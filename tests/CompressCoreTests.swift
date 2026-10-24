// Tests for CompressCore.swift (the Compress to Zip app minus its window).
// Built and run by tests/test_compress.sh:  swiftc CompressCore.swift tests/CompressCoreTests.swift
import Foundation

var passed = 0, failed = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { passed += 1; print("  PASS  \(name)") } else { failed += 1; print("  FAIL  \(name)  (\(detail()))") }
}

let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("cz-tests-\(UUID().uuidString)")
try! fm.createDirectory(at: root, withIntermediateDirectories: true)
// No `defer` here: top-level defer never runs because exit() ends the process first,
// which is how earlier runs left test zips behind in $TMPDIR. Cleanup is explicit below.
let script = URL(fileURLWithPath: CommandLine.arguments[1])  // compress-to-zip.zsh
func write(_ name: String, _ text: String, in dir: URL = root) -> URL {
    let u = dir.appendingPathComponent(name)
    try! fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! text.write(to: u, atomically: true, encoding: .utf8)
    return u
}
func entries(_ zip: URL) -> [String] {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo"); p.arguments = ["-1", zip.path]
    let o = Pipe(); p.standardOutput = o; try! p.run(); p.waitUntilExit()
    return String(decoding: o.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init).sorted()
}

// uniqueURL
let downloads = root.appendingPathComponent("Downloads"); try! fm.createDirectory(at: downloads, withIntermediateDirectories: true)
check("unique name is <base>.zip when free", CompressCore.uniqueURL(in: downloads, fileName: "Archive.zip").lastPathComponent == "Archive.zip")
_ = write("Archive.zip", "x", in: downloads); _ = write("Archive 2.zip", "x", in: downloads)
check("unique name skips taken names (→ Archive 3.zip)", CompressCore.uniqueURL(in: downloads, fileName: "Archive.zip").lastPathComponent == "Archive 3.zip")

// labels
check("sizes read like Finder", CompressCore.humanSize(0) == "Zero KB" || CompressCore.humanSize(0) == "Zero bytes", CompressCore.humanSize(0))
check("1 item / 3 items", CompressCore.itemsLabel(1) == "1 item" && CompressCore.itemsLabel(3) == "3 items")

// compress one file: zip made in a private temp folder, originals untouched
let src = root.appendingPathComponent("src"); try! fm.createDirectory(at: src, withIntermediateDirectories: true)
let doc = write("report one.pdf", "hello", in: src)
let one = try! CompressCore.compress([doc], script: script)
check("one file → <name>.zip", one.zip.lastPathComponent == "report one.pdf.zip", one.zip.path)
check("the zip is made away from the originals", one.zip.deletingLastPathComponent().path != src.path)
check("the zip holds just that file", entries(one.zip) == ["report one.pdf"], "\(entries(one.zip))")
check("result reports size and count", one.bytes > 0 && one.itemCount == 1)
check("the original is untouched", (try? String(contentsOf: doc, encoding: .utf8)) == "hello")

// download: lands in the folder, never overwrites, temp folder cleaned up
let tempDir = one.zip.deletingLastPathComponent()
_ = write("report one.pdf.zip", "older zip", in: downloads)
let landed = try! CompressCore.download(one.zip, to: downloads)
check("Download never overwrites (→ '… 2.zip')", landed.lastPathComponent == "report one.pdf 2.zip", landed.lastPathComponent)
check("the existing zip is left alone", (try? String(contentsOf: downloads.appendingPathComponent("report one.pdf.zip"), encoding: .utf8)) == "older zip")
check("the downloaded zip is the real archive", entries(landed) == ["report one.pdf"])
check("the private temp folder is cleaned up", !fm.fileExists(atPath: tempDir.path))

// several items → Archive.zip
let dir = root.appendingPathComponent("src/My Folder"); try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
_ = write("a.txt", "a", in: dir)
let c = write("c.txt", "c", in: src)
let many = try! CompressCore.compress([doc, c, dir], script: script)
check("several items → Archive.zip", many.zip.lastPathComponent == "Archive.zip" && many.itemCount == 3)
check("Archive.zip holds every item", entries(many.zip) == ["My Folder/", "My Folder/a.txt", "c.txt", "report one.pdf"], "\(entries(many.zip))")

// Save As replaces only what the user confirmed in the panel
let chosen = write("mine.zip", "old", in: root)
let saved = try! CompressCore.save(many.zip, as: chosen)
check("Save As puts the zip exactly where chosen", saved == chosen && entries(saved).count == 4)

// failures are reported, never shown as success
do { _ = try CompressCore.compress([], script: script); check("nothing selected is an error", false) }
catch { check("nothing selected is an error", "\(error)".contains("Nothing")) }
do { _ = try CompressCore.compress([doc], script: URL(fileURLWithPath: "/nope.zsh")); check("missing script is an error", false) }
catch { check("missing script is an error", "\(error)".contains("missing")) }
let liar = write("liar.zsh", "print -r -- /tmp/not-really-there-\(UUID().uuidString).zip\nexit 0\n")
do { _ = try CompressCore.compress([doc], script: liar); check("a script that claims success but made no zip is a FAILURE", false) }
catch { check("a script that claims success but made no zip is a FAILURE", true) }
do { _ = try CompressCore.compress([root.appendingPathComponent("does-not-exist.txt")], script: script); check("a missing input is an error", false) }
catch { check("a missing input is an error", true) }

try? fm.removeItem(at: root)
check("the tests leave no files behind", !fm.fileExists(atPath: root.path))
print("\n  \(passed) passed, \(failed) failed\n")
exit(failed == 0 ? 0 : 1)

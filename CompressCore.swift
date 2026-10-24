// CompressCore.swift — everything in the Compress to Zip app that is not UI.
// Kept apart so tests/CompressCoreTests.swift can exercise it without a window.
//
// The zipping itself is compress-to-zip.zsh (the same tested script the Quick
// Action runs), called with COMPRESS_OUT_DIR so the zip is made in a private
// temporary folder. "Download" then moves it into ~/Downloads under a name that
// never overwrites anything, and Finder shows it.
import Foundation

enum CompressError: Error, CustomStringConvertible {
    case nothingToCompress
    case scriptMissing(String)
    case failed(String)
    var description: String {
        switch self {
        case .nothingToCompress: return "Nothing to compress."
        case .scriptMissing(let p): return "The compress script is missing (\(p)). Reinstall the app."
        case .failed(let why): return why
        }
    }
}

struct CompressResult {
    let zip: URL          // where the zip is now
    let itemCount: Int
    let bytes: Int64
}

enum CompressCore {
    /// "<base>.zip", or "<base> 2.zip", "<base> 3.zip"... — the first that does not exist in `dir`.
    static func uniqueURL(in dir: URL, fileName: String, fm: FileManager = .default) -> URL {
        let base = fileName.hasSuffix(".zip") ? String(fileName.dropLast(4)) : fileName
        var candidate = dir.appendingPathComponent("\(base).zip")
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(n).zip")
            n += 1
        }
        return candidate
    }

    /// "12 KB", "3.4 MB": the way Finder shows sizes.
    static func humanSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func itemsLabel(_ n: Int) -> String { n == 1 ? "1 item" : "\(n) items" }

    /// Runs the script with the files, zip made in a new temp folder. Blocking: call off the main thread.
    static func compress(_ files: [URL], script: URL, fm: FileManager = .default) throws -> CompressResult {
        guard !files.isEmpty else { throw CompressError.nothingToCompress }
        guard fm.fileExists(atPath: script.path) else { throw CompressError.scriptMissing(script.path) }
        let work = fm.temporaryDirectory.appendingPathComponent("CompressToZip-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [script.path] + files.map { $0.path }
        var env = ProcessInfo.processInfo.environment
        env["COMPRESS_OUT_DIR"] = work.path
        env["COMPRESS_QUIET"] = "1"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        let lastLine = String(decoding: outData, as: UTF8.self)
            .split(separator: "\n").last.map(String.init) ?? ""
        let zip = URL(fileURLWithPath: lastLine)
        // Trust the file, not the exit code alone: a zip that is not there is a failure
        // even if the script said 0.
        guard p.terminationStatus == 0, !lastLine.isEmpty, fm.fileExists(atPath: zip.path) else {
            let why = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            try? fm.removeItem(at: work)
            throw CompressError.failed(why.isEmpty ? "Could not compress the selection." : why)
        }
        let size = ((try? fm.attributesOfItem(atPath: zip.path))?[.size] as? NSNumber)?.int64Value ?? 0
        return CompressResult(zip: zip, itemCount: files.count, bytes: size)
    }

    /// Moves the zip into `folder` without overwriting anything; returns where it landed.
    static func download(_ zip: URL, to folder: URL, fm: FileManager = .default) throws -> URL {
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = uniqueURL(in: folder, fileName: zip.lastPathComponent, fm: fm)
        try fm.moveItem(at: zip, to: dest)
        try? fm.removeItem(at: zip.deletingLastPathComponent()) // the private temp folder, now empty
        return dest
    }

    /// Moves the zip to an exact place the user picked in a Save panel (which already
    /// asked them about replacing an existing file).
    static func save(_ zip: URL, as dest: URL, fm: FileManager = .default) throws -> URL {
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: zip, to: dest)
        try? fm.removeItem(at: zip.deletingLastPathComponent())
        return dest
    }

    static var downloadsFolder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }
}

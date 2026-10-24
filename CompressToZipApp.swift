// CompressToZipApp.swift — the Compress to Zip window.
//
//   drop files (or click to choose) → it zips them → Download saves the zip to
//   ~/Downloads and shows it in Finder. Save As… picks another place.
//   Dropping files on the Dock icon does the same.
//
// All the work is in CompressCore.swift; this file is only the window.
// `CompressToZip --headless [--download-dir DIR] FILE...` runs the same
// compress-and-download path with no window, which is what the tests drive.
import AppKit
import UniformTypeIdentifiers

// MARK: - Drop area

final class DropView: NSView {
    var onFiles: (([URL]) -> Void)?
    var enabled = true { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }

    let icon = NSImageView()
    let title = NSTextField(labelWithString: "Drop files or folders here")
    let subtitle = NSTextField(labelWithString: "or click to choose")
    let spinner = NSProgressIndicator()

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        icon.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: "Zip")
        icon.symbolConfiguration = .init(pointSize: 44, weight: .light)
        icon.contentTintColor = .secondaryLabelColor
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.alignment = .center
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isHidden = true
        let stack = NSStackView(views: [icon, spinner, title, subtitle])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel("Drop files or folders here, or click to choose")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14)
        (hovering ? NSColor.controlAccentColor.withAlphaComponent(0.10) : NSColor.quaternaryLabelColor.withAlphaComponent(0.08)).setFill()
        path.fill()
        path.lineWidth = 2
        path.setLineDash([8, 6], count: 2, phase: 0)
        (hovering ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setStroke()
        path.stroke()
    }

    private func urls(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard enabled, !urls(sender).isEmpty else { return [] }
        hovering = true
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { hovering = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hovering = false
        let files = urls(sender)
        guard enabled, !files.isEmpty else { return false }
        onFiles?(files)
        return true
    }
    override func mouseDown(with event: NSEvent) { chooseFiles() }

    func chooseFiles() {
        guard enabled else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Compress"
        panel.message = "Choose files or folders to zip"
        if panel.runModal() == .OK, !panel.urls.isEmpty { onFiles?(panel.urls) }
    }
}

// MARK: - Window controller

final class MainController: NSObject {
    let window: NSWindow
    let drop = DropView()
    let result = NSStackView()
    let fileIcon = NSImageView()
    let fileName = NSTextField(labelWithString: "")
    let fileDetail = NSTextField(labelWithString: "")
    let status = NSTextField(labelWithString: "")
    let downloadButton = NSButton(title: "Download", target: nil, action: nil)
    let saveAsButton = NSButton(title: "Save As…", target: nil, action: nil)
    let againButton = NSButton(title: "Compress more", target: nil, action: nil)

    var current: CompressResult?
    var saved: URL?
    let script: URL

    init(script: URL) {
        self.script = script
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Compress to Zip"
        window.isReleasedWhenClosed = false
        window.center()

        drop.onFiles = { [weak self] in self?.compress($0) }
        drop.translatesAutoresizingMaskIntoConstraints = false

        fileIcon.image = NSWorkspace.shared.icon(for: .zip)
        fileIcon.imageScaling = .scaleProportionallyUpOrDown
        fileIcon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        fileIcon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        fileName.font = .systemFont(ofSize: 17, weight: .semibold)
        fileName.lineBreakMode = .byTruncatingMiddle
        fileDetail.textColor = .secondaryLabelColor
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)

        for (b, sel) in [(downloadButton, #selector(downloadTapped)), (saveAsButton, #selector(saveAsTapped)), (againButton, #selector(reset))] {
            b.target = self
            b.action = sel
            b.bezelStyle = .rounded
            b.controlSize = .large
        }
        // Click-only on purpose. With Return as its key, a Return typed in another
        // app at the moment this window came forward (files dropped on the Dock
        // icon) saved the zip without the user asking; seen once in testing.
        downloadButton.keyEquivalent = ""
        downloadButton.bezelColor = .controlAccentColor
        downloadButton.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        downloadButton.imagePosition = .imageLeading
        againButton.bezelStyle = .inline
        againButton.controlSize = .regular

        let buttons = NSStackView(views: [saveAsButton, downloadButton])
        buttons.spacing = 10
        result.setViews([fileIcon, fileName, fileDetail, buttons, status, againButton], in: .center)
        result.orientation = .vertical
        result.spacing = 8
        result.setCustomSpacing(18, after: fileDetail)
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isHidden = true

        let content = NSView()
        content.addSubview(drop)
        content.addSubview(result)
        NSLayoutConstraint.activate([
            drop.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            drop.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            drop.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            drop.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            result.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            result.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            result.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 24),
        ])
        window.contentView = content
    }

    // MARK: states

    func compress(_ files: [URL]) {
        discardUnsaved()
        drop.isHidden = false
        result.isHidden = true
        drop.enabled = false
        drop.icon.isHidden = true
        drop.spinner.isHidden = false
        drop.spinner.startAnimation(nil)
        drop.title.stringValue = "Compressing \(CompressCore.itemsLabel(files.count))…"
        drop.title.textColor = .labelColor
        drop.subtitle.stringValue = files.count == 1 ? files[0].lastPathComponent : ""
        let script = self.script
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Result { try CompressCore.compress(files, script: script) }
            DispatchQueue.main.async { self.finished(outcome) }
        }
    }

    private func finished(_ outcome: Result<CompressResult, Error>) {
        drop.spinner.stopAnimation(nil)
        drop.spinner.isHidden = true
        drop.icon.isHidden = false
        drop.enabled = true
        switch outcome {
        case .success(let r):
            current = r
            saved = nil
            fileName.stringValue = r.zip.lastPathComponent
            fileDetail.stringValue = "\(CompressCore.humanSize(r.bytes)) · \(CompressCore.itemsLabel(r.itemCount))"
            status.stringValue = "Ready. Download saves it to your Downloads folder."
            downloadButton.title = "Download"
            downloadButton.isEnabled = true
            saveAsButton.isHidden = false
            drop.isHidden = true
            result.isHidden = false
        case .failure(let e):
            drop.title.stringValue = "Couldn't compress that"
            drop.title.textColor = .systemRed
            drop.subtitle.stringValue = "\(e)  Drop to try again."
        }
    }

    @objc func downloadTapped() {
        if let done = saved { reveal(done); return }
        guard let r = current else { return }
        deliver { try CompressCore.download(r.zip, to: CompressCore.downloadsFolder) }
    }

    /// Show the file selected in Finder. Asked twice, a moment apart: right after a
    /// move, Finder can still be refreshing a folder window that is already open
    /// and select whatever was there before (seen in testing: it selected
    /// "Archive 2" instead of the new "Archive 10.zip").
    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc func saveAsTapped() {
        guard let r = current, saved == nil else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = r.zip.lastPathComponent
        panel.allowedContentTypes = [.zip]
        panel.directoryURL = CompressCore.downloadsFolder
        panel.beginSheetModal(for: window) { resp in
            guard resp == .OK, let dest = panel.url else { return }
            self.deliver { try CompressCore.save(r.zip, as: dest) }
        }
    }

    private func deliver(_ move: () throws -> URL) {
        do {
            let dest = try move()
            saved = dest
            status.stringValue = "Saved to \(dest.deletingLastPathComponent().lastPathComponent) ✓"
            status.textColor = .systemGreen
            fileName.stringValue = dest.lastPathComponent
            downloadButton.title = "Show in Finder"
            saveAsButton.isHidden = true
            reveal(dest)
        } catch {
            status.stringValue = "Couldn't save: \(error.localizedDescription)"
            status.textColor = .systemRed
        }
    }

    @objc func reset() {
        discardUnsaved()
        status.textColor = .secondaryLabelColor
        drop.title.stringValue = "Drop files or folders here"
        drop.title.textColor = .labelColor
        drop.subtitle.stringValue = "or click to choose"
        result.isHidden = true
        drop.isHidden = false
    }

    /// A zip that was never downloaded lives in a private temp folder; clean it up.
    /// (It's only a copy: the originals are never touched.)
    func discardUnsaved() {
        if let r = current, saved == nil { try? FileManager.default.removeItem(at: r.zip.deletingLastPathComponent()) }
        current = nil
        saved = nil
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: MainController!
    var pending: [URL] = []

    func applicationDidFinishLaunching(_ n: Notification) {
        let script = Bundle.main.url(forResource: "compress-to-zip", withExtension: "zsh")
            ?? URL(fileURLWithPath: "/missing/compress-to-zip.zsh")
        controller = MainController(script: script)
        buildMenu()
        controller.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !pending.isEmpty { controller.compress(pending); pending = [] }
    }

    // Files dropped on the Dock icon (or opened with the app).
    func application(_ app: NSApplication, open urls: [URL]) {
        let files = urls.filter { $0.isFileURL }
        guard !files.isEmpty else { return }
        if let c = controller { c.window.makeKeyAndOrderFront(nil); c.compress(files) } else { pending += files }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ n: Notification) { controller?.discardUnsaved() }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Compress to Zip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        let open = fileMenu.addItem(withTitle: "Choose Files…", action: #selector(chooseFiles), keyEquivalent: "o")
        open.target = self
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        NSApp.mainMenu = main
    }
    @objc func chooseFiles() { controller.window.makeKeyAndOrderFront(nil); controller.drop.chooseFiles() }
}

@main
struct CompressToZipMain {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--headless") { exit(headless(Array(args.dropFirst()))) }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    /// Same compress + download path as the window, with no UI. For tests and scripts.
    static func headless(_ args: [String]) -> Int32 {
        var files: [URL] = []
        var dir = CompressCore.downloadsFolder
        var script = Bundle.main.url(forResource: "compress-to-zip", withExtension: "zsh")
        var it = args.makeIterator()
        while let a = it.next() {
            switch a {
            case "--headless": continue
            case "--download-dir": if let d = it.next() { dir = URL(fileURLWithPath: d) }
            case "--script": if let s = it.next() { script = URL(fileURLWithPath: s) }
            default: files.append(URL(fileURLWithPath: a))
            }
        }
        guard let script else { fputs("compress script not found\n", stderr); return 2 }
        do {
            let r = try CompressCore.compress(files, script: script)
            let dest = try CompressCore.download(r.zip, to: dir)
            print(dest.path)
            return 0
        } catch {
            fputs("\(error)\n", stderr)
            return 1
        }
    }
}

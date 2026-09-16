// AirDropSend.swift — open the AirDrop picker for the given files and stay alive
// until the transfer is done.
//
// Why a compiled app and not a script: NSSharingService's picker is a real
// AppKit window. It needs a process running a real NSApplication event loop to
// receive the click. `osascript` cannot provide one — and the failure is nasty
// rather than obvious: the picker DRAWS (the window server does that), but no
// mouse event is ever dispatched to it, so clicking a recipient produces no
// delegate callback at all, the window goes half-transparent instead of
// closing, and nothing is sent. Touching NSApplication from osascript to fix
// that suppresses the picker entirely. There is no script-shaped answer here.
import AppKit

let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Caches/airdrop-send.log")

func note(_ m: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "\(stamp)  \(m)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let fh = try? FileHandle(forWritingTo: logURL) {
        defer { try? fh.close() }
        _ = try? fh.seekToEnd()
        try? fh.write(contentsOf: data)
    } else {
        try? data.write(to: logURL)
    }
}

final class ShareDelegate: NSObject, NSSharingServiceDelegate {
    func sharingService(_ s: NSSharingService, willShareItems items: [Any]) {
        note("willShareItems — picker presented")
    }
    // The transfer is asynchronous, so do not quit the instant this arrives.
    func sharingService(_ s: NSSharingService, didShareItems items: [Any]) {
        note("didShareItems — accepted by the service")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { NSApp.terminate(nil) }
    }
    func sharingService(_ s: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        let e = error as NSError
        // NSUserCancelledError (3072) is the user pressing Cancel: not a fault.
        if e.code == NSUserCancelledError {
            note("cancelled by user")
        } else {
            note("FAILED — \(e.domain) code=\(e.code) — \(e.localizedDescription)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
    }
}

let paths = Array(CommandLine.arguments.dropFirst())
guard !paths.isEmpty else { note("no files given"); exit(0) }
let urls = paths.map { URL(fileURLWithPath: $0) }
note("--- invoked with \(urls.count) item(s) ---")
for u in urls { note("  \(u.path)") }

guard let svc = NSSharingService(named: .sendViaAirDrop) else {
    note("AirDrop sharing service unavailable"); exit(1)
}
note("canPerform = \(svc.canPerform(withItems: urls))")

let app = NSApplication.shared
let delegate = ShareDelegate()
svc.delegate = delegate
// Accessory: no Dock icon, no menu bar, but a real activatable app — which is
// exactly what the picker needs and what a script cannot be.
app.setActivationPolicy(.accessory)

// Hard ceiling, so a picker left open forever does not leave a process behind.
DispatchQueue.main.asyncAfter(deadline: .now() + 900) {
    note("timeout — quitting"); NSApp.terminate(nil)
}

DispatchQueue.main.async {
    app.activate(ignoringOtherApps: true)
    svc.perform(withItems: urls)
    note("perform(withItems:) called — picker should be on screen")
}

app.run()

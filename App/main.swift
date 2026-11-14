import AppKit
import WebKit

// Full-screen window showing index.html — the same piece as the screensaver.
// Esc, Q or a click quits.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSScreen.main!.frame
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .mainMenu + 1
        window.backgroundColor = .black
        let web = WKWebView(frame: frame)
        window.contentView = web
        let page = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "index.html")
        web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 || e.charactersIgnoringModifiers == "q" { NSApp.terminate(nil) }
            return e
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { e in NSApp.terminate(nil); return e }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

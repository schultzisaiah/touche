import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay: OverlayController
    private let center: TouchCenter
    private var statusItem: StatusItemController?

    override init() {
        Prefs.registerDefaults()
        overlay = OverlayController()
        center = TouchCenter(overlay: overlay)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--snapshots"), i + 1 < CommandLine.arguments.count {
            Snapshots.render(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            NSApp.terminate(nil)
            return
        }
        statusItem = StatusItemController(center: center, overlay: overlay)
        center.watcher.start()
        if CommandLine.arguments.contains("--preview") {
            center.preview(.fido2)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [center] in center.preview(.openPGP) }
        }
    }

    /// `log stream` is a child process, and it would otherwise outlive the app.
    func applicationWillTerminate(_ notification: Notification) {
        center.watcher.stop()
    }
}

import AppKit

// Plain AppKit entry point: a menu bar app with no windows has no use for a SwiftUI App and its Scene.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}

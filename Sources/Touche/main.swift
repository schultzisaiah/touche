import AppKit

// Settings saved under Touché's earlier bundle ID, dev.isaiah.touche, come along once without overwriting
// anything already set here.
let defaults = UserDefaults.standard
if !defaults.bool(forKey: "importedLegacySettings") {
    if let legacy = defaults.persistentDomain(forName: "dev.isaiah.touche") {
        let current = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        for (key, value) in legacy where current[key] == nil { defaults.set(value, forKey: key) }
    }
    defaults.set(true, forKey: "importedLegacySettings")
}

// Plain AppKit entry point: a menu bar app with no windows has no use for a SwiftUI App and its Scene.
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    let app = NSApplication.shared
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}

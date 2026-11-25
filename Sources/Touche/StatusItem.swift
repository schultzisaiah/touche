import AppKit
import Combine
import ServiceManagement

/// The menu bar key: a tapping hand while a request waits, with recent requests, previews, and settings in its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let center: TouchCenter
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var watching: AnyCancellable?

    init(center: TouchCenter, overlay: OverlayController) {
        self.center = center
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        watching = overlay.$alerts.sink { [weak self] alerts in
            let waiting = alerts.contains { !$0.touched }
            let image = NSImage(systemSymbolName: waiting ? "hand.tap.fill" : "key.horizontal.fill", accessibilityDescription: "Touché")
            image?.isTemplate = true
            self?.item.button?.image = image
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(disabled(center.watcher.running ? "Watching for touch requests" : "Not watching: log stream isn't running"))

        if !center.recent.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Recent"))
            for record in center.recent {
                let when = record.at.formatted(date: .omitted, time: .shortened)
                let item = disabled("\(when)  \(record.requester?.text ?? "\(record.kind.label) request")")
                item.image = NSImage(systemSymbolName: record.touched ? "checkmark.circle.fill" : "circle.dashed", accessibilityDescription: nil)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Preview"))
        for kind in TouchKind.allCases {
            let item = action("\(kind.label) Touch", #selector(preview(_:)))
            item.representedObject = kind.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let sizes = NSMenu()
        let current = PillSize(rawValue: UserDefaults.standard.string(forKey: Prefs.size) ?? "") ?? .large
        for size in PillSize.allCases {
            let item = action(size.label, #selector(pickSize(_:)))
            item.representedObject = size.rawValue
            item.state = size == current ? .on : .off
            sizes.addItem(item)
        }
        let size = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        size.submenu = sizes
        menu.addItem(size)
        let positions = NSMenu()
        let place = PillPosition(rawValue: UserDefaults.standard.string(forKey: Prefs.position) ?? "") ?? .top
        for position in PillPosition.allCases {
            let item = action(position.label, #selector(pickPosition(_:)))
            item.representedObject = position.rawValue
            item.state = position == place ? .on : .off
            positions.addItem(item)
        }
        let position = NSMenuItem(title: "Position", action: nil, keyEquivalent: "")
        position.submenu = positions
        menu.addItem(position)
        let sounds = NSMenu()
        let chosen = UserDefaults.standard.string(forKey: Prefs.sound)
        for name in Prefs.sounds {
            let item = action(name, #selector(pickSound(_:)))
            item.representedObject = name
            item.state = name == chosen ? .on : .off
            sounds.addItem(item)
            if name == "None" { sounds.addItem(.separator()) }
        }
        let sound = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        sound.submenu = sounds
        menu.addItem(sound)
        menu.addItem(toggle("Glow Around the Screen", Prefs.glow))
        menu.addItem(toggle("Show on Every Display", Prefs.allDisplays))
        let login = action("Open at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(quitItem())
    }

    /// "Quit Touché", then the running version, dimmed to match the ⌘Q beside it.
    private func quitItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Quit Touché", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return item }
        let font = NSFont.menuFont(ofSize: 0)
        let title = NSMutableAttributedString(string: "Quit Touché", attributes: [.font: font])
        title.append(NSAttributedString(string: "  v\(version)", attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]))
        item.attributedTitle = title
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func toggle(_ title: String, _ key: String) -> NSMenuItem {
        let item = action(title, #selector(flip(_:)))
        item.representedObject = key
        item.state = UserDefaults.standard.bool(forKey: key) ? .on : .off
        return item
    }

    @objc private func preview(_ sender: NSMenuItem) {
        guard let kind = (sender.representedObject as? String).flatMap(TouchKind.init(rawValue:)) else { return }
        center.preview(kind)
    }

    @objc private func pickSize(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.representedObject as? String, forKey: Prefs.size)
    }

    @objc private func pickPosition(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.representedObject as? String, forKey: Prefs.position)
    }

    /// Plays the pick, so you hear what you chose.
    @objc private func pickSound(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        UserDefaults.standard.set(name, forKey: Prefs.sound)
        NSSound(named: name)?.play()
    }

    @objc private func flip(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.informativeText = "Open at Login needs Touché in /Applications. Run ./build.sh install."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}

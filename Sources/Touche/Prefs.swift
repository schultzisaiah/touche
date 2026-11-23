import Foundation

enum PillSize: String, CaseIterable, Identifiable {
    case compact, regular, large
    var id: Self { self }

    var label: String { rawValue.capitalized }

    /// Pills are laid out at this scale (not scaleEffect) so stacked pills don't overlap. Large is a card instead.
    var scale: CGFloat {
        switch self {
        case .compact: 0.86
        case .regular, .large: 1
        }
    }
}

enum PillPosition: String, CaseIterable, Identifiable {
    case top, center
    var id: Self { self }

    var label: String { self == .top ? "Under the Notch" : "Center of the Screen" }
}

enum Prefs {
    static let size = "size"
    static let position = "position"
    /// A macOS system sound's name, or "None".
    static let sound = "soundName"
    static let glow = "glow"
    static let allDisplays = "allDisplays"

    static let sounds = ["None", "Pop", "Tink", "Purr", "Morse", "Glass", "Ping", "Hero", "Funk", "Submarine", "Blow", "Bottle", "Frog", "Sosumi", "Basso"]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [size: PillSize.large.rawValue, position: PillPosition.top.rawValue, sound: "Pop", glow: false, allDisplays: true])
    }
}

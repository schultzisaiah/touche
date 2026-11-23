import AppKit
import SwiftUI

enum Brand {
    /// Touched.
    static let mint = "#00C878"

    /// Waiting, whatever asked: black in dark mode and white in light mode, so only the checkmark brings color.
    static let waiting = NSColor(name: "waiting") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .white
    }

    /// WCAG's minimum contrast for small text.
    static let minimumContrast = 4.5

    /// A shade of `color` that's readable as text or an icon: deepened for light mode, or lifted for dark mode,
    /// only as far as it takes. Bright tints stay as they are for fills and glows, where they don't need to be read.
    static func ink(_ color: NSColor, dark: Bool) -> NSColor {
        guard let c = color.usingColorSpace(.sRGB) else { return color }
        // Roughly what text sits on: the alert glass, with a wash of the tint over it.
        let surface = NSColor(srgbRed: dark ? 0.27 : 0.88, green: dark ? 0.27 : 0.88, blue: dark ? 0.27 : 0.88, alpha: 1)
        guard contrast(c, surface) < minimumContrast else { return c }

        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        c.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // Darkening alone turns orange brown, so richer as it deepens. Lifting needs paler, since it starts at full brightness.
        var steps = 0
        var shade = c
        while contrast(shade, surface) < minimumContrast, steps < 50 {
            steps += 1
            let t = CGFloat(steps) / 50
            shade = dark
                ? NSColor(hue: hue, saturation: saturation * (1 - t), brightness: brightness + (1 - brightness) * t, alpha: alpha)
                : NSColor(hue: hue, saturation: min(1, saturation * (1 + t)), brightness: brightness * (1 - t), alpha: alpha)
            shade = shade.usingColorSpace(.sRGB) ?? shade
        }
        return shade
    }

    /// WCAG contrast ratio, from 1 (identical) to 21 (black on white).
    static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private static func luminance(_ color: NSColor) -> Double {
        guard let c = color.usingColorSpace(.sRGB) else { return 0 }
        let linear = { (v: CGFloat) -> Double in
            let v = Double(v)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }

    static func nsColor(_ hex: String) -> NSColor {
        let v = Int(hex.dropFirst(), radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    /// This color as text or an icon, readable in `scheme`. See `Brand.ink`.
    func ink(on scheme: ColorScheme) -> Color {
        Color(nsColor: Brand.ink(NSColor(self), dark: scheme == .dark))
    }

    init(hex: String) {
        self.init(nsColor: Brand.nsColor(hex))
    }
}

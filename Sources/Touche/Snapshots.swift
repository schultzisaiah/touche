import AppKit
import SwiftUI

/// `Touche --snapshots DIR` renders the README images from the real views, under a stand-in notch and menu bar,
/// once each for dark and light mode (`card-dark.jpg`, `card-light.jpg`, ...), then quits.
@MainActor
enum Snapshots {
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for scheme in [ColorScheme.dark, .light] {
            NSAppearance.current = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let signing = Requester.signing(repo: "schultzisaiah/touche", subject: "Retry S3 uploads on timeout")
            save(Notch(height: 270) {
                TouchCard(alert: TouchAlert(kind: .fido2, requester: signing, since: Date().addingTimeInterval(-4)), onDismiss: {})
            }, "card", scheme, to: dir)
            save(Notch(height: 270) {
                TouchCard(alert: TouchAlert(kind: .fido2, requester: signing, touched: true), onDismiss: {})
            }, "touched", scheme, to: dir)
            save(Notch(height: 270) {
                VStack(spacing: 10) {
                    TouchPill(alert: TouchAlert(kind: .fido2, requester: .ssh(destination: "deploy@build-01", command: "systemctl restart api"),
                                                since: Date().addingTimeInterval(-7)), scale: 1, onDismiss: {})
                    TouchPill(alert: TouchAlert(kind: .openPGP, requester: .signing(repo: "schultzisaiah/dotfiles", subject: "Sign tags with the card"),
                                                touched: true), scale: 1, onDismiss: {})
                    TouchPill(alert: TouchAlert(kind: .fido2, since: Date().addingTimeInterval(-12)), scale: PillSize.compact.scale, onDismiss: {})
                }
            }, "pills", scheme, to: dir)
        }
    }

    private static func save(_ view: some View, _ name: String, _ scheme: ColorScheme, to dir: URL) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme).environment(\.isSnapshot, true))
        renderer.scale = 2
        // Full-bleed gradients are several MB as PNG and a fraction of that as JPEG.
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let data = NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        else { return }
        try? data.write(to: dir.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").jpg"))
    }
}

extension EnvironmentValues {
    /// Set for `--snapshots`: ImageRenderer can't draw glass or materials, so alerts get a plain panel instead.
    @Entry var isSnapshot = false
}

/// The top of a MacBook screen: a wallpaper, a slice of menu bar, and the notch, with the alerts hanging under it.
private struct Notch<Content: View>: View {
    let height: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    private let menuBar: CGFloat = 32

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: scheme == .dark
                           ? [Color(red: 0.16, green: 0.12, blue: 0.30), Color(red: 0.08, green: 0.24, blue: 0.32)]
                           : [Color(red: 0.90, green: 0.86, blue: 0.98), Color(red: 0.80, green: 0.92, blue: 0.95)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle()
                .fill(scheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.45))
                .frame(height: menuBar)
            UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous)
                .fill(.black)
                .frame(width: 190, height: menuBar)
            content
                .padding(.top, menuBar + 12)
        }
        .frame(width: 680, height: height)
    }
}

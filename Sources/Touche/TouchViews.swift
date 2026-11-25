import SwiftUI

struct OverlayRoot: View {
    @ObservedObject var controller: OverlayController
    @AppStorage(Prefs.size) private var size = PillSize.large
    @AppStorage(Prefs.position) private var position = PillPosition.top

    var body: some View {
        VStack(spacing: 10) {
            ForEach(controller.alerts) { alert in
                let offset = controller.swipeOffsets[alert.kind] ?? 0
                Group {
                    if size == .large {
                        TouchCard(
                            alert: alert,
                            onDismiss: { controller.dismiss(alert.kind) },
                            onHoverChange: { controller.setHovering(alert.kind, $0) }
                        )
                    } else {
                        TouchPill(
                            alert: alert,
                            scale: size.scale,
                            onDismiss: { controller.dismiss(alert.kind) },
                            onHoverChange: { controller.setHovering(alert.kind, $0) }
                        )
                    }
                }
                .offset(x: offset)
                .opacity(max(0, 1 - Double(abs(offset)) / 600))
                // A background sits in the alert's resting frame (offset doesn't move layout), so the hint stays put as the alert slides off it.
                .background { SwipeHint(offset: offset) }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { controller.dragSwipe(alert.kind, $0.translation.width) }
                        .onEnded { controller.endSwipe(alert.kind, flick: $0.predictedEndTranslation.width - $0.translation.width) }
                )
                .transition(position == .top ? Self.dropIn : Self.popIn)
            }
        }
        .padding(.top, position == .top ? 10 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position == .top ? .top : .center)
        // Soft left and right edges, so a swiped alert dissolves into the panel's edge instead of being cut off.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.11),
                    .init(color: .black, location: 0.89),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        )
    }

    /// Drops down from under the notch.
    private static let dropIn = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.4, anchor: .top)
            .combined(with: .offset(y: -40))
            .combined(with: .opacity),
        removal: .scale(scale: 0.85, anchor: .top)
            .combined(with: .offset(y: -16))
            .combined(with: .opacity)
    )

    /// Pops out from the middle of the screen.
    private static let popIn = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.3).combined(with: .opacity),
        removal: .scale(scale: 0.8).combined(with: .opacity)
    )
}

/// What letting go will do, revealed behind an alert as it's swiped right.
private struct SwipeHint: View {
    let offset: CGFloat

    var body: some View {
        let progress = min(max(offset, 0) / SwipeOutcome.threshold, 1)
        let armed = offset >= SwipeOutcome.threshold
        GeometryReader { geo in
            Label("Dismiss", systemImage: "xmark")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .modifier(HintBackground(armed: armed))
                .scaleEffect(armed ? 1.08 : 0.85 + 0.15 * progress)
                .animation(.spring(response: 0.3, dampingFraction: 0.55), value: armed)
                .alignmentGuide(.leading) { -SwipeOutcome.hintX(offset: offset, width: geo.size.width, hintWidth: $0.width) }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .opacity(offset <= 0 ? 0 : Double(progress))
        .allowsHitTesting(false)
    }
}

/// The swipe hint's capsule: Liquid Glass on macOS 26 and later, frosted material before that.
private struct HintBackground: ViewModifier {
    let armed: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().strokeBorder(.white.opacity(armed ? 0.35 : 0.15)))
        }
    }
}

struct TouchPill: View {
    let alert: TouchAlert
    let scale: CGFloat
    let onDismiss: () -> Void
    var onHoverChange: (Bool) -> Void = { _ in }

    @State private var hovering = false
    @State private var shakes: CGFloat = 0
    @State private var bounce = 0

    private var s: CGFloat { scale }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let waited = ctx.date.timeIntervalSince(alert.since)
            HStack(spacing: 12 * s) {
                TouchRing(tint: alert.tint, touched: alert.touched, bounce: bounce, scale: s)

                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(alert.touched ? "Touched" : "Touch your YubiKey")
                        .font(.system(size: 14 * s, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Label {
                        Text(subtitle(waited))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .contentTransition(.numericText())
                    } icon: {
                        Image(systemName: alert.requester?.symbol ?? alert.kind.symbol)
                    }
                    .font(.system(size: 12 * s, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)

                IconButton(systemImage: "xmark", help: "Dismiss", scale: s, action: onDismiss)
                    .opacity(hovering ? 1 : 0.75)
            }
            .padding(.leading, 8 * s)
            .padding(.trailing, 10 * s)
            .padding(.vertical, 8 * s)
            .frame(width: 440 * s)
            .background(GlassBackground(shape: Capsule(), tint: alert.tint))
            .shadow(color: alert.tint.opacity(0.55), radius: 22, y: 6)
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            .scaleEffect(hovering ? 1.025 : 1)
            .modifier(ShakeEffect(shakes: shakes))
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: hovering)
            .animation(.snappy, value: Int(waited))
        }
        .onHover { hovering = $0; onHoverChange($0) }
        .onAppear(perform: wiggle)
        .onChange(of: alert.token) { wiggle() }
    }

    /// Who's asking, and how long they've waited. Unknown requesters show the kind, so an unfamiliar line stands out.
    private func subtitle(_ waited: TimeInterval) -> String {
        let who = alert.requester?.text ?? "\(alert.kind.label) request"
        return alert.touched ? who : "\(who) · \(waitedText(waited))"
    }

    private func wiggle() {
        bounce += 1
        withAnimation(.easeInOut(duration: 0.6).delay(0.25)) { shakes += 1 }
    }
}

/// How long the key has been waiting. `spelledOut` is for the card, which has room for words.
func waitedText(_ waited: TimeInterval, spelledOut: Bool = false) -> String {
    func count(_ n: Int, _ short: String, _ word: String) -> String {
        spelledOut ? "\(n) \(word)\(n == 1 ? "" : "s")" : "\(n)\(short)"
    }
    let seconds = Int(waited)
    return seconds < 60 ? count(seconds, "s", "second") : count(seconds / 60, " min", "minute")
}

/// The large alert: a card that spells out who's asking, what for, and on which kind of key.
struct TouchCard: View {
    let alert: TouchAlert
    let onDismiss: () -> Void
    var onHoverChange: (Bool) -> Void = { _ in }

    @State private var hovering = false
    @State private var shakes: CGFloat = 0
    @State private var bounce = 0
    @Environment(\.colorScheme) private var scheme

    private let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let waited = ctx.date.timeIntervalSince(alert.since)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    TouchRing(tint: alert.tint, touched: alert.touched, bounce: bounce, scale: 1.6)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(alert.touched ? "TOUCHED" : "TOUCH YOUR YUBIKEY")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(alert.tint.ink(on: scheme))
                        Text(alert.requester?.headline ?? "\(alert.kind.label) request")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(alert.touched ? "Thanks" : "Waiting \(waitedText(waited, spelledOut: true))")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }

                    Spacer(minLength: 0)

                    IconButton(systemImage: "xmark", help: "Dismiss", scale: 1.1, action: onDismiss)
                }

                details
            }
            .padding(18)
            .frame(width: 500)
            .background(GlassBackground(shape: shape, tint: alert.tint))
            .shadow(color: alert.tint.opacity(0.55), radius: 30, y: 8)
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            .scaleEffect(hovering ? 1.015 : 1)
            .modifier(ShakeEffect(shakes: shakes))
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: hovering)
            .animation(.snappy, value: Int(waited))
        }
        .onHover { hovering = $0; onHoverChange($0) }
        .onAppear(perform: wiggle)
        .onChange(of: alert.token) { wiggle() }
    }

    /// The requester's detail, then the kind of key. Unknown requesters get only the key row, so they look sparse.
    private var details: some View {
        let rows = [alert.requester?.detail, (alert.kind.symbol, alert.kind.device)].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(rows, id: \.text) { symbol, text in
                Label {
                    Text(text).lineLimit(1).truncationMode(.middle)
                } icon: {
                    Image(systemName: symbol).foregroundStyle(alert.tint.ink(on: scheme)).frame(width: 18)
                }
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(alert.tint.opacity(0.08)))
    }

    private func wiggle() {
        bounce += 1
        withAnimation(.easeInOut(duration: 0.6).delay(0.25)) { shakes += 1 }
    }
}

/// A comet circling while the key waits, closing into a full ring and a checkmark once it's touched. It doesn't
/// count down, since each client gives up on its own schedule.
private struct TouchRing: View {
    let tint: Color
    let touched: Bool
    let bounce: Int
    let scale: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Waiting's black or white would vanish into the glass under it, so the comet takes the readable shade.
        let comet = tint.ink(on: scheme)
        ZStack {
            Circle().fill(tint.opacity(0.18))
            if touched {
                Circle()
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: 3.5 * scale, lineCap: .round))
                    .padding(2 * scale)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                    let turn = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(
                            AngularGradient(colors: [comet.opacity(0), comet], center: .center, startAngle: .zero, endAngle: .degrees(108)),
                            style: StrokeStyle(lineWidth: 3.5 * scale, lineCap: .round)
                        )
                        .rotationEffect(.degrees(turn * 360))
                        .padding(2 * scale)
                }
                // The pill animates on each whole-second tick; keep that from easing the comet and making it stutter.
                .transaction { $0.animation = nil }
                .transition(.opacity)
            }
            // One view for both symbols, so the hand morphs into the checkmark instead of swapping.
            Image(systemName: touched ? "checkmark" : "hand.tap.fill")
                .font(.system(size: 15 * scale, weight: .bold))
                .foregroundStyle(tint.ink(on: scheme))
                .contentTransition(.symbolEffect(.replace.downUp))
                .symbolEffect(.bounce, value: bounce)
                .symbolEffect(.bounce, value: touched)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.62), value: touched)
        .frame(width: 40 * scale, height: 40 * scale)
    }
}

/// Liquid Glass on macOS 26 and later, tinted with the alert's color; the frosted material before that.
private struct GlassBackground<S: InsettableShape>: View {
    let shape: S
    let tint: Color
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isSnapshot) private var isSnapshot

    /// Stronger in light mode, where a faint tint disappears into the pale glass.
    private var wash: LinearGradient {
        let strength = scheme == .dark ? (0.08, 0.2) : (0.18, 0.42)
        return LinearGradient(colors: [tint.opacity(strength.0), tint.opacity(strength.1)], startPoint: .leading, endPoint: .trailing)
    }

    var body: some View {
        if isSnapshot {
            ZStack {
                shape.fill(scheme == .dark ? Color(white: 0.16, opacity: 0.85) : Color.white.opacity(0.85))
                shape.fill(wash)
                shape.strokeBorder(tint.opacity(0.6), lineWidth: 1.2)
            }
        } else if #available(macOS 26, *) {
            ZStack {
                shape.fill(wash)
                shape.strokeBorder(tint.opacity(0.6), lineWidth: 1.2)
            }
            .glassEffect(.regular.tint(tint.opacity(0.32)), in: shape)
        } else {
            ZStack {
                shape.fill(.regularMaterial)
                shape.fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)], startPoint: .leading, endPoint: .trailing))
                shape.fill(wash)
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.35), tint.opacity(0.9)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.5
                )
            }
        }
    }
}

private struct IconButton: View {
    let systemImage: String
    let help: String
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11 * scale, weight: .bold))
                .frame(width: 28 * scale, height: 28 * scale)
                .background(Circle().fill(.primary.opacity(0.08)))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(SquishStyle())
        .help(help)
    }
}

struct SquishStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

/// Horizontal "no-no" wiggle; each +1 to `shakes` plays one wiggle.
struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let x = sin(shakes * .pi * 6) * 7 * (1 - (shakes - shakes.rounded(.down)))
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

struct GlowView: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Rectangle().strokeBorder(color, lineWidth: 26).blur(radius: 30)
            Rectangle().strokeBorder(color.opacity(0.9), lineWidth: 6).blur(radius: 8)
        }
        .opacity(pulse ? 0.95 : 0.35)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

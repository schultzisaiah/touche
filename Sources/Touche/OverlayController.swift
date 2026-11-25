import AppKit
import SwiftUI

struct TouchAlert: Identifiable, Equatable {
    let kind: TouchKind
    var requester: Requester?
    var since = Date()
    var touched = false
    /// New for every request, so a repeat request wiggles the pill again and a late lookup or removal for an
    /// earlier request leaves it alone.
    let token = UUID()
    var id: TouchKind { kind }
    var tint: Color { touched ? Color(hex: Brand.mint) : Color(nsColor: Brand.waiting) }
}

/// What letting go of a swipe does. Pure, so the feel tuned by hand stays pinned by tests.
enum SwipeOutcome: Equatable {
    case dismiss, springBack

    /// Past this, letting go commits the swipe.
    static let threshold: CGFloat = 180

    /// Where the hint behind a swiped alert sits, as its left edge within the alert's resting frame: centered in the
    /// gap the alert leaves behind, so it starts at the edge and ends up in the middle once the alert has gone.
    static func hintX(offset: CGFloat, width: CGFloat, hintWidth: CGFloat) -> CGFloat {
        max(6, min(offset, width) / 2 - hintWidth / 2)
    }

    /// `offset` is how far the alert has travelled right; `flick` is its velocity at release. Commits past the
    /// threshold or on a quick outward flick, unless the gesture was heading back (pulling back means "never mind").
    static func decide(offset: CGFloat, flick: CGFloat) -> SwipeOutcome {
        let retreating = flick < -8
        let flicked = offset > 40 && flick > 60
        guard offset > 0, !retreating, offset >= threshold || flicked else { return .springBack }
        return .dismiss
    }
}

/// Owns the floating pill panels and the screen-edge glow windows.
@MainActor
final class OverlayController: ObservableObject {
    @Published private(set) var alerts: [TouchAlert] = []
    /// Horizontal swipe distance per alert. Right dismisses; left only rubber-bands.
    @Published private(set) var swipeOffsets: [TouchKind: CGFloat] = [:]

    var onDismiss: (TouchKind) -> Void = { _ in }

    static let spring = Animation.spring(response: 0.55, dampingFraction: 0.68)
    /// Room for both kinds of request stacked as large cards (500pt wide), plus the soft edge fade in OverlayRoot.
    static let panelSize = NSSize(width: 720, height: 460)
    /// How long the checkmark shows before a touched pill leaves.
    static let touchedLinger: Duration = .milliseconds(1100)

    private var hoveredID: TouchKind?
    /// The alert a trackpad swipe started on; it keeps the swipe even as the pill slides out from under the pointer.
    private var swipingID: TouchKind?
    private var swipeMonitor: Any?
    private var positionObserver: NSKeyValueObservation?
    private var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var glowWindows: [NSWindow] = []
    private var glowColor: NSColor?

    init() {
        // Two-finger trackpad swipes arrive as scroll events on whichever window is under the pointer.
        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handleScroll(event) ?? event }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        // Moving alerts to the other position takes effect on the ones already showing.
        positionObserver = UserDefaults.standard.observe(\.position, options: .new) { [weak self] _, _ in
            Task { @MainActor in self?.screensChanged() }
        }
    }

    // MARK: Alerts

    func isWaiting(_ kind: TouchKind) -> Bool {
        alerts.contains { $0.kind == kind && !$0.touched }
    }

    /// Shows a pill for a new request, replacing any for the same kind. Returns its token for `setRequester`.
    @discardableResult
    func show(_ kind: TouchKind) -> UUID {
        presentPanels()
        let alert = TouchAlert(kind: kind)
        swipeOffsets[kind] = nil
        withAnimation(Self.spring) {
            if let i = alerts.firstIndex(where: { $0.kind == kind }) {
                alerts[i] = alert
            } else {
                alerts.insert(alert, at: 0)
            }
        }
        updateGlow()
        return alert.token
    }

    func setRequester(_ requester: Requester?, for kind: TouchKind, token: UUID) {
        guard let i = alerts.firstIndex(where: { $0.token == token }) else { return }
        withAnimation(.snappy) { alerts[i].requester = requester }
    }

    /// Ends a request: a touched one turns into a checkmark for a moment first.
    func finish(_ kind: TouchKind, touched: Bool) {
        guard let i = alerts.firstIndex(where: { $0.kind == kind && !$0.touched }) else { return }
        guard touched else { remove(kind); return }
        let token = alerts[i].token
        withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) { alerts[i].touched = true }
        updateGlow()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.touchedLinger)
            guard let self, self.alerts.contains(where: { $0.token == token }) else { return }
            self.remove(kind)
        }
    }

    func dismiss(_ kind: TouchKind) {
        remove(kind)
        onDismiss(kind)
    }

    private func remove(_ kind: TouchKind) {
        withAnimation(Self.spring) { alerts.removeAll { $0.kind == kind } }
        updateGlow()
        // Clearing the offset mid-removal would yank a swiped-away pill back on screen, so wait out the transition.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self else { return }
            if !self.alerts.contains(where: { $0.kind == kind }) { self.swipeOffsets[kind] = nil }
            if self.alerts.isEmpty { self.panels.values.forEach { $0.orderOut(nil) } }
        }
    }

    func setHovering(_ kind: TouchKind, _ hovering: Bool) {
        if hovering { hoveredID = kind } else if hoveredID == kind { hoveredID = nil }
    }

    // MARK: Swipe to dismiss

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        guard event.hasPreciseScrollingDeltas,
              let window = event.window, panels.values.contains(where: { $0 === window }),
              let kind = swipingID ?? hoveredID,
              alerts.contains(where: { $0.kind == kind })
        else { return event }

        // Inertia after the fingers lift: the swipe was already decided at .ended.
        if !event.momentumPhase.isEmpty { return nil }

        // Finger direction regardless of the natural-scrolling setting.
        let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        switch event.phase {
        case .began, .changed:
            // Only claim mostly-horizontal gestures, so a vertical scroll doesn't nudge the pill.
            if swipingID == nil {
                guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
                swipingID = kind
            }
            dragSwipe(kind, (swipeOffsets[kind] ?? 0) + dx)
        case .ended:
            endSwipe(kind, flick: dx * 4)
        case .cancelled:
            endSwipe(kind, flick: 0)
        default:
            return event
        }
        return nil
    }

    /// Moves the alert with the gesture. Crossing the commit point outward plays a firm trackpad click;
    /// crossing back plays a lighter one, so you can feel which side you're on.
    func dragSwipe(_ kind: TouchKind, _ offset: CGFloat) {
        let before = swipeOffsets[kind] ?? 0
        // Left has nothing to do, so it only stretches a little.
        swipeOffsets[kind] = offset < 0 ? max(offset * 0.3, -36) : offset
        let wasPast = before >= Self.swipeThreshold, isPast = offset >= Self.swipeThreshold
        if wasPast != isPast {
            NSHapticFeedbackManager.defaultPerformer.perform(isPast ? .levelChange : .alignment, performanceTime: .now)
        }
    }

    static let swipeThreshold = SwipeOutcome.threshold

    /// Throws the alert off and dismisses it, or springs it back (see SwipeOutcome.decide).
    func endSwipe(_ kind: TouchKind, flick: CGFloat) {
        swipingID = nil
        guard SwipeOutcome.decide(offset: swipeOffsets[kind] ?? 0, flick: flick) == .dismiss,
              let token = alerts.first(where: { $0.kind == kind })?.token
        else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.6)) { swipeOffsets[kind] = 0 }
            return
        }
        // A full panel width, so the pill's trailing edge clears the panel before it's removed.
        withAnimation(.easeIn(duration: 0.26)) { swipeOffsets[kind] = Self.panelSize.width }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            guard let self, self.alerts.contains(where: { $0.token == token }) else { return }
            self.dismiss(kind)
        }
    }

    // MARK: Windows

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    /// Displays come and go: panels follow the screens that remain, and the glow is redrawn to cover them.
    private func screensChanged() {
        if !alerts.isEmpty { presentPanels() }
        if let glowColor { showGlow(color: glowColor) }
    }

    /// Every display, or just the pointer's.
    private static func targetScreens() -> [NSScreen] {
        guard UserDefaults.standard.bool(forKey: Prefs.allDisplays) else {
            let mouse = NSEvent.mouseLocation
            return [NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]]
        }
        return NSScreen.screens
    }

    private func presentPanels() {
        let screens = Self.targetScreens()
        for (display, panel) in panels where !screens.contains(where: { Self.displayID($0) == display }) {
            panel.orderOut(nil)
            panels[display] = nil
        }
        for screen in screens {
            let display = Self.displayID(screen)
            let panel = panels[display] ?? makePanel()
            panels[display] = panel
            panel.setFrame(Self.frame(on: screen), display: true)
            panel.orderFrontRegardless()
        }
    }

    private static func frame(on screen: NSScreen) -> NSRect {
        let size = panelSize
        let y: CGFloat
        switch PillPosition(rawValue: UserDefaults.standard.string(forKey: Prefs.position) ?? "") ?? .top {
        case .top:
            // Hang just below the menu bar (and the notch, on screens that have one).
            let topInset = max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
            y = screen.frame.maxY - topInset - size.height
        case .center:
            y = screen.frame.midY - size.height / 2
        }
        return NSRect(x: screen.frame.midX - size.width / 2, y: y, width: size.width, height: size.height)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        // Left out of screen shares and recordings, so a call doesn't see which repo or host you're touching for.
        panel.sharingType = .none
        let host = NSHostingView(rootView: OverlayRoot(controller: self))
        host.layer?.backgroundColor = .clear
        panel.contentView = host
        return panel
    }

    /// Glows while any request is waiting, if the glow is on.
    private func updateGlow() {
        guard UserDefaults.standard.bool(forKey: Prefs.glow), alerts.contains(where: { !$0.touched }) else {
            hideGlow()
            return
        }
        // White in both modes: the pills' dark-mode black wouldn't glow.
        if glowColor == nil { showGlow(color: .white) }
    }

    private func showGlow(color: NSColor) {
        hideGlow(animated: false)
        glowColor = color
        for screen in Self.targetScreens() {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.sharingType = .none
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.contentView = NSHostingView(rootView: GlowView(color: Color(nsColor: color)))
            window.setFrame(screen.frame, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()
            glowWindows.append(window)
        }
        panels.values.forEach { if $0.isVisible { $0.orderFrontRegardless() } } // keep pills above the glow
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.6
            glowWindows.forEach { $0.animator().alphaValue = 1 }
        }
    }

    private func hideGlow(animated: Bool = true) {
        let windows = glowWindows
        glowWindows.removeAll()
        glowColor = nil
        guard animated else { windows.forEach { $0.orderOut(nil) }; return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            windows.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            windows.forEach { $0.orderOut(nil) }
        }
    }
}

extension UserDefaults {
    /// Key-value observable, so the panels can follow a change of position. Named for `Prefs.position`.
    @objc dynamic var position: String? { string(forKey: Prefs.position) }
}

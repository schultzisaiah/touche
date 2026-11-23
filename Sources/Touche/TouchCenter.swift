import AppKit

struct TouchRecord {
    let kind: TouchKind
    let at: Date
    var requester: Requester?
    var touched = false
}

/// Turns detector events into alerts: one pill per kind of request, a ding per request, and an end to requests the
/// key never reports finishing.
@MainActor
final class TouchCenter {
    private let overlay: OverlayController
    let watcher = TouchWatcher()
    private(set) var recent: [TouchRecord] = []

    private var lastRequest: [TouchKind: Date] = [:]
    private var lastHeard: [TouchKind: Date] = [:]
    /// Dismissed while gpg is still waiting. gpg repeats its request every few seconds, and the pill shouldn't
    /// keep coming back.
    private var silenced: Set<TouchKind> = []
    private var expiry: Timer?

    init(overlay: OverlayController) {
        self.overlay = overlay
        watcher.onEvent = { [weak self] in self?.handle($0) }
        overlay.onDismiss = { [weak self] kind in
            if kind == .openPGP, self?.lastHeard[kind] != nil { self?.silenced.insert(kind) }
        }
        expiry = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.expireQuiet() }
        }
    }

    func handle(_ event: TouchEvent) {
        switch event {
        case .waiting(let kind):
            waiting(kind)
        case .done(let kind):
            lastHeard[kind] = nil
            silenced.remove(kind)
            if let i = recent.firstIndex(where: { $0.kind == kind }) { recent[i].touched = true }
            overlay.finish(kind, touched: true)
        case .cancelled(let kind):
            lastHeard[kind] = nil
            silenced.remove(kind)
            overlay.finish(kind, touched: false)
        }
    }

    /// Plays a request through end to end with a sample requester, so you can see and hear it without the key.
    func preview(_ kind: TouchKind) {
        waiting(kind, requester: kind == .fido2 ? .signing(repo: "onyb/ykding", subject: "Ding when your YubiKey wants a touch") : nil)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.handle(.done(kind))
        }
    }

    private func waiting(_ kind: TouchKind, requester: Requester? = nil) {
        let now = Date()
        lastHeard[kind] = now
        if silenced.contains(kind) { return }
        // gpg repeats itself for as long as it waits, and one FIDO2 request can start its queue more than once.
        if overlay.isWaiting(kind), kind == .openPGP || now.timeIntervalSince(lastRequest[kind] ?? .distantPast) < kind.debounce { return }
        lastRequest[kind] = now

        // Sound first: the requester lookup takes a moment.
        if let sound = UserDefaults.standard.string(forKey: Prefs.sound) { NSSound(named: sound)?.play() }
        let token = overlay.show(kind)
        recent.insert(TouchRecord(kind: kind, at: now), at: 0)
        recent = Array(recent.prefix(5))

        if let requester {
            resolve(requester, kind: kind, token: token)
        } else {
            Task.detached(priority: .userInitiated) {
                let found = Requester.lookUp()
                await MainActor.run { [weak self] in self?.resolve(found, kind: kind, token: token) }
            }
        }
    }

    private func resolve(_ requester: Requester?, kind: TouchKind, token: UUID) {
        overlay.setRequester(requester, for: kind, token: token)
        if let i = recent.firstIndex(where: { $0.kind == kind }) { recent[i].requester = requester }
    }

    private func expireQuiet() {
        let now = Date()
        for (kind, heard) in lastHeard where now.timeIntervalSince(heard) > kind.timeout {
            lastHeard[kind] = nil
            silenced.remove(kind)
            overlay.finish(kind, touched: false)
        }
    }
}

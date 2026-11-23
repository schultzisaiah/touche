import Foundation

/// Tails `log stream` for touch requests, restarting it if it exits.
@MainActor
final class TouchWatcher {
    var onEvent: (TouchEvent) -> Void = { _ in }
    var onRunningChange: (Bool) -> Void = { _ in }
    private(set) var running = false {
        didSet { if running != oldValue { onRunningChange(running) } }
    }
    private var process: Process?
    private var stopping = false

    func start() {
        stopping = false
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--level", "debug", "--style", "ndjson", "--predicate", TouchDetector.predicate]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let reader = LineReader { [weak self] event in
            Task { @MainActor [weak self] in self?.onEvent(event) }
        }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { reader.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.running = false
                guard !self.stopping else { return }
                try? await Task.sleep(for: .seconds(3))
                if !self.stopping { self.start() }
            }
        }
        do {
            try process.run()
            self.process = process
            running = true
        } catch {
            running = false
        }
    }

    func stop() {
        stopping = true
        process?.terminate()
        process = nil
    }
}

/// Splits the stream into lines for the detector. Only touched from the pipe's readability handler, which
/// FileHandle calls serially.
private final class LineReader: @unchecked Sendable {
    private var buffer = Data()
    private var detector = TouchDetector()
    private let emit: @Sendable (TouchEvent) -> Void

    init(emit: @escaping @Sendable (TouchEvent) -> Void) {
        self.emit = emit
    }

    func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let event = detector.feed(line) { emit(event) }
        }
    }
}

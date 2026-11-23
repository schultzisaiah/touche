import Foundation

enum TouchKind: String, CaseIterable, Identifiable {
    case fido2, openPGP
    var id: Self { self }

    var label: String { self == .fido2 ? "FIDO2" : "OpenPGP" }
    var symbol: String { self == .fido2 ? "key.fill" : "lock.fill" }
    var device: String { self == .fido2 ? "FIDO2 security key" : "OpenPGP card (gpg)" }

    /// Requests closer together than this are one request. gpg logs again about every 0.3s while it waits.
    var debounce: TimeInterval { self == .fido2 ? 1 : 8 }

    /// Silence for this long ends a request, in case the message saying it ended was missed. gpg repeats its request
    /// about every 0.3s while it waits, so its silence means something sooner.
    var timeout: TimeInterval { self == .fido2 ? 35 : 5 }
}

enum TouchEvent: Equatable {
    case waiting(TouchKind)
    /// The key was touched.
    case done(TouchKind)
    /// The key stopped waiting without a touch.
    case cancelled(TouchKind)
}

/// Turns `log stream --style ndjson` lines into touch events, using noperator/yknotify's heuristic. These are log
/// messages, not an API, so a macOS update can change them.
struct TouchDetector {
    static let predicate = #"(processImagePath == "/kernel" AND senderImagePath ENDSWITH "IOHIDFamily") OR (subsystem CONTAINS "CryptoTokenKit")"#

    /// HID clients seen opening a USB HID device. Only their queues count, so keyboards and trackpads starting
    /// queues of their own don't read as touches.
    private var clients: Set<Substring> = []
    /// While gpg waits, the card's next reply is the wait ending: OK once touched, an error if it gave up.
    private var gpgWaiting = false

    mutating func feed(_ line: String) -> TouchEvent? {
        guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let message = entry["eventMessage"] as? String
        else { return nil }
        let process = entry["processImagePath"] as? String ?? ""
        let sender = entry["senderImagePath"] as? String ?? ""

        if process == "/kernel" {
            // "AppleUserUSBHostHIDDevice:0x… open by IOHIDLibUserClient:0x…", then "IOHIDLibUserClient:0x… startQueue".
            if message.contains("AppleUserUSBHostHIDDevice:"), let by = message.range(of: " open by IOHIDLibUserClient:") {
                clients.insert(message[message.index(by.lowerBound, offsetBy: 9)...].prefix { $0 != " " })
                return nil
            }
            let client = message.prefix { $0 != " " }
            if message.hasSuffix(" startQueue") {
                return clients.contains(client) ? .waiting(.fido2) : nil
            }
            if message.hasSuffix(" stopQueue") {
                return clients.remove(client) != nil ? .done(.fido2) : nil
            }
        } else if message == "Time extension received", (process + sender).contains("usbsmartcardreaderd") {
            gpgWaiting = true
            return .waiting(.openPGP)
        } else if gpgWaiting, message.contains("transmitRequest RSP <<<") {
            gpgWaiting = false
            return message.contains("SW=9000") ? .done(.openPGP) : .cancelled(.openPGP)
        }
        return nil
    }
}

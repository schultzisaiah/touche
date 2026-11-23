import Foundation
import Testing
@testable import Touche

/// One `log stream --style ndjson` line, as the detector sees it.
private func line(_ message: String, process: String = "/kernel", sender: String = "/System/Library/Extensions/IOHIDFamily.kext/Contents/MacOS/IOHIDFamily") -> String {
    let entry = ["eventMessage": message, "processImagePath": process, "senderImagePath": sender]
    return String(decoding: try! JSONSerialization.data(withJSONObject: entry), as: UTF8.self)
}

private let open = line("AppleUserUSBHostHIDDevice:0x100000abc open by IOHIDLibUserClient:0x100000def (0x1 0x0)")

@Suite("Touch detection")
struct TouchDetectorTests {
    @Test func aTrackedClientStartingItsQueueIsAFIDO2Touch() {
        var detector = TouchDetector()
        #expect(detector.feed(open) == nil)
        #expect(detector.feed(line("IOHIDLibUserClient:0x100000def startQueue")) == .waiting(.fido2))
    }

    @Test func stoppingTheQueueEndsTheRequest() {
        var detector = TouchDetector()
        _ = detector.feed(open)
        _ = detector.feed(line("IOHIDLibUserClient:0x100000def startQueue"))
        #expect(detector.feed(line("IOHIDLibUserClient:0x100000def stopQueue")) == .done(.fido2))
    }

    @Test func otherHIDClientsAreIgnored() {
        var detector = TouchDetector()
        _ = detector.feed(open)
        #expect(detector.feed(line("IOHIDLibUserClient:0x100000aaa startQueue")) == nil)
        #expect(detector.feed(line("IOHIDLibUserClient:0x100000aaa stopQueue")) == nil)
    }

    @Test func aClientIsForgottenOnceItStops() {
        var detector = TouchDetector()
        _ = detector.feed(open)
        _ = detector.feed(line("IOHIDLibUserClient:0x100000def stopQueue"))
        #expect(detector.feed(line("IOHIDLibUserClient:0x100000def startQueue")) == nil)
    }

    @Test func gpgTimeExtensionsAreOpenPGPTouches() {
        var detector = TouchDetector()
        #expect(detector.feed(gpgWaiting) == .waiting(.openPGP))
    }

    @Test func theCardsOKReplyIsTheTouch() {
        var detector = TouchDetector()
        _ = detector.feed(gpgWaiting)
        #expect(detector.feed(reply("SW=9000 (OK)")) == .done(.openPGP))
    }

    @Test func anErrorReplyEndsTheWaitWithoutATouch() {
        var detector = TouchDetector()
        _ = detector.feed(gpgWaiting)
        #expect(detector.feed(reply("SW=6982 (Security status not satisfied)")) == .cancelled(.openPGP))
    }

    @Test func repliesOutsideAWaitAreIgnored() {
        var detector = TouchDetector()
        #expect(detector.feed(reply("SW=9000 (OK)")) == nil)
        _ = detector.feed(gpgWaiting)
        _ = detector.feed(reply("SW=9000 (OK)"))
        #expect(detector.feed(reply("SW=9000 (OK)")) == nil)
    }

    private let gpgWaiting = line("Time extension received", process: "/System/Library/CryptoTokenKit/usbsmartcardreaderd.slotdextension/Contents/MacOS/usbsmartcardreaderd", sender: "")

    private func reply(_ status: String) -> String {
        line("Yubico YubiKey OTP+FIDO+CCID: transmitRequest RSP <<< T=1 [async] [256 bytes] \(status) <private>", process: "/System/Library/Frameworks/CryptoTokenKit.framework/ctkpcscd", sender: "")
    }

    @Test func nonJSONLinesAreSkipped() {
        var detector = TouchDetector()
        #expect(detector.feed("Filtering the log data using \"composedMessage CONTAINS …\"") == nil)
    }
}

@Suite("Who asked for the touch")
struct RequesterTests {
    @Test func gitRemotesShortenToOrgAndRepo() {
        #expect(Requester.shortRepo("git@github.com:onyb/ykding.git\n") == "onyb/ykding")
        #expect(Requester.shortRepo("https://github.com/onyb/ykding") == "onyb/ykding")
        #expect(Requester.shortRepo("ssh://git@gitlab.example.com/team/project.git") == "team/project")
    }

    @Test func sshDestinationAndRemoteCommand() {
        let target = Requester.sshTarget(["/usr/bin/ssh", "-o", "SendEnv=GIT_PROTOCOL", "git@github.com", "git-upload-pack", "'onyb/ykding.git'"])
        #expect(target?.destination == "git@github.com")
        #expect(target?.command == "git-upload-pack onyb/ykding.git")
    }

    @Test func sshFlagsWithoutValuesAreSkipped() {
        let target = Requester.sshTarget(["ssh", "-T", "-p", "2222", "ssh://host.example"])
        #expect(target?.destination == "host.example")
        #expect(target?.command == nil)
    }

    @Test func notSSH() {
        #expect(Requester.sshTarget(["/usr/bin/scp", "file", "host:"]) == nil)
        #expect(Requester.sshTarget(["ssh", "-v"]) == nil)
    }

    @Test func emptyProbesStillSayWhatKindOfRequest() {
        #expect(Requester.signing(repo: nil, subject: nil).text == "Signing a commit")
        #expect(Requester.signing(repo: "onyb/ykding", subject: nil).text == "onyb/ykding")
        #expect(Requester.ssh(destination: "git@github.com", command: nil).text == "git@github.com")
    }
}

@Suite("Swipe to dismiss")
struct SwipeOutcomeTests {
    let t = SwipeOutcome.threshold

    @Test func pastTheThresholdDismisses() {
        #expect(SwipeOutcome.decide(offset: t, flick: 0) == .dismiss)
    }

    @Test func leftNeverDismisses() {
        #expect(SwipeOutcome.decide(offset: -t, flick: -80) == .springBack)
    }

    @Test func pullingBackCancels() {
        #expect(SwipeOutcome.decide(offset: t + 40, flick: -20) == .springBack)
    }

    @Test func aQuickFlickDismissesEarly() {
        #expect(SwipeOutcome.decide(offset: 60, flick: 80) == .dismiss)
        #expect(SwipeOutcome.decide(offset: 30, flick: 80) == .springBack)
    }

    @Test func hintStaysCenteredInTheGap() {
        #expect(SwipeOutcome.hintX(offset: 20, width: 440, hintWidth: 100) == 6)
        #expect(SwipeOutcome.hintX(offset: 300, width: 440, hintWidth: 100) == 100)
        #expect(SwipeOutcome.hintX(offset: 720, width: 440, hintWidth: 100) == 170)
    }
}

import Foundation

/// Who asked for the touch, so a request you didn't start stands out instead of training you to tap whenever the
/// key blinks. Best effort, ported from ykding: any probe can come up empty.
enum Requester: Equatable {
    /// Git signing a commit through `ssh-keygen -Y sign` or `gpg -bsau`.
    case signing(repo: String?, subject: String?)
    /// An ssh client authenticating with a security key.
    case ssh(destination: String?, command: String?)

    var symbol: String {
        switch self {
        case .signing: "signature"
        case .ssh: "network"
        }
    }

    var text: String {
        switch self {
        case let .signing(repo, subject):
            [repo, subject].compactMap { $0 }.joined(separator: ": ").nonEmpty ?? "Signing a commit"
        case let .ssh(destination, command):
            [destination, command].compactMap { $0 }.joined(separator: ": ").nonEmpty ?? "SSH connection"
        }
    }

    /// The large card's title: what's being signed, or where ssh is connecting.
    var headline: String {
        switch self {
        case let .signing(_, subject): subject ?? "Signing a commit"
        case let .ssh(destination, _): destination ?? "SSH connection"
        }
    }

    /// The large card's detail row under the headline, when there's more to say.
    var detail: (symbol: String, text: String)? {
        switch self {
        case let .signing(repo, _): repo.map { ("folder.fill", $0) }
        case let .ssh(_, command): command.map { ("terminal.fill", $0) }
        }
    }

    /// Blocks for about 0.2s while it inspects processes, so call it off the main thread.
    static func lookUp() -> Requester? {
        signing() ?? ssh()
    }

    // Probes match processes by executable name (`pgrep -x`), never by argv pattern (`-f`): a pgrep's own argv
    // would contain the pattern, and the match would be gone by the time it's inspected.

    /// While git's signer waits for the touch, its working directory is the repo git ran in, and the message being
    /// signed is already in the git dir.
    private static func signing() -> Requester? {
        let signers = [("ssh-keygen", " -Y sign"), ("gpg", " -bsau")]
        guard let pid = signers.lazy.compactMap({ name, flag in
            lines(Shell.run("/usr/bin/pgrep", "-x", name))
                .first { Shell.run("/bin/ps", "-o", "command=", "-p", $0)?.contains(flag) == true }
        }).first
        else { return nil }
        guard let dir = lines(Shell.run("/usr/sbin/lsof", "-a", "-p", pid, "-d", "cwd", "-Fn"))
            .first(where: { $0.hasPrefix("n") })?.dropFirst()
        else { return .signing(repo: nil, subject: nil) }

        let info = lines(Shell.run("/usr/bin/git", "-C", String(dir), "rev-parse", "--absolute-git-dir", "--show-toplevel"))
        guard info.count == 2 else { return .signing(repo: nil, subject: nil) }
        let repo = Shell.run("/usr/bin/git", "-C", String(dir), "remote", "get-url", "origin").flatMap(shortRepo)
            ?? URL(fileURLWithPath: info[1]).lastPathComponent
        // A rebase, then a merge or cherry-pick, then a plain commit.
        let subject = ["rebase-merge/message", "MERGE_MSG", "COMMIT_EDITMSG"].lazy
            .compactMap { try? String(contentsOfFile: "\(info[0])/\($0)", encoding: .utf8) }
            .first { !$0.isEmpty }
            .flatMap { lines($0).first }
        return .signing(repo: repo, subject: subject)
    }

    /// While a security key waits for the touch, `ssh-sk-helper` is alive, and its parent is the ssh client whose
    /// command line names the destination and any remote command.
    private static func ssh() -> Requester? {
        guard let helper = lines(Shell.run("/usr/bin/pgrep", "-nx", "ssh-sk-helper")).first else { return nil }
        guard let parent = Shell.run("/bin/ps", "-o", "ppid=", "-p", helper)?.trimmingCharacters(in: .whitespaces),
              let command = Shell.run("/bin/ps", "-o", "command=", "-p", parent),
              let target = sshTarget(command.split(separator: " ").map(String.init))
        else { return .ssh(destination: nil, command: nil) }
        return .ssh(destination: target.destination, command: target.command)
    }

    /// The destination and remote command from an ssh argv, skipping flags and the values of flags that take one
    /// (ssh.c's getopt string). `ps` prints args unquoted, so a flag value with spaces mis-parses. Fine for a hint.
    static func sshTarget(_ argv: [String]) -> (destination: String, command: String?)? {
        guard let program = argv.first, URL(fileURLWithPath: program).lastPathComponent == "ssh" else { return nil }
        var i = 1
        while i < argv.count {
            let arg = argv[i]
            if arg == "--" { i += 1; break }
            guard arg.hasPrefix("-") else { break }
            i += arg.count == 2 && "BbcDEeFIiJLlmOoPpRSWw".contains(arg.last!) ? 2 : 1
        }
        guard i < argv.count else { return nil }
        let destination = argv[i].hasPrefix("ssh://") ? String(argv[i].dropFirst(6)) : argv[i]
        let command = argv[(i + 1)...].joined(separator: " ").filter { $0 != "'" && $0 != "\"" }
        return (destination, command.nonEmpty)
    }

    /// `org/repo` from a remote URL, since the pill only fits about 40 characters.
    static func shortRepo(_ remote: String) -> String? {
        var url = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix(".git") { url.removeLast(4) }
        let parts = url.replacingOccurrences(of: ":", with: "/").split(separator: "/")
        guard parts.count >= 2 else { return url.nonEmpty }
        return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
    }

    private static func lines(_ output: String?) -> [String] {
        output?.split(whereSeparator: \.isNewline).map(String.init) ?? []
    }
}

enum Shell {
    /// Standard output, or nil if the command failed.
    static func run(_ path: String, _ args: String...) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

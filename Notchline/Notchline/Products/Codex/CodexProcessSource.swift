import Darwin
import Foundation

/// Native provenance stays at the Codex boundary. A PID alone is never an execution identity.
nonisolated struct CodexExecution: Hashable, Sendable {
    enum Surface: Hashable, Sendable { case desktop, cli }
    let pid: Int32
    let startedAt: Date
    let surface: Surface
    let terminal: String?
}

nonisolated struct CodexProcessSource: Sendable {
    var resolvePeer: @Sendable (Int32) -> CodexExecution?
    var isAlive: @Sendable (CodexExecution) -> Bool
    var localProcesses: @Sendable () -> [CodexExecution]?

    static func live() -> Self {
        native(CodexNativeProcesses())
    }

    static func native(_ reader: CodexNativeProcesses) -> Self {
        return Self(resolvePeer: { descriptor in
            var pid: pid_t = 0
            var length = socklen_t(MemoryLayout<pid_t>.size)
            // nc is still blocked waiting for our reply, so the peer is alive to be named.
            guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0,
                  length == MemoryLayout<pid_t>.size else { return nil }
            return reader.owner(of: pid)
        }, isAlive: { execution in
            ControllingTerminalGestureReader.systemProcessStartedAt(forProcessIdentifier: execution.pid)
                == execution.startedAt
        }, localProcesses: {
            LibprocProcessTable().processes(named: CodexNativeProcesses.executableName)?.compactMap {
                reader.localTUI($0.processIdentifier)
            }
        })
    }
}

/// Observed on 0.154.0; unsupported modes and unreadable process arguments fail closed.
nonisolated struct CodexNativeProcesses: Sendable {
    /// What the kernel calls both surfaces' executable, and what ``CodexProcessSource/live()``
    /// asks the process table for.
    static let executableName = "codex"

    private let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func owner(of peer: Int32) -> CodexExecution? {
        var pid = peer
        for _ in 0..<32 {
            guard pid > 1,
                  let path = ProcessAncestryHostResolver.systemExecutablePath(ofProcess: pid)
            else { return nil }
            if URL(fileURLWithPath: path).lastPathComponent == Self.executableName {
                if let local = localTUI(pid) { return local }
                // Only an app-server belonging to the actual Desktop application can vouch for it.
                guard let arguments = Self.arguments(pid), Self.isAppServer(arguments),
                      usesDefaultHome(pid) else { return nil }
                var ancestor = pid
                for _ in 0..<32 {
                    guard let parent = ProcessAncestryHostResolver.systemParent(ofProcess: ancestor), parent > 1,
                          let executable = ProcessAncestryHostResolver.systemExecutablePath(ofProcess: parent)
                    else { return nil }
                    if let bundle = ProcessAncestryHostResolver.enclosingApplicationBundlePath(ofExecutable: executable),
                       ProcessAncestryHostResolver.systemBundle(atPath: bundle)?.identifier == "com.openai.codex",
                       let start = ControllingTerminalGestureReader.systemProcessStartedAt(forProcessIdentifier: parent) {
                        return CodexExecution(pid: parent, startedAt: start, surface: .desktop, terminal: nil)
                    }
                    ancestor = parent
                }
                return nil
            }
            guard let parent = ProcessAncestryHostResolver.systemParent(ofProcess: pid) else { return nil }
            pid = parent
        }
        return nil
    }

    /// A local interactive TUI, identified by what the process **is** rather than by where it was
    /// installed from.
    ///
    /// An install location is not an identity. This used to require the running executable to
    /// resolve to the single path ``ProductInstallationDiscovery/command(named:)`` found first, and
    /// that silently costs rows in ordinary setups: a machine can hold two `codex` binaries — a
    /// Homebrew one and a version manager's — and the one the user runs is not necessarily the one
    /// a fixed search order picks, while a mise- or asdf-style shim is a different file from the
    /// binary it executes and an nvm-style layout keeps the binary under a version directory that
    /// changes on every upgrade. In each of those the process is plainly Codex and matched nothing,
    /// so its Turns got no rows at all.
    ///
    /// What is left identifies it without reference to any list, and is no weaker: the kernel's own
    /// name for the running executable, TUI-shaped argv (`exec`, `app-server` and every other
    /// subcommand are rejected), a controlling terminal, no multiplexer or SSH ancestor, and
    /// `proc_pidfdinfo` reporting this user's own `~/.codex/state_5.sqlite` open and no other
    /// home's. A process holding that database open is Codex; nothing else has reason to.
    func localTUI(_ pid: Int32) -> CodexExecution? {
        guard let path = ProcessAncestryHostResolver.systemExecutablePath(ofProcess: pid),
              URL(fileURLWithPath: path).lastPathComponent == Self.executableName,
              let arguments = Self.arguments(pid),
              Self.isLocalTUI(arguments),
              let tty = ControllingTerminalGestureReader.systemControllingTerminalPath(forProcessIdentifier: pid),
              let start = ControllingTerminalGestureReader.systemProcessStartedAt(forProcessIdentifier: pid),
              usesDefaultHome(pid)
        else { return nil }
        var ancestor = pid
        for _ in 0..<32 {
            guard let parent = ProcessAncestryHostResolver.systemParent(ofProcess: ancestor), parent > 1 else { break }
            guard let executable = ProcessAncestryHostResolver.systemExecutablePath(ofProcess: parent) else { return nil }
            if ["tmux", "screen", "ssh", "sshd"].contains(URL(fileURLWithPath: executable).lastPathComponent) { return nil }
            ancestor = parent
        }
        return CodexExecution(pid: pid, startedAt: start, surface: .cli, terminal: tty)
    }

    func usesDefaultHome(_ pid: Int32) -> Bool {
        Self.hasHomeDatabase(in: LibprocProcessTable().openFilePaths(ofProcess: pid), home: home)
    }

    /// Presence evidence only: no SQLite contents or historical Turns are read.
    /// KERN_PROCARGS2 omits envp on macOS 26.6, so environment is not a home identity source.
    static func hasHomeDatabase(in paths: [String], home: URL) -> Bool {
        let expected = home.appendingPathComponent(".codex/state_5.sqlite").resolvingSymlinksInPath().path
        let databases = Set(paths.filter { URL(fileURLWithPath: $0).lastPathComponent == "state_5.sqlite" }
            .map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
        return databases == [expected]
    }

    /// The subcommands that open the interactive TUI. **This is the only list that has to stay
    /// current**: a bare word that is not one of these is refused, whether it is a subcommand this
    /// app has classified or one a newer CLI has just added. Measured from `codex --help` on
    /// 0.154.0, where both take `[SESSION_ID] [PROMPT]` and the interactive options below.
    static let interactiveCommands: Set<String> = ["resume", "fork"]

    /// The rest of the command surface, which is **not consulted at run time** — an unknown bare
    /// word is refused by the same rule that refuses these. It is declared so
    /// ``CodexCLIIntegrationTests`` can tell a subcommand this app has looked at from one a new
    /// version added, which is the whole drift signal for this dependency.
    static let nonInteractiveCommands: Set<String> = ["agents", "exec", "e", "review", "login",
        "logout", "mcp", "plugin", "app-server", "remote-control", "app", "completion", "update",
        "doctor", "sandbox", "debug", "apply", "a", "queue", "archive", "delete", "migrate-rollouts",
        "unarchive", "cloud", "exec-server", "features", "help",
        // Names an older CLI had; harmless to keep, and refused either way.
        "mcp-server", "agent"]

    /// Interactive options that take a value, and those that do not. The union of `codex`,
    /// `codex resume` and `codex fork` on 0.154.0, plus names older versions had (`--full-auto`).
    static let valueOptions: Set<String> = ["-c", "--config", "--enable", "--disable", "-m", "--model",
        "-p", "--profile", "-C", "--cd", "--add-dir", "-s", "--sandbox", "-a", "--ask-for-approval",
        "-i", "--image", "--local-provider"]
    static let booleanOptions: Set<String> = ["--search", "--full-auto", "--oss", "--approve-for-me",
        "--dangerously-bypass-approvals-and-sandbox", "--no-alt-screen", "--last", "--all",
        "--strict-config", "--worktree", "--dangerously-bypass-hook-trust", "--include-non-interactive"]

    /// Interactive options this app deliberately does not admit, so the drift check can tell them
    /// from an option nobody has classified. `--remote` and its token variable point the TUI at a
    /// remote app server, which is not a local execution and is outside what this app watches;
    /// `--help` and `--version` print and exit, so the process is never a session.
    static let unmonitoredOptions: Set<String> = ["--remote", "--remote-auth-token-env",
        "-h", "--help", "-V", "--version"]

    /// Whether clap could route this token to a subcommand. Every subcommand this CLI has had is
    /// spelled in lowercase ASCII, digits and hyphens, so a prompt that steps outside that
    /// alphabet — a space, a capital, a question mark, a path — cannot be one whatever a future
    /// version adds, and is admitted as the prompt it is.
    static func couldNameASubcommand(_ argument: String) -> Bool {
        !argument.isEmpty && argument.allSatisfy {
            ($0.isASCII && $0.isLowercase) || ($0.isASCII && $0.isNumber) || $0 == "-"
        }
    }

    /// Whether this argv is the interactive TUI rather than one of the CLI's other modes.
    ///
    /// **Refuses what it does not recognise, in both directions.** An unknown option was always
    /// refused; an unknown bare word used to be taken for the prompt, which admitted any
    /// subcommand a future version might add — `codex <newsubcommand>` would have been monitored
    /// as an interactive session, silently and wrongly. The first bare word is now the prompt only
    /// when it *cannot* be a subcommand; otherwise the process is left alone.
    ///
    /// The cost is a single lowercase word used as a prompt (`codex fix`), which is refused. That
    /// is deliberate: refusing is **loud** — the payloads arrive, cannot be attributed, and are
    /// counted into the Codex row's diagnostic in Settings — while admitting is silent. Refusing
    /// is also what the rest of this boundary does with an unreadable home or an unknown option.
    static func isLocalTUI(_ argv: [String]) -> Bool {
        var index = 1
        var positional = false
        while index < argv.count {
            let argument = argv[index]
            let option = argument.split(separator: "=", maxSplits: 1).first.map(String.init) ?? argument
            if valueOptions.contains(option) {
                if option == argument { index += 1; if index >= argv.count { return false } }
            } else if booleanOptions.contains(argument) {
                // A supported boolean option.
            } else if argument.hasPrefix("-") { return false
            } else if !positional {
                // clap routes the first bare word to a subcommand when it names one and treats it
                // as the prompt otherwise, and only the running CLI knows its own list.
                if interactiveCommands.contains(argument) { positional = true }
                else if couldNameASubcommand(argument) { return false }
                else { positional = true }
            }
            index += 1
        }
        return !argv.isEmpty
    }

    /// Desktop places global -c overrides before the app-server subcommand.
    static func isAppServer(_ argv: [String]) -> Bool {
        var index = 1
        while index < argv.count {
            let argument = argv[index]
            let name = argument.split(separator: "=", maxSplits: 1).first.map(String.init) ?? argument
            if ["-c", "--config", "--enable", "--disable"].contains(name) {
                if name == argument { index += 1; if index >= argv.count { return false } }
            } else if argument != "--strict-config" {
                return argument == "app-server"
            }
            index += 1
        }
        return false
    }

    /// Reads argv only. No environment values are retained.
    static func arguments(_ pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size >= 4, size <= 4 * 1024 * 1024 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { return nil }
        return decodeArguments(Array(bytes.prefix(size)))
    }

    static func decodeArguments(_ bytes: [UInt8]) -> [String]? {
        guard bytes.count >= 4 else { return nil }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0, argc < 65536 else { return nil }
        var offset = 4
        func next() -> String? {
            guard offset < bytes.count, let end = bytes[offset...].firstIndex(of: 0),
                  let text = String(bytes: bytes[offset..<end], encoding: .utf8) else { return nil }
            offset = end + 1
            return text
        }
        guard next() != nil else { return nil } // executable path
        while offset < bytes.count && bytes[offset] == 0 { offset += 1 }
        var argv: [String] = []
        for _ in 0..<argc { guard let value = next() else { return nil }; argv.append(value) }
        return argv
    }
}

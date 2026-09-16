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
            LibprocProcessTable().processes(named: "codex")?.compactMap {
                reader.localTUI($0.processIdentifier)
            }
        })
    }
}

/// Observed on 0.154.0; unsupported modes and unreadable process arguments fail closed.
nonisolated struct CodexNativeProcesses: Sendable {
    private let home: URL
    /// Read per use: a CLI installed while this app runs must not need a relaunch to be seen,
    /// and the settings reading resolves it the same way on every check.
    private let command: @Sendable () -> URL?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         command: @escaping @Sendable () -> URL? = { ProductInstallationDiscovery.command(named: "codex") }) {
        self.home = home
        self.command = command
    }

    func owner(of peer: Int32) -> CodexExecution? {
        var pid = peer
        for _ in 0..<32 {
            guard pid > 1,
                  let path = ProcessAncestryHostResolver.systemExecutablePath(ofProcess: pid)
            else { return nil }
            if URL(fileURLWithPath: path).lastPathComponent == "codex" {
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

    func localTUI(_ pid: Int32) -> CodexExecution? {
        guard let path = ProcessAncestryHostResolver.systemExecutablePath(ofProcess: pid),
              let installed = command()?.resolvingSymlinksInPath(),
              URL(fileURLWithPath: path).resolvingSymlinksInPath() == installed,
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

    static func isLocalTUI(_ argv: [String]) -> Bool {
        let values: Set<String> = ["-c", "--config", "--enable", "--disable", "-m", "--model", "-p", "--profile",
            "-C", "--cd", "--add-dir", "-s", "--sandbox", "-a", "--ask-for-approval", "-i", "--image"]
        let flags: Set<String> = ["--search", "--full-auto", "--dangerously-bypass-approvals-and-sandbox",
            "--no-alt-screen", "--last", "--all", "--strict-config", "--worktree",
            "--dangerously-bypass-hook-trust"]
        let commands: Set<String> = ["exec", "e", "review", "login", "logout", "mcp", "mcp-server", "app-server",
            "app", "completion", "sandbox", "debug", "apply", "a", "cloud", "features", "help", "agent", "agents",
            "plugin", "remote-control", "update", "doctor", "queue", "archive", "delete", "migrate-rollouts", "unarchive", "exec-server"]
        var index = 1
        var positional = false
        while index < argv.count {
            let argument = argv[index]
            let option = argument.split(separator: "=", maxSplits: 1).first.map(String.init) ?? argument
            if values.contains(option) {
                if option == argument { index += 1; if index >= argv.count { return false } }
            } else if flags.contains(argument) {
                // A supported boolean option.
            } else if argument.hasPrefix("-") { return false
            } else if !positional {
                if commands.contains(argument) { return false }
                positional = true
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

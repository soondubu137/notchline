import Foundation
import Network
import os

/// Receives one product's lifecycle events over loopback and queues them for
/// the Turn reducer.
///
/// This is the counterpart to the Codex side's helper script. Codex has no HTTP
/// hook type, so there a Python process is spawned per event to write a file;
/// Claude Code can POST directly, which matters because its `PostToolUse` has
/// to be registered without a matcher and a busy session makes hundreds of tool
/// calls. Loopback costs a socket write; a process launch does not.
///
/// Two things this has to do that the helper did not:
///
/// **Stamp arrival.** Claude Code's hook payloads carry no timestamp of any
/// kind — measured 2026-08-16 — where the helper wrote `received_at` itself.
/// The reducer's freshness rule needs one, so it is taken here, at the moment
/// the request lands.
///
/// **Refuse to see the text.** A hook payload carries `prompt`, `tool_input`,
/// `tool_response` and `last_assistant_message`: shell command lines, file
/// paths, diffs, whole answers. ``Payload`` has no field for any of them, so
/// they are dropped by the decoder and cannot reach memory, let alone the
/// queue. What the product promises not to persist, it does not receive.
final class AgentHookListener: @unchecked Sendable {
    private static let log = Logger(
        subsystem: "com.yinfenglu.CodexInNotch",
        category: "AgentHookListener"
    )

    /// The fields taken from a payload. Everything absent here is discarded.
    private struct Payload: Decodable {
        let hookEventName: String?
        let sessionID: String?
        /// Claude Code's name for the turn: "a UUID correlating a user prompt
        /// with all subsequent events until the next prompt".
        let promptID: String?
        let toolName: String?
        let toolUseID: String?
        let permissionMode: String?
        let cwd: String?

        enum CodingKeys: String, CodingKey {
            case hookEventName = "hook_event_name"
            case sessionID = "session_id"
            case promptID = "prompt_id"
            case toolName = "tool_name"
            case toolUseID = "tool_use_id"
            case permissionMode = "permission_mode"
            case cwd
        }
    }

    /// The queue file shape, which is the helper's shape unchanged so both
    /// products' events reduce through one path.
    private struct QueuedEvent: Encodable {
        let eventID: String
        let receivedAt: Double
        let hookEventName: String
        let sessionID: String
        let turnID: String?
        let toolName: String?
        let toolUseID: String?
        let permissionMode: String?

        enum CodingKeys: String, CodingKey {
            case eventID = "event_id"
            case receivedAt = "received_at"
            case hookEventName = "hook_event_name"
            case sessionID = "session_id"
            case turnID = "turn_id"
            case toolName = "tool_name"
            case toolUseID = "tool_use_id"
            case permissionMode = "permission_mode"
        }
    }

    /// A request body larger than this is refused outright rather than read.
    static let maximumBodyBytes = 1 << 20

    private let eventsDirectory: URL
    /// Set when the listener binds, because it comes from the user's settings
    /// rather than from this app: whatever token their registration carries is
    /// the one Claude Code will send.
    private var token: String
    private let clock: any MonitorClock
    private let fileManager: FileManager
    /// Events whose working directory is this one are dropped.
    ///
    /// The quota reading runs `claude -p "/usage"`, which is a real session and
    /// fires real hooks. `UserPromptSubmit` would have separated it from a
    /// human's prompt by its `source` field, except that field was measured
    /// absent from every event including a human's — so the poll is pinned to a
    /// directory of its own and recognised by that instead.
    private let ignoredWorkingDirectory: URL?
    private let queue = DispatchQueue(label: "com.yinfenglu.CodexInNotch.hook-listener")
    private var listener: NWListener?
    private var boundPort: UInt16?

    init(
        eventsDirectory: URL,
        token: String = "",
        ignoredWorkingDirectory: URL? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        fileManager: FileManager = .default
    ) {
        self.eventsDirectory = eventsDirectory
        self.token = token
        self.ignoredWorkingDirectory = ignoredWorkingDirectory
        self.clock = clock
        self.fileManager = fileManager
    }

    /// The port events are being accepted on, once bound.
    var port: UInt16? {
        queue.sync { boundPort }
    }

    /// Binds loopback and starts accepting.
    ///
    /// `preferredPort` is the port the installed configuration already names.
    /// Keeping it means the user's settings do not have to be rewritten on
    /// every launch; failing to get it is ordinary — something else may hold it
    /// — so it falls back to an ephemeral one and the caller repairs the
    /// configuration.
    @discardableResult
    func start(preferredPort: UInt16? = nil, token: String? = nil) -> UInt16? {
        if let token { queue.sync { self.token = token } }
        if let preferredPort, let bound = bind(to: preferredPort) {
            return bound
        }
        return bind(to: 0)
    }

    private func bind(to port: UInt16) -> UInt16? {
        let parameters = NWParameters.tcp
        // Loopback only. This accepts lifecycle events from processes on this
        // machine and must not be reachable from anywhere else.
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port) ?? .any
        )
        guard let listener = try? NWListener(using: parameters) else { return nil }

        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled:
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 2)

        guard case .ready = listener.state, let bound = listener.port?.rawValue else {
            listener.cancel()
            return nil
        }
        queue.sync {
            self.listener?.cancel()
            self.listener = listener
            self.boundPort = bound
        }
        return bound
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            boundPort = nil
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            guard error == nil else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let chunk { buffer.append(chunk) }

            switch self.consume(buffer) {
            case .needMore:
                if isComplete {
                    connection.cancel()
                } else if buffer.count > Self.maximumBodyBytes {
                    self.respond(connection, status: "413 Payload Too Large")
                } else {
                    self.receive(connection, buffer: buffer)
                }
            case let .answer(status, body):
                if let body { self.record(body) }
                self.respond(connection, status: status)
            }
        }
    }

    private enum Outcome {
        case needMore
        case answer(status: String, body: Data?)
    }

    /// Parses one HTTP/1.1 request, far enough to decide and no further.
    private func consume(_ buffer: Data) -> Outcome {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else { return .needMore }
        guard let head = String(
            data: buffer[buffer.startIndex ..< headerEnd.lowerBound],
            encoding: .utf8
        ) else {
            return .answer(status: "400 Bad Request", body: nil)
        }

        let lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return .answer(status: "400 Bad Request", body: nil)
        }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2, requestParts[0] == "POST" else {
            return .answer(status: "405 Method Not Allowed", body: nil)
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[line.startIndex ..< colon].lowercased()] =
                line[line.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
        }

        // Constant-time comparison: the token is a nonce guarding a loopback
        // socket rather than a credential, but there is no reason to leak it.
        let offered = headers["authorization"] ?? ""
        let expected = "Bearer \(token)"
        guard offered.utf8.count == expected.utf8.count,
              zip(offered.utf8, expected.utf8).reduce(0, { $0 | ($1.0 ^ $1.1) }) == 0
        else {
            return .answer(status: "403 Forbidden", body: nil)
        }

        guard let length = Int(headers["content-length"] ?? ""), length >= 0 else {
            return .answer(status: "411 Length Required", body: nil)
        }
        guard length <= Self.maximumBodyBytes else {
            return .answer(status: "413 Payload Too Large", body: nil)
        }

        let bodyStart = headerEnd.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else {
            return .needMore
        }
        let body = buffer[bodyStart ..< buffer.index(bodyStart, offsetBy: length)]
        return .answer(status: "200 OK", body: Data(body))
    }

    private func respond(_ connection: NWConnection, status: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(
            content: Data(response.utf8),
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }

    /// Writes one event into the queue, having already answered the request.
    ///
    /// Answering first is deliberate: nothing this app does may sit on a user's
    /// session. A hook that blocked here would slow every tool call they make.
    private func record(_ body: Data) {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: body),
              let eventName = payload.hookEventName,
              let sessionID = payload.sessionID else {
            return
        }
        // Our own quota reading is a real session firing real hooks.
        // Compared as paths rather than URLs: a URL built from a payload string
        // is not marked as a directory, and URL equality counts that, so two
        // spellings of the same folder would not match.
        if let ignoredWorkingDirectory, let cwd = payload.cwd,
           URL(fileURLWithPath: cwd).standardizedFileURL.path
            == ignoredWorkingDirectory.standardizedFileURL.path {
            return
        }

        let receivedAt = clock.now().timeIntervalSince1970
        let event = QueuedEvent(
            eventID: UUID().uuidString,
            receivedAt: receivedAt,
            hookEventName: eventName,
            sessionID: sessionID,
            // A subagent's events carry the parent's session and prompt ids, so
            // they fold into the turn that spawned them with nothing to do here.
            turnID: payload.promptID,
            toolName: payload.toolName,
            toolUseID: payload.toolUseID,
            permissionMode: payload.permissionMode
        )

        guard let data = try? JSONEncoder().encode(event) else { return }
        try? fileManager.createDirectory(
            at: eventsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // Ordered by arrival, so the consumer sorts by name the way it does for
        // the helper's files.
        let name = String(format: "%.6f-%@.json", receivedAt, event.eventID)
        let url = eventsDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Self.log.error("failed to queue hook event: \(error.localizedDescription)")
        }
    }
}

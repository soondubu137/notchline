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
/// **Keep the text out of the queue.** A hook payload carries `prompt`,
/// `tool_input`, `tool_response` and `last_assistant_message`: shell command
/// lines, file paths, diffs, whole answers. ``Payload`` has no field for any of
/// them, so they are dropped by the decoder and cannot reach the queue — which
/// is a directory of files, and therefore the disk.
///
/// One exception is collected, on purpose and only in memory: `MessageDisplay`
/// carries the assistant text as it is printed to the screen, and that is the
/// row's third line (CC-015). It is decoded by a *second* decoder, diverted in
/// ``record(_:)`` before the queue is touched, and held in
/// ``previewsBySessionID`` — never encoded into ``QueuedEvent``, never written.
/// The Codex side needs a whole Unix socket for the same guarantee, because
/// there a hook is a shell command and the only other way home is a file; here
/// the text is already inside this process when it arrives.
///
/// Two consequences of the event's shape. Measured against CLI 2.1.234 by
/// driving an interactive session under a pty, against a listener registered
/// through a temporary `--settings` file — one 1561-character message arrived
/// as eleven deltas, 0.20s to 0.44s apart, mean 0.29s:
///
/// - at three a second it must not become a file each time, which is what
///   diverting it in ``record(_:)`` is for;
/// - only the *head* of each message is kept, so a long answer costs nothing
///   after its first 240 characters and the retained bytes per session are
///   bounded by a constant rather than by how much the model said. The row
///   therefore shows the beginning of whatever message is being printed now —
///   not a running tail, and not the turn concatenated.
final class AgentHookListener: @unchecked Sendable {
    private static let log = Logger(
        subsystem: "com.yinfenglu.CodexInNotch",
        category: "AgentHookListener"
    )

    /// The fields taken from a payload. Everything absent here is discarded.
    ///
    /// Deliberately without any text field. Everything decoded here is eligible
    /// to be written into the queue, so the absence is the guarantee.
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

    /// The fields taken from a `MessageDisplay` payload.
    ///
    /// A second decoder rather than two more cases on ``Payload``, because this
    /// one carries the assistant's words and ``Payload`` is what feeds the
    /// queue. Nothing decoded here is reachable from ``QueuedEvent``.
    ///
    /// The published payload is `turn_id, message_id, index, final, delta`, and
    /// only two of the five are needed: a new `message_id` is what ends the
    /// previous message, and only the head of each is kept, so there is nothing
    /// for a completion flag or an ordinal to decide. `turn_id` is worth a note
    /// even unused — this is the only event carrying both it and `prompt_id`,
    /// and the reducer's identity is `prompt_id`.
    ///
    /// `delta` is documented as *"the newly completed lines"*, and measured to
    /// be exactly that on CLI 2.1.234 — which is what makes the fold in
    /// ``normalizedPreview(appending:to:carriedLength:)`` a line join rather
    /// than a concatenation. Two shapes were measured:
    ///
    /// - **interactive**: incremental, never cumulative — successive deltas of
    ///   one message began `1. `, `2. `, `3. `, each starting where the last
    ///   stopped — and every non-final one ended on a newline;
    /// - **`-p`**: one delivery, `index: 0`, `final: true`, the whole message
    ///   with its newlines intact inside the single delta.
    ///
    /// The first of those is the load-bearing one. Were `delta` cumulative,
    /// appending would repeat the message on every chunk.
    private struct MessageDisplayPayload: Decodable {
        let messageID: String?
        let delta: String?

        enum CodingKeys: String, CodingKey {
            case messageID = "message_id"
            case delta
        }
    }

    /// One session's live preview, and the message it was read from.
    private struct SessionPreview {
        /// Whichever assistant message is currently being printed. When this
        /// changes the text starts again — the newest message is the progress,
        /// and its head is what the row reports.
        let messageID: String?
        var text: String
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

    /// The event that carries assistant text, and the only one that does.
    ///
    /// Officially described as "While assistant message text is displayed".
    /// It is absent from the exploration document's table of events, which is
    /// why the first pass at this product concluded no such thing existed.
    static let messageDisplayEventName = "MessageDisplay"

    /// How much of one message is kept.
    ///
    /// The same 240 the Codex helper truncates to, so the two products' rows
    /// are cut at the same place. It is also the memory bound: once the head is
    /// full every further delta is dropped without being stored.
    static let maximumPreviewCharacters = 240

    /// How many sessions' previews are held before the oldest is dropped.
    ///
    /// Previews are pruned to the live session list on every refresh, so this
    /// is a leak stop for text belonging to a session that never appears there
    /// — not a working set.
    static let maximumRetainedPreviews = 64

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

    /// Preview state, under a lock of its own rather than under ``queue``.
    ///
    /// ``setAcceptsText(_:)`` is a privacy control and has to take effect on the
    /// caller's thread, in order. `queue` also serves connections and writes
    /// queue files, so putting the switch behind it would make an infallible
    /// control wait on file I/O for no reason. Same shape, and same reasoning,
    /// as ``HookPreviewChannel``.
    private let previewLock = NSLock()
    private var previewsBySessionID: [String: SessionPreview] = [:]
    private var previewOrder: [String] = []
    private var acceptsText = true
    /// The sessions the last refresh listed, as handed to ``retainPreviews``.
    ///
    /// Held only to qualify the edge below.
    private var listedSessionIDs: Set<String> = []
    /// Told when a session gains a preview it did not have.
    ///
    /// Deltas themselves are deliberately off the change stream -- three a
    /// second is not a redraw rate -- but a row holding *no* text is a
    /// different case: nothing on screen is stale, something is missing, and
    /// the next thing that would ask happens to be whatever the session does
    /// next. That gap is what made turning content previews back on look
    /// broken: collection resumes at once, but the row it belongs to was drawn
    /// while previews were off and nobody was going to draw it again.
    ///
    /// Only the absent-to-present edge, so the cost is one wake per session per
    /// spell of having nothing to show, not one per delta.
    ///
    /// Set after construction rather than taken in `init`, so the service wires
    /// it to whichever listener it ends up with -- its own or an injected one.
    /// Held under ``previewLock`` with the previews themselves: it is read on
    /// the connection queue, and a handler installed while a delta is being
    /// folded must not be a data race.
    private var onPreviewAppeared: (@Sendable () -> Void)?

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

    /// Registers the handler for ``onPreviewAppeared``.
    func setOnPreviewAppeared(_ handler: (@Sendable () -> Void)?) {
        previewLock.lock()
        onPreviewAppeared = handler
        previewLock.unlock()
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
                self.respond(connection, status: status)
                if let body { self.record(body) }
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

    /// Takes one event: to memory if it is text, to the queue otherwise.
    ///
    /// **Answering comes first**, and since `MessageDisplay` it matters more
    /// than it used to. Every registration is *synchronous*: Claude Code's HTTP
    /// hook configuration has no key for background delivery — the `async: true`
    /// this app used to write is not one of its schema's fields and is dropped
    /// by its settings parser, measured against 2.1.233 and 2.1.235. So the CLI
    /// waits for this response, and a talking turn waits three times a second.
    /// Nothing this app does may sit on a user's session, so the response goes
    /// out before any work is done, on the serial queue that already orders
    /// every connection. That ordering is the whole of what keeps these hooks
    /// off the user's critical path; there is no configuration doing it.
    ///
    /// The work is bounded regardless: one decode, and for `MessageDisplay` a
    /// scan of one delta that stops at ``maximumPreviewCharacters``.
    ///
    /// A body over ``maximumBodyBytes`` is refused before it reaches here. For a
    /// lifecycle event that loses the event; for `MessageDisplay` it loses one
    /// message's preview, which is the same degradation as no listener at all:
    /// a missing preview rather than a stale one.
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

        // Assistant text turns back here. It goes to memory and the method
        // returns: no queue file is written, which is both the privacy
        // guarantee and the reason a 0.3s event does not become 0.3s of disk.
        //
        // Returning also keeps this event off ``HookEventRepository``'s change
        // stream, so a talking turn does not redraw the panel three times a
        // second. The text is picked up by whatever refresh the turn's own
        // lifecycle events cause, which is the cadence the panel already runs
        // at — see AGENTS.md §7.
        if eventName == Self.messageDisplayEventName {
            recordPreview(from: body, sessionID: sessionID)
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

    // MARK: - Previews

    /// The text this session is currently printing, if any was collected.
    ///
    /// Read, not consumed. A preview stands until the message it came from is
    /// replaced or the session leaves the live list, because a turn spends most
    /// of its life between events and a row that blanked itself after one
    /// refresh would flicker rather than report.
    func preview(forSession sessionID: String) -> String? {
        previewLock.lock()
        let text = previewsBySessionID[sessionID]?.text
        previewLock.unlock()
        // The stored form keeps its trailing space so the next delta can join
        // onto it; a row never shows one.
        guard let trimmed = text?.trimmingCharacters(in: .whitespaces),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Drops previews for sessions that are no longer live.
    ///
    /// Called with the same set the transcript reader is pruned with, so the
    /// text of a session that has ended does not outlive the row that showed
    /// it.
    func retainPreviews(forSessions sessionIDs: Set<String>) {
        previewLock.lock()
        defer { previewLock.unlock() }
        previewsBySessionID = previewsBySessionID.filter { sessionIDs.contains($0.key) }
        previewOrder.removeAll { !sessionIDs.contains($0) }
        listedSessionIDs = sessionIDs
    }

    /// Whether received text is retained at all.
    ///
    /// The privacy switch, and an in-memory flag for the same reason
    /// ``HookPreviewChannel``'s is: there is no write to lose, no revision to
    /// race, and no way for the settings to show "off" while text is still
    /// being kept. Turning it off discards what is already held.
    func setAcceptsText(_ accepts: Bool) {
        previewLock.lock()
        acceptsText = accepts
        if !accepts {
            previewsBySessionID.removeAll()
            previewOrder.removeAll()
        }
        previewLock.unlock()
    }

    /// Discards collected text without changing whether more is accepted.
    func discardPreviews() {
        previewLock.lock()
        previewsBySessionID.removeAll()
        previewOrder.removeAll()
        previewLock.unlock()
    }

    /// Folds one `MessageDisplay` delta into the session's preview.
    ///
    /// Only the head of a message is ever held. Once it is full the delta is
    /// dropped before it is decoded into anything retained, so the cost of a
    /// long answer is a comparison — and the bytes held per session cannot grow
    /// past ``maximumPreviewCharacters`` no matter how much the model says.
    private func recordPreview(from body: Data, sessionID: String) {
        previewLock.lock()
        let accepts = acceptsText
        let existing = previewsBySessionID[sessionID]
        previewLock.unlock()
        guard accepts else { return }

        guard let payload = try? JSONDecoder().decode(
            MessageDisplayPayload.self,
            from: body
        ), let delta = payload.delta, !delta.isEmpty else { return }

        // A new message replaces the old one rather than extending it: the row
        // shows the message being printed now, not the whole turn concatenated.
        let carried = existing?.messageID == payload.messageID ? (existing?.text ?? "") : ""
        let carriedLength = carried.count
        guard carriedLength < Self.maximumPreviewCharacters else { return }
        let text = Self.normalizedPreview(
            appending: delta,
            to: carried,
            carriedLength: carriedLength
        )
        guard !text.isEmpty else { return }

        previewLock.lock()
        // Re-checked under the lock: the switch may have been turned off while
        // this delta was being decoded, and a privacy control that loses a race
        // is not one.
        guard acceptsText else {
            previewLock.unlock()
            return
        }
        let isFirstSinceEmpty = previewsBySessionID[sessionID] == nil
        if isFirstSinceEmpty {
            previewOrder.append(sessionID)
        }
        previewsBySessionID[sessionID] = SessionPreview(
            messageID: payload.messageID,
            text: text
        )
        while previewOrder.count > Self.maximumRetainedPreviews {
            previewsBySessionID.removeValue(forKey: previewOrder.removeFirst())
        }
        // Only for a session the last refresh actually listed. Without that
        // test this is a 3 Hz loop rather than one wake: text from a session
        // the list does not carry is pruned by the very refresh it asks for,
        // which makes the next delta an absent-to-present edge again -- and
        // the row it would draw is not on screen either way.
        let appeared = isFirstSinceEmpty && listedSessionIDs.contains(sessionID)
            ? onPreviewAppeared
            : nil
        previewLock.unlock()

        // Outside the lock. Whoever is told asks this listener what it holds
        // straight back, and a privacy switch that can deadlock behind a redraw
        // is not one either.
        appeared?()
    }

    /// Folds one delta onto a head that is already normalised, in one pass.
    ///
    /// One line, collapsed and cut, the way the Codex side cuts its own:
    /// control characters dropped, runs of whitespace collapsed to one space,
    /// no leading space, and never longer than ``maximumPreviewCharacters``.
    ///
    /// `carried` is seeded rather than rescanned, and the running length is
    /// carried as an `Int`. Both matter: `String.count` walks grapheme breaks,
    /// so the previous form — rebuild `carried + delta`, then test `.count`
    /// after every character — was quadratic in the cap and additionally copied
    /// the whole delta, which may be up to ``maximumBodyBytes``. Now the scan
    /// touches only the new delta and stops the moment the head is full, so an
    /// oversized delta costs the same as an ordinary one.
    ///
    /// A single trailing space **is** kept, unlike the Codex side's one-shot
    /// version, and the seed relies on it: measured on CLI 2.1.234, every
    /// non-final delta ends on a line break, which collapses to that trailing
    /// space — so the next delta joins onto it and no separator is invented.
    /// Only a message's final delta ends mid-line, and that is what
    /// `pendingSpace` is seeded for. Trimming the tail here instead would weld
    /// the last word of one delta onto the first word of the next; the caller
    /// trims it when the text is read.
    nonisolated private static func normalizedPreview(
        appending delta: String,
        to carried: String,
        carriedLength: Int
    ) -> String {
        var normalized = carried
        normalized.reserveCapacity(maximumPreviewCharacters)
        var length = carriedLength
        var pendingSpace = !normalized.isEmpty && !normalized.hasSuffix(" ")

        for character in delta {
            if character.isWhitespace {
                // Never leading: a message that opens with a newline should not
                // spend its first character on it.
                pendingSpace = !normalized.isEmpty
                continue
            }
            guard !character.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains
            ) else { continue }

            if pendingSpace {
                normalized.append(" ")
                pendingSpace = false
                length += 1
                if length >= maximumPreviewCharacters { return normalized }
            }
            normalized.append(character)
            length += 1
            if length >= maximumPreviewCharacters { return normalized }
        }

        if pendingSpace { normalized.append(" ") }
        return normalized
    }
}

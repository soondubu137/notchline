import Foundation
import os

/// Receives one product's lifecycle events over a Unix domain socket and queues
/// them for the Turn reducer.
///
/// **Why a socket and not a port.** This used to be an HTTP listener on
/// `127.0.0.1:51741`, because Claude Code can POST a hook payload directly and
/// that costs a socket write where a `command` hook costs a process launch —
/// which matters when `PostToolUse` has to be registered without a matcher and
/// a busy session makes hundreds of tool calls. The port turned out to cost
/// more than the process. Nothing owns it while this app is closed, so the CLI
/// prints `connect ECONNREFUSED` once per event in the user's session, with no
/// setting that suppresses it; and being unowned inside the ephemeral range, it
/// can be taken by any local process, which then receives the prompt and can
/// answer with `permissionDecision`. Neither is fixable from the registration
/// (CC-021, CC-014). A helper that exits 0 says nothing when this app is
/// closed, and a socket in a directory this app owns cannot be taken.
///
/// The helper is `ClaudeCodeHookSetup.helperScript(socketPath:)`: `nc -U` and
/// an unconditional `exit 0`. One connection carries one payload and is closed
/// by the writer, so the frame is simply "read to EOF" — there is no request
/// line, no header, and no token, because the socket is `0600` in this user's
/// own directory and the filesystem answers the question a bearer token used to.
///
/// Two things this has to do that the Codex helper did not:
///
/// **Stamp arrival.** Claude Code's hook payloads carry no timestamp of any
/// kind — measured 2026-08-16 — where the helper wrote `received_at` itself.
/// The reducer's freshness rule needs one, so it is taken here, at the moment
/// the payload lands.
///
/// **Keep `MessageDisplay` out of the queue.** That event carries the assistant
/// text as it is printed to the screen, and that is the row's third line
/// (CC-015). It is decoded by a *second* decoder, diverted in ``record(_:)``
/// before the queue is touched, and held in ``previewsBySessionID``. This is a
/// performance rule, not a privacy one (PRD 7): the queue is a directory of
/// files, and measured against CLI 2.1.234 by driving an interactive session
/// under a pty, one 1561-character message arrived as eleven deltas, 0.20s to
/// 0.44s apart, mean 0.29s. At three a second it must not become a file each
/// time.
///
/// Only the *head* of each message is kept, so a long answer costs nothing
/// after its first 240 characters and the retained bytes per session are
/// bounded by a constant rather than by how much the model said. The row
/// therefore shows the beginning of whatever message is being printed now — not
/// a running tail, and not the turn concatenated.
///
/// **Order is preserved by the read queue, not promised by the transport.**
/// Connections are accepted in arrival order and handed to one serial queue, so
/// ``record(_:)`` runs in the order the payloads landed. That is worth stating
/// because the registration is deliberately synchronous: Claude Code's
/// `command` schema does have an `async` key, unlike its `http` one, and using
/// it was measured to reorder a `PreToolUse` against its own `PostToolUse` and
/// to lose `Stop` entirely under `-p`, where the process exits before a
/// backgrounded hook finishes. Paying 6.3 ms on the session buys both back.
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

    /// A payload larger than this is dropped rather than read to the end.
    static let maximumBodyBytes = 1 << 20

    /// How long one connection may take to deliver its payload.
    ///
    /// The helper connects, writes once and closes, so anything slower is a
    /// client that has stopped making progress. It has to be well inside the
    /// helper's own `nc -w 1`, which is in turn inside the registration's
    /// `timeout: 3` -- three bounds, innermost first, so the one that fires is
    /// always the one closest to the problem.
    ///
    /// This only bounds anything on a *blocking* descriptor; see
    /// ``receivePayload(on:)``, which is where that is made true.
    static let receiveTimeoutMicroseconds: Int32 = 250_000

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

    /// Listening state, under a lock rather than a queue.
    ///
    /// Same shape as ``HookPreviewChannel``: the accept handler runs on one GCD
    /// queue, payloads are read on another, and the shared state is two fields.
    private let socketLock = NSLock()
    private var listeningDescriptor: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var boundSocketURL: URL?

    private let acceptQueue = DispatchQueue(
        label: "com.yinfenglu.CodexInNotch.hook-listener.accept"
    )
    /// Serial on purpose: it is what makes ``record(_:)`` see payloads in the
    /// order they arrived.
    private let readQueue = DispatchQueue(
        label: "com.yinfenglu.CodexInNotch.hook-listener.read"
    )

    /// Preview state, under a lock of its own rather than under ``queue``.
    ///
    /// `queue` also serves connections and writes queue files, so holding this
    /// behind it would make a memory-only read wait on file I/O for no reason.
    /// Same shape as ``HookPreviewChannel``.
    private let previewLock = NSLock()
    private var previewsBySessionID: [String: SessionPreview] = [:]
    private var previewOrder: [String] = []
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
    /// next. A turn that talks for a minute before it touches a tool sends no
    /// lifecycle event in the meantime, so without this edge its row stays
    /// blank for as long as it keeps talking.
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
        ignoredWorkingDirectory: URL? = nil,
        clock: any MonitorClock = SystemMonitorClock(),
        fileManager: FileManager = .default
    ) {
        self.eventsDirectory = eventsDirectory
        self.ignoredWorkingDirectory = ignoredWorkingDirectory
        self.clock = clock
        self.fileManager = fileManager
    }

    deinit {
        stop()
    }

    /// Registers the handler for ``onPreviewAppeared``.
    func setOnPreviewAppeared(_ handler: (@Sendable () -> Void)?) {
        previewLock.lock()
        onPreviewAppeared = handler
        previewLock.unlock()
    }

    /// The socket payloads are being accepted on, once bound.
    var socketURL: URL? {
        socketLock.lock()
        defer { socketLock.unlock() }
        return boundSocketURL
    }

    /// Binds the socket and starts accepting.
    ///
    /// Returns `false` rather than throwing: the caller's only recourse is to
    /// report it in the settings card, and every failure here has the same
    /// consequence — the helper the user pasted has nothing to hand its
    /// payloads to.
    @discardableResult
    func start(socketURL: URL) -> Bool {
        socketLock.lock()
        let alreadyBound = listeningDescriptor >= 0 && boundSocketURL == socketURL
        socketLock.unlock()
        if alreadyBound { return true }
        stop()

        let pathBytes = Array(socketURL.path.utf8)
        // `sun_path` is a fixed 104-byte field, and a home directory deep
        // enough to overflow it would otherwise fail inside `bind` with an
        // errno nobody could act on.
        guard pathBytes.count < MemoryLayout<sockaddr_un>.size
            - MemoryLayout<UInt8>.size * 2 else {
            Self.log.error("hook socket path is too long to bind")
            return false
        }

        try? fileManager.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // A socket left behind by a crash keeps `bind` from succeeding, and it
        // is ours by construction -- it lives in a directory this app owns.
        unlink(socketURL.path)

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }
        address.sun_len = UInt8(
            MemoryLayout<sockaddr_un>.size - MemoryLayout.size(ofValue: address.sun_path)
                + pathBytes.count
        )
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            close(descriptor)
            return false
        }

        // Only this user's processes may hand events to this app. This is the
        // whole of the access control, and it is stronger than the bearer token
        // it replaced: that one authenticated the CLI to the listener and said
        // nothing about who the listener was.
        chmod(socketURL.path, 0o600)

        guard listen(descriptor, 64) == 0 else {
            close(descriptor)
            unlink(socketURL.path)
            return false
        }

        // Non-blocking so the accept handler can drain the backlog and return
        // rather than parking the queue on the next connection.
        let flags = fcntl(descriptor, F_GETFL, 0)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(
            fileDescriptor: descriptor,
            queue: acceptQueue
        )
        source.setEventHandler { [weak self] in
            self?.acceptPendingConnections()
        }
        source.setCancelHandler {
            close(descriptor)
        }

        socketLock.lock()
        listeningDescriptor = descriptor
        acceptSource = source
        boundSocketURL = socketURL
        socketLock.unlock()

        source.resume()
        return true
    }

    func stop() {
        socketLock.lock()
        let source = acceptSource
        let url = boundSocketURL
        acceptSource = nil
        listeningDescriptor = -1
        boundSocketURL = nil
        socketLock.unlock()

        source?.cancel()
        if let url { unlink(url.path) }
    }

    private func acceptPendingConnections() {
        socketLock.lock()
        let descriptor = listeningDescriptor
        socketLock.unlock()
        guard descriptor >= 0 else { return }

        while true {
            let connection = accept(descriptor, nil, nil)
            guard connection >= 0 else { return }
            readQueue.async { [weak self] in
                self?.receivePayload(on: connection)
            }
        }
    }

    /// Reads one payload and hands it to ``record(_:)``.
    ///
    /// One connection is one payload: the helper writes what it was given on
    /// stdin and closes, so the end of the message is the end of the stream and
    /// there is no framing to get wrong.
    private func receivePayload(on descriptor: Int32) {
        defer { close(descriptor) }

        // Darwin hands `accept` a descriptor that inherits the listening
        // socket's file status flags, and the listening socket is `O_NONBLOCK`
        // so the accept handler can drain its backlog rather than park on the
        // next connection. Inherited here that is silent data loss: a client
        // that has connected but whose write has not landed yet makes `read`
        // fail with `EAGAIN`, which the loop below cannot tell from the end of
        // a payload, so the event is dropped for good instead of waited for.
        // This is the same trap ``HookPreviewChannel`` documents as CC-023, and
        // clearing the flag is what makes the timeout below the thing that
        // bounds this.
        let flags = fcntl(descriptor, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK)
        }

        var timeout = timeval(tv_sec: 0, tv_usec: Self.receiveTimeoutMicroseconds)
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var payload = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
        while payload.count <= Self.maximumBodyBytes {
            let readCount = read(descriptor, &buffer, buffer.count)
            guard readCount > 0 else { break }
            payload.append(contentsOf: buffer[0 ..< readCount])
        }

        // Over the cap is dropped rather than truncated: a half payload decodes
        // to nothing useful and would be quarantined as corruption.
        guard !payload.isEmpty, payload.count <= Self.maximumBodyBytes else {
            return
        }
        record(payload)
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
        // returns: no queue file is written, which is why a 0.3s event does not
        // become 0.3s of disk.
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

    /// Folds one `MessageDisplay` delta into the session's preview.
    ///
    /// Only the head of a message is ever held. Once it is full the delta is
    /// dropped before it is decoded into anything retained, so the cost of a
    /// long answer is a comparison — and the bytes held per session cannot grow
    /// past ``maximumPreviewCharacters`` no matter how much the model says.
    private func recordPreview(from body: Data, sessionID: String) {
        previewLock.lock()
        let existing = previewsBySessionID[sessionID]
        previewLock.unlock()

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
        // straight back, so calling it under the lock would deadlock.
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

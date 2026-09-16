import Foundation

/// Execution ownership is not a current-view signal: /new keeps the previous runtime alive.
/// Serial Hook delivery records provenance before enqueueing evidence in the sole reducer.
nonisolated final class CodexSurfaceLedger: SessionProcessLocating, @unchecked Sendable {
    let changes = MonitoringChangeBroadcast()
    private let source: CodexProcessSource
    private let lock = NSLock()
    private var owners: [String: Set<CodexExecution>] = [:]
    private var discovered: [CodexExecution] = []
    private var scannedAt: Date?
    private var scanKnown = false
    private var turnOwners: [String: (turn: String, owner: CodexExecution)] = [:]
    private struct EndedBinding: Hashable { let thread: String; let owner: CodexExecution }
    private var ended: Set<EndedBinding> = []

    /// How long one process inventory answers for. A ceiling on repeat cost within a burst of
    /// refreshes, never a cadence: nothing wakes the store to re-scan (see ``refresh(at:)``).
    static let scanLifetime: TimeInterval = 5

    init(source: CodexProcessSource = .live()) { self.source = source }

    func receive(_ body: Data, at date: Date, descriptor: Int32, repository: MonitoringRepository) -> AgentHookListener.Disposition {
        // Nothing unattributable may own a Thread, so this drop happens before the reducer — but
        // never in silence. A custom `CODEX_HOME`, an excluded mode, an unreadable sender and a
        // process that died mid-handshake all arrive in this shape, and unreported they read as
        // "hooks are not firing" with nothing on screen to say otherwise.
        guard let owner = source.resolvePeer(descriptor), source.isAlive(owner) else {
            (repository.boundary as? HookEvidenceBoundary)?.recordUnattributedPayload()
            return .close
        }
        // No identity or no supported kind: this ledger can book no ownership from it, but the
        // repository's boundary already counts an unreadable payload and an unsupported kind under
        // sentences of their own. Short-circuiting here is what lost them.
        guard let event = HookPayload.distilled(from: body, admittingRequestWhere: { _, _ in false }),
              let thread = event.sessionID, !thread.isEmpty,
              let name = event.hookEventName,
              CodexHookVocabulary().signal(forEvent: name, toolName: event.toolName) != nil
        else { return repository.deliver(body, at: date, on: descriptor) }
        // Refused by the ownership contract, and silent by design: a late event under an ended
        // binding and a second executor's handle for a live Turn are both expected here, so
        // reporting them would cry wolf on the one diagnostic that means monitoring is broken.
        guard record(owner: owner, thread: thread, event: name, isSubagent: event.agentID != nil),
              event.agentID != nil || admit(owner: owner, thread: thread, turn: event.turnID, event: name)
        else { return .close }
        return repository.deliver(body, at: date, on: descriptor)
    }

    /// Two executors cannot supply interchangeable request handles for the same native Turn.
    func admit(owner: CodexExecution, thread: String, turn: String?, event: String) -> Bool {
        guard let turn else { return true }
        lock.lock(); defer { lock.unlock() }
        if let previous = turnOwners[thread], previous.turn == turn,
           previous.owner != owner, source.isAlive(previous.owner) { return false }
        if event == "UserPromptSubmit" || turnOwners[thread] == nil {
            turnOwners[thread] = (turn, owner)
        }
        return true
    }

    @discardableResult
    func record(owner: CodexExecution, thread: String, event: String, isSubagent: Bool = false) -> Bool {
        lock.lock()
        let binding = EndedBinding(thread: thread, owner: owner)
        if ended.contains(binding) && (event != "SessionStart" || isSubagent) {
            lock.unlock()
            return false
        }
        let oldOwners = owners[thread]
        if event == "SessionEnd", !isSubagent {
            ended.insert(binding)
            owners[thread]?.remove(owner)
            if turnOwners[thread]?.owner == owner { turnOwners.removeValue(forKey: thread) }
        } else {
            if event == "SessionStart", !isSubagent { ended.remove(binding) }
            owners[thread, default: []].insert(owner)
        }
        let changed = oldOwners != owners[thread]
        lock.unlock()
        if changed { changes.signal() }
        return true
    }

    struct Reading: Sendable {
        let threadIDs: Set<String>
        let cliIsOpen: Bool?
        /// A live Desktop execution owns at least one Thread. **Positive only**: false means this
        /// ledger has nothing to say, never that Desktop is closed — a Desktop sitting idle with
        /// every Thread ended owns nothing, and is still open. Desktop has no inventory to read,
        /// so there is no third answer here; `false` defers to the running-application reading.
        let desktopIsOpen: Bool
    }

    /// The inventory is read opportunistically, as `AntigravityConversationScanner` reads its locks:
    /// it answers presence and nothing else, and no state says when a TUI that has never sent a Hook
    /// appeared, so a due date for it is one no refresh can clear — it would wake every product every
    /// five seconds for the life of the app, screen asleep included. A TUI started normally sends
    /// `SessionStart`, which books an owner and wakes the store on its own; one started before this
    /// app, or with Hooks untrusted, is found at the next refresh from any cause and until then the
    /// dot is the last reading. Liveness is not on this cache: an exited owner or TUI retires below
    /// on every refresh, so a stale inventory can only under-report, never keep a dead TUI open.
    func refresh(at now: Date) -> Reading {
        lock.lock()
        defer { lock.unlock() }
        if scannedAt.map({ now < $0 || now.timeIntervalSince($0) >= Self.scanLifetime }) ?? true {
            let processes = source.localProcesses()
            scanKnown = processes != nil
            if let processes { discovered = processes }
            scannedAt = now
        }
        owners = owners.mapValues { Set($0.filter(source.isAlive)) }.filter { !$0.value.isEmpty }
        turnOwners = turnOwners.filter { owners[$0.key] != nil }
        ended = ended.filter { source.isAlive($0.owner) }
        discovered = discovered.filter(source.isAlive)
        // Both read `owners`, which the line above has already cut to executions still alive: an
        // owner is a kernel fact (pid *and* start time), so it is stronger evidence that a surface
        // is open than any application listing, and it cannot outlive the process it names.
        let anyCLI = !discovered.isEmpty || owners.values.contains { $0.contains { $0.surface == .cli } }
        let anyDesktop = owners.values.contains { $0.contains { $0.surface == .desktop } }
        return Reading(
            threadIDs: Set(owners.keys),
            cliIsOpen: anyCLI ? true : (scanKnown ? false : nil),
            desktopIsOpen: anyDesktop
        )
    }

    func isCLI(_ thread: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        // A Thread active on both surfaces has no unique terminal read authority.
        let live = owners[thread, default: []]
        return !live.isEmpty && live.allSatisfy { $0.surface == .cli }
    }

    func hasCLI(_ thread: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return owners[thread, default: []].contains { $0.surface == .cli }
    }

    /// Which surface can be raised for this Thread **right now**, or nil when none can.
    ///
    /// One question for both surfaces, asked at click time. Routing used to ask two that disagreed
    /// about liveness: the CLI side read the owners the last refresh left behind, while the Desktop
    /// side re-read the kernel. A terminal that closed in between was still routed to, and failed
    /// further down under a different error type and a different sentence than the identical
    /// Desktop case. An owner that has exited is gone on either surface, and is said so once here.
    ///
    /// Desktop answers for a Thread open on both: a Thread this app can deep-link is not navigated
    /// by raising a terminal that also holds it.
    func navigableSurface(ofThread thread: String) -> CodexExecution.Surface? {
        lock.lock(); defer { lock.unlock() }
        let live = owners[thread, default: []].filter(source.isAlive)
        if live.contains(where: { $0.surface == .desktop }) { return .desktop }
        return live.isEmpty ? nil : .cli
    }

    func processIdentifier(forThreadID threadID: String) async -> Int32? {
        navigationProcess(threadID)
    }

    func navigationProcess(_ thread: String) -> Int32? {
        lock.lock(); defer { lock.unlock() }
        let live = owners[thread, default: []].filter(source.isAlive)
        guard live.count == 1, let owner = live.first, owner.surface == .cli else { return nil }
        return owner.pid
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        owners.removeAll(); turnOwners.removeAll(); ended.removeAll()
        discovered.removeAll(); scannedAt = nil; scanKnown = false
    }
}

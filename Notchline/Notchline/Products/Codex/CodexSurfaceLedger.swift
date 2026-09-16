import Foundation

/// Execution ownership is not a current-view signal: /new keeps the previous runtime alive.
/// Serial Hook delivery records provenance before enqueueing evidence in the sole reducer.
nonisolated final class CodexSurfaceLedger: SessionProcessLocating, @unchecked Sendable {
    let changes = MonitoringChangeBroadcast()
    private let source: CodexProcessSource
    private let lock = NSLock()
    private var owners: [String: Set<CodexExecution>] = [:]
    private var discovered: [CodexExecution] = []
    private var nextScan: Date?
    private var scanKnown = false
    private var turnOwners: [String: (turn: String, owner: CodexExecution)] = [:]
    private struct EndedBinding: Hashable { let thread: String; let owner: CodexExecution }
    private var ended: Set<EndedBinding> = []

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
    }

    func refresh(at now: Date) -> Reading {
        lock.lock()
        defer { lock.unlock() }
        if nextScan == nil || now >= nextScan! {
            let processes = source.localProcesses()
            scanKnown = processes != nil
            if let processes { discovered = processes }
            nextScan = now.addingTimeInterval(5)
        }
        owners = owners.mapValues { Set($0.filter(source.isAlive)) }.filter { !$0.value.isEmpty }
        turnOwners = turnOwners.filter { owners[$0.key] != nil }
        ended = ended.filter { source.isAlive($0.owner) }
        discovered = discovered.filter(source.isAlive)
        let anyCLI = !discovered.isEmpty || owners.values.contains { $0.contains { $0.surface == .cli } }
        return Reading(threadIDs: Set(owners.keys), cliIsOpen: anyCLI ? true : (scanKnown ? false : nil))
    }

    func deadline() -> Date? { lock.lock(); defer { lock.unlock() }; return nextScan }

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

    func hasDesktop(_ thread: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return owners[thread, default: []].contains { $0.surface == .desktop && source.isAlive($0) }
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
        discovered.removeAll(); nextScan = nil; scanKnown = false
    }
}

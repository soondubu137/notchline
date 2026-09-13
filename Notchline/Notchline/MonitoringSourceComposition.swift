import Foundation

/// Optional ownership contract for a source with work to start or stop. Pure
/// value readers need not implement it. One instance is owned once per runtime.
nonisolated protocol ManagedMonitoringSource: AnyObject, Sendable {
    nonisolated var sourceChanges: [AsyncStream<Void>] { get }
    func startMonitoring() async
    func stopMonitoring() async
}

extension ManagedMonitoringSource {
    nonisolated var sourceChanges: [AsyncStream<Void>] { [] }
    func startMonitoring() async {}
}

/// A timed reader updates its own held evidence here. The ordinary source
/// contracts then read that evidence in the runtime's documented order.
/// Returning nil parks this reader until its own edge or a fresh observation.
nonisolated protocol ScheduledMonitoringSource: ManagedMonitoringSource {
    func refresh(at now: Date) async throws -> Date?
}

/// Owns optional source work and consumes every deadline it publishes. A failed
/// read retains the source's last trustworthy values and backs off 5–60 s.
actor MonitoringSourceComposition {
    nonisolated let sources: [any ManagedMonitoringSource]
    private let clock: any MonitorClock
    nonisolated private let edges = MonitoringSourceEdges()
    private var readEdges: [ObjectIdentifier: Int] = [:]
    private var pending: [ObjectIdentifier: Task<Void, Never>] = [:]
    nonisolated private let completions = MonitoringChangeBroadcast()
    private var active = false
    private var generation = 0
    private var deadlines: [ObjectIdentifier: Date] = [:]
    private var failures: [ObjectIdentifier: Int] = [:]
    private var diagnostics: [ObjectIdentifier: String] = [:]

    init(_ candidates: [any Sendable], clock: any MonitorClock = SystemMonitorClock()) {
        self.clock = clock
        var seen: Set<ObjectIdentifier> = []
        sources = candidates.compactMap { $0 as? any ManagedMonitoringSource }
            .filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    nonisolated var changeEvents: [AsyncStream<Void>] {
        [completions.events()] + sources.flatMap { source in
            source.sourceChanges.map { edges.forward($0, for: ObjectIdentifier(source)) }
        }
    }

    func refresh(at now: Date) async {
        let token = generation
        if !active {
            active = true
            for source in sources {
                await source.startMonitoring()
                guard generation == token else {
                    if !active { await source.stopMonitoring() }
                    return
                }
            }
        }
        for source in sources {
            guard let scheduled = source as? any ScheduledMonitoringSource else { continue }
            let id = ObjectIdentifier(source)
            guard pending[id] == nil else { continue }
            // Failure backoff is also respected when unrelated sources emit edges.
            if failures[id] != nil, let due = deadlines[id], due > now { continue }
            let edge = edges.count(for: id)
            if failures[id] == nil, readEdges[id] == edge,
               deadlines[id].map({ $0 > now }) ?? true { continue }
            // The ordinary refresh reads held evidence immediately. A slow
            // optional source never holds lifecycle reduction or another source.
            pending[id] = Task { [weak self] in
                let result: Result<Date?, Error>
                do { result = .success(try await scheduled.refresh(at: now)) }
                catch { result = .failure(error) }
                await self?.completed(result, id: id, edge: edge, generation: token, startedAt: now)
            }
        }
    }

    private func completed(_ result: Result<Date?, Error>, id: ObjectIdentifier, edge: Int,
                           generation token: Int, startedAt now: Date) {
        guard active, generation == token else { return }
        pending[id] = nil
        let completedAt = max(now, clock.now())
        switch result {
        case let .success(next):
            deadlines[id] = next.map { $0 > completedAt ? $0 : completedAt.addingTimeInterval(5) }
            readEdges[id] = edge
            failures[id] = nil
            diagnostics[id] = nil
        case let .failure(error):
            let attempts = min((failures[id] ?? 0) + 1, 5)
            failures[id] = attempts
            deadlines[id] = completedAt.addingTimeInterval(min(5 * pow(2, Double(attempts - 1)), 60))
            diagnostics[id] = "A monitoring source could not be read: \(error.localizedDescription)"
        }
        // Counted source edges are consumed only up to the beginning of the
        // read. An edge during it stays due when this completion wakes the store.
        completions.signal()
    }

    func nextDeadline() -> Date? {
        guard active else { return nil }
        if sources.contains(where: {
            let id = ObjectIdentifier($0)
            return $0 is any ScheduledMonitoringSource && pending[id] == nil && failures[id] == nil
                && readEdges[id] != edges.count(for: id)
        }) { return .distantPast }
        return deadlines.filter { pending[$0.key] == nil }.values.min()
    }
    func diagnostic() -> String? {
        let messages = sources.compactMap { diagnostics[ObjectIdentifier($0)] }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    func stop() async {
        generation += 1
        active = false
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        readEdges.removeAll()
        deadlines.removeAll()
        failures.removeAll()
        diagnostics.removeAll()
        for source in sources.reversed() { await source.stopMonitoring() }
    }
}

/// Counts before yielding so an edge arriving during a read remains due even
/// if the store coalesces that edge into the refresh already in progress.
nonisolated private final class MonitoringSourceEdges: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [ObjectIdentifier: Int] = [:]
    func count(for id: ObjectIdentifier) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[id] ?? 0
    }
    private func advance(_ id: ObjectIdentifier) {
        lock.lock(); defer { lock.unlock() }
        counts[id, default: 0] += 1
    }
    func forward(_ stream: AsyncStream<Void>, for id: ObjectIdentifier) -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                for await _ in stream {
                    self.advance(id)
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

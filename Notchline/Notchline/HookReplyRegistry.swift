import Foundation
import os

/// The hook connections held open because a person is being asked something (ADR 0013).
/// - Held off the read queue, so a human decision parks nothing; a held Turn is stopped.
/// - `nc` half-closes, so a gone peer shows only as a failed write (`answer-in-notch.md` §8).
/// - After every drain, tickets no live wait names are closed (CR-030).
nonisolated final class HookReplyRegistry: @unchecked Sendable {
    /// Monotonic and never reused, so a stale ticket answers nothing.
    typealias Ticket = UInt64

    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "HookReplyRegistry"
    )

    private struct Connection {
        let descriptor: Int32
        /// Here, not on the wait, so these bytes live as long as the connection and never reach
        /// the view.
        let input: JSONValue?
        /// As the vocabulary declared at hold time; checked again at the write.
        let operations: AnswerOperations
        /// When the product's window runs out (``AgentHookVocabulary/answerWindowSeconds``); then
        /// the request says `Read`. An expired channel is not an ended wait.
        let expiresAt: Date?
    }

    /// Stamped on every handle, so another registry's ticket cannot address a connection here.
    let identity = UUID()

    private let lock = NSLock()
    private var held: [Ticket: Connection] = [:]
    /// Reconciliation may close only these: a connection is held before its evidence reaches the
    /// inbox, and a drain in that gap would close it (found 2026-09-12).
    private var reduced: Set<Ticket> = []
    private var nextTicket: Ticket = 1

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return held.count
    }

    /// Called on the listener's serial read queue; does nothing that could block it.
    func hold(
        _ descriptor: Int32,
        answering input: JSONValue?,
        permitting operations: AnswerOperations,
        expiringAt expiresAt: Date? = nil
    ) -> AnswerHandle {
        lock.lock()
        defer { lock.unlock() }
        let ticket = nextTicket
        nextTicket += 1
        held[ticket] = Connection(
            descriptor: descriptor, input: input, operations: operations, expiresAt: expiresAt
        )
        return AnswerHandle(ticket: ticket, issuer: identity)
    }

    private func ticket(of handle: AnswerHandle) -> Ticket? {
        handle.issuer == identity ? handle.ticket : nil
    }

    /// nil once no longer held, which is what a stale handle gets.
    func operations(for handle: AnswerHandle) -> AnswerOperations? {
        lock.lock()
        defer { lock.unlock() }
        return ticket(of: handle).flatMap { held[$0]?.operations }
    }

    /// The request keeps its words and stops offering a way to answer.
    func expire(at now: Date) -> Set<AnswerHandle> {
        lock.lock()
        let departing = held.filter { $0.value.expiresAt.map { $0 <= now } ?? false }
        for ticket in departing.keys {
            held.removeValue(forKey: ticket)
            reduced.remove(ticket)
        }
        lock.unlock()
        for connection in departing.values { close(connection.descriptor) }
        return Set(departing.keys.map { AnswerHandle(ticket: $0, issuer: identity) })
    }

    func nextExpiry() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return held.values.compactMap(\.expiresAt).min()
    }

    func input(for handle: AnswerHandle) -> JSONValue? {
        lock.lock()
        defer { lock.unlock() }
        return ticket(of: handle).flatMap { held[$0]?.input }
    }

    /// ``AnswerOutcome/sent`` means every byte was written, nothing more. `EPIPE` is ordinary;
    /// an unheld handle writes nothing; callers never retry. `SIGPIPE` is ignored
    /// (``BrokenPipeSignal``).
    @discardableResult
    func answer(_ handle: AnswerHandle, with body: Data) -> AnswerOutcome {
        lock.lock()
        guard let ticket = ticket(of: handle), let connection = held.removeValue(forKey: ticket) else {
            lock.unlock()
            return .expired(.notHeld)
        }
        reduced.remove(ticket)
        lock.unlock()
        defer { close(connection.descriptor) }
        return Self.write(body, to: connection.descriptor)
    }

    /// Closes without writing; the product carries on as if this app were not running.
    func release(_ handle: AnswerHandle) {
        guard let ticket = ticket(of: handle) else { return }
        lock.lock()
        let connection = held.removeValue(forKey: ticket)
        reduced.remove(ticket)
        lock.unlock()
        if let connection { close(connection.descriptor) }
    }

    /// The reducer has applied this connection's evidence; it is now the reducer's to judge.
    func markReduced(_ handle: AnswerHandle) {
        guard let ticket = ticket(of: handle) else { return }
        lock.lock()
        if held[ticket] != nil { reduced.insert(ticket) }
        lock.unlock()
    }

    /// Called after every drain, so any wait-clearing path releases its connection. Connections
    /// not yet reduced are skipped (``reduced``).
    func retain(only handles: Set<AnswerHandle>) {
        let tickets = Set(handles.compactMap(ticket(of:)))
        lock.lock()
        let departing = held.filter { reduced.contains($0.key) && !tickets.contains($0.key) }
        for ticket in departing.keys {
            held.removeValue(forKey: ticket)
            reduced.remove(ticket)
        }
        lock.unlock()
        for connection in departing.values { close(connection.descriptor) }
    }

    /// For evidence discarded before any drain took it (an observation reset emptying the inbox).
    func release(_ handles: some Sequence<AnswerHandle>) {
        for handle in handles { release(handle) }
    }

    func releaseAll() {
        lock.lock()
        let departing = held
        held.removeAll()
        reduced.removeAll()
        lock.unlock()
        for connection in departing.values { close(connection.descriptor) }
    }

    /// Loops past short writes and signals. Peer gone (`EPIPE`, `ECONNRESET`, `ENOTCONN`) before
    /// any byte is ``AnswerExpiry/peerGone``; anything else, or after a partial write, is
    /// ``AnswerOutcome/uncertain``: a retry could deliver a second decision.
    private static func write(_ body: Data, to descriptor: Int32) -> AnswerOutcome {
        var written = 0
        return body.withUnsafeBytes { raw -> AnswerOutcome in
            guard let base = raw.baseAddress else { return .sent }
            while written < raw.count {
                let count = Darwin.write(descriptor, base + written, raw.count - written)
                if count > 0 {
                    written += count
                    continue
                }
                if count < 0, errno == EINTR { continue }
                let failure = errno
                // Logged, not reported: the caller learns it from the outcome.
                Self.log.debug(
                    "an answer could not be written to a held hook connection (errno \(failure))"
                )
                let peerGone = failure == EPIPE || failure == ECONNRESET || failure == ENOTCONN
                return written == 0 && peerGone ? .expired(.peerGone) : .uncertain
            }
            return .sent
        }
    }
}

import Foundation
import os

/// The hook connections this app is holding open because a person is being
/// asked something.
///
/// One connection carries one payload and is normally closed the moment that
/// payload is handed over — the close *is* the acknowledgement, and it is the
/// only back-pressure in the transport ([ADR 0013](../../docs/adr/0013-claude-code-hooks-run-a-helper-not-a-port.md)).
/// On the one event per product that opens a wait for a person, the descriptor
/// is handed here instead and the read queue returns immediately. Holding it on
/// that queue would park every subsequent event from that product for the length
/// of a human decision, which is the one thing this must not do.
///
/// **The lost back-pressure is bounded and worth stating.** A held connection is
/// a Turn that is *stopped*, so there is nothing behind it to reorder: the
/// product is waiting on the tool it just asked about, and its next event cannot
/// be produced until this one is answered.
///
/// **A held connection cannot be watched for the peer going away.** The helper's
/// `nc` half-closes its write side as soon as its stdin reaches EOF — which is
/// what lets this app read to end-of-payload and still write back on the same
/// descriptor — so the read side is *already* at EOF and a read source would
/// fire at once on every held connection. There is therefore no "the hook
/// process disconnected" signal to subscribe to; a peer that has gone is
/// discovered when the answer is written and `write` fails, which is
/// [`answer-in-notch.md`](../../docs/answer-in-notch.md) §8's *not delivered*.
///
/// **Nothing here decides when to let go.** The reducer owns the waits, so the
/// registry is *reconciled* against them after every drain: whatever ticket no
/// live wait names is closed. That is one rule in one place rather than a
/// release beside each of the seven sites that already clear a wait — which is
/// exactly the shape CR-030 turned out to be, and the same reason the request
/// itself lives inside the wait rather than in a table beside it.
nonisolated final class HookReplyRegistry: @unchecked Sendable {
    /// Names one held connection, for as long as it is held.
    ///
    /// Monotonic and never reused, so a stale ticket answers nothing rather
    /// than answering the wrong request: `tool_use_id` would be the obvious key
    /// and is not available here, because a `PermissionRequest` carries none —
    /// the id it is filed under is borrowed from the open call, and that
    /// borrowing happens in the reducer, later, on another queue.
    typealias Ticket = UInt64

    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "HookReplyRegistry"
    )

    /// One held connection: the descriptor, and the input an answer may have to
    /// hand back.
    private struct Connection {
        let descriptor: Int32
        /// The `tool_input` this request arrived with.
        ///
        /// Kept **here** rather than on the request or the wait, and that is the
        /// point: answering a question means handing the tool back its own
        /// input with the answers merged in, so those bytes are needed exactly
        /// as long as the connection is held and by exactly the code that
        /// writes to it. On the wait they would travel into the snapshot and
        /// into the view, which parses no protocols; here their lifetime is the
        /// connection's, and `retain(only:)` frees them with it.
        let input: JSONValue?
        /// What an answer down this connection may do, as the vocabulary
        /// declared it when the connection was taken. Checked again at the
        /// write, so a surface offering something the channel never accepted
        /// is refused here before a byte is composed.
        let operations: AnswerOperations
        /// When the product's own window for an answer runs out.
        ///
        /// The helper waits `nc -w` seconds for this app and the product waits
        /// its registered timeout for the helper, the first inside the second
        /// by construction (``AgentHookVocabulary/answerWindowSeconds``). Past
        /// this instant the product has carried on without an answer, so the
        /// connection is let go and the request says `Read`, whatever the
        /// Turn is doing -- a channel expiring is not a wait ending.
        let expiresAt: Date?
    }

    /// Names this registry on every handle it mints, so a number another
    /// registry counted to cannot address a connection here.
    let identity = UUID()

    private let lock = NSLock()
    private var held: [Ticket: Connection] = [:]
    /// The held connections whose evidence the reducer has taken.
    ///
    /// **Reconciliation may close only these.** A connection is held on the
    /// listener's queue *before* its evidence is appended to the inbox, and a
    /// drain kicked by the event before it can run in that gap: it would find
    /// no live wait naming the new ticket and close a connection whose
    /// request the reducer has not seen yet -- the person then answers into a
    /// descriptor already gone and the row says *not sent*. Found on
    /// 2026-09-12 by a test delivering three events back to back. So a
    /// ticket becomes reconcilable only once ``markReduced(_:)`` has said its
    /// evidence was applied, accepted or not; until then only an explicit
    /// release or a shutdown lets it go.
    private var reduced: Set<Ticket> = []
    private var nextTicket: Ticket = 1

    /// How many connections are being held right now.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return held.count
    }

    /// Takes ownership of a connection and names it.
    ///
    /// Called on the listener's serial read queue and doing nothing that could
    /// block it: a dictionary insert under a lock nothing else holds for long.
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

    /// The ticket a handle names here, or nil for one minted elsewhere.
    private func ticket(of handle: AnswerHandle) -> Ticket? {
        handle.issuer == identity ? handle.ticket : nil
    }

    /// What one held connection accepts, while it is still held; nil once it
    /// is not, which is the answer a stale handle gets.
    func operations(for handle: AnswerHandle) -> AnswerOperations? {
        lock.lock()
        defer { lock.unlock() }
        return ticket(of: handle).flatMap { held[$0]?.operations }
    }

    /// The connections whose window has run out, let go: the request keeps
    /// its words and stops claiming a way to answer them.
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

    /// The earliest moment a held connection's window runs out, for the
    /// refresh that will withdraw it.
    func nextExpiry() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return held.values.compactMap(\.expiresAt).min()
    }

    /// The `tool_input` one held request arrived with, while it is still held.
    func input(for handle: AnswerHandle) -> JSONValue? {
        lock.lock()
        defer { lock.unlock() }
        return ticket(of: handle).flatMap { held[$0]?.input }
    }

    /// Writes one answer onto the connection and closes it.
    ///
    /// What comes back is what the write proved (``AnswerOutcome``): every
    /// byte written is ``AnswerOutcome/sent`` and no more -- a hook's stdout
    /// acknowledges nothing. A write to a descriptor whose peer has gone
    /// fails with `EPIPE`, which is an ordinary outcome and not a bug: the
    /// product may have killed the hook process because the person answered
    /// there instead. A handle this registry does not hold -- spent, minted
    /// elsewhere, or released when its wait cleared -- writes nothing. The
    /// caller says so on the row rather than retrying; there is nothing to
    /// retry against, and after a partial write nothing safe to retry with.
    ///
    /// `SIGPIPE` is ignored process-wide (``BrokenPipeSignal``), which is what
    /// turns that case into an error return instead of the app dying.
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

    /// Closes one connection without writing anything.
    ///
    /// The product then carries on exactly as it does when this app is not
    /// running, which is the fail-open the whole transport is built on.
    func release(_ handle: AnswerHandle) {
        guard let ticket = ticket(of: handle) else { return }
        lock.lock()
        let connection = held.removeValue(forKey: ticket)
        reduced.remove(ticket)
        lock.unlock()
        if let connection { close(connection.descriptor) }
    }

    /// The reducer has applied the evidence this connection arrived with, so
    /// the connection is now the reducer's to keep or let go.
    func markReduced(_ handle: AnswerHandle) {
        guard let ticket = ticket(of: handle) else { return }
        lock.lock()
        if held[ticket] != nil { reduced.insert(ticket) }
        lock.unlock()
    }

    /// Closes every reconcilable connection no live wait still names.
    ///
    /// The reconciliation described above: called after every drain with the
    /// tickets the reducer is still holding, so a wait cleared by any of its
    /// seven paths releases its connection without any of those paths knowing
    /// this type exists. A connection whose evidence no drain has taken yet is
    /// not judged -- see ``reduced``.
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

    /// Closes the connections of evidence that was discarded before any
    /// drain took it -- an observation reset emptying the inbox -- so they do
    /// not wait on a reconciliation that will never see them.
    func release(_ handles: some Sequence<AnswerHandle>) {
        for handle in handles { release(handle) }
    }

    /// Closes everything, for a listener shutting down.
    func releaseAll() {
        lock.lock()
        let departing = held
        held.removeAll()
        reduced.removeAll()
        lock.unlock()
        for connection in departing.values { close(connection.descriptor) }
    }

    /// Writes the whole body, looping past short writes and signals, and
    /// says what the write proved.
    ///
    /// A peer that has gone (`EPIPE`, `ECONNRESET`, `ENOTCONN`) before any
    /// byte was taken is ``AnswerExpiry/peerGone``: nothing reached it and
    /// nothing will. Any other failure, or one after part of the body was
    /// taken, is ``AnswerOutcome/uncertain``: the product may hold half a
    /// decision, and a retry could hand it a second one.
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
                // `EPIPE` is the ordinary shape of "the product stopped
                // waiting", so this is logged rather than reported: the caller
                // already learns it from the outcome and is the only place
                // that can say anything useful to the person who typed it.
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

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
    }

    private let lock = NSLock()
    private var held: [Ticket: Connection] = [:]
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
    func hold(_ descriptor: Int32, answering input: JSONValue?) -> Ticket {
        lock.lock()
        defer { lock.unlock() }
        let ticket = nextTicket
        nextTicket += 1
        held[ticket] = Connection(descriptor: descriptor, input: input)
        return ticket
    }

    /// The `tool_input` one held request arrived with, while it is still held.
    func input(for ticket: Ticket) -> JSONValue? {
        lock.lock()
        defer { lock.unlock() }
        return held[ticket]?.input
    }

    /// Writes one answer onto the connection and closes it.
    ///
    /// Returns whether the whole answer reached the peer. `false` is an ordinary
    /// outcome and not a bug: the product may have killed the hook process
    /// because the person answered there instead, and a write to a descriptor
    /// whose peer has gone fails with `EPIPE`. The caller says so on the row
    /// rather than retrying — there is nothing to retry against.
    ///
    /// `SIGPIPE` is ignored process-wide (``BrokenPipeSignal``), which is what
    /// turns that case into an error return instead of the app dying.
    @discardableResult
    func answer(_ ticket: Ticket, with body: Data) -> Bool {
        lock.lock()
        guard let connection = held.removeValue(forKey: ticket) else {
            lock.unlock()
            return false
        }
        lock.unlock()
        defer { close(connection.descriptor) }
        return Self.write(body, to: connection.descriptor)
    }

    /// Closes one connection without writing anything.
    ///
    /// The product then carries on exactly as it does when this app is not
    /// running, which is the fail-open the whole transport is built on.
    func release(_ ticket: Ticket) {
        lock.lock()
        let connection = held.removeValue(forKey: ticket)
        lock.unlock()
        if let connection { close(connection.descriptor) }
    }

    /// Closes every connection no live wait still names.
    ///
    /// The reconciliation described above: called after every drain with the
    /// tickets the reducer is still holding, so a wait cleared by any of its
    /// seven paths releases its connection without any of those paths knowing
    /// this type exists.
    func retain(only tickets: Set<Ticket>) {
        lock.lock()
        let departing = held.filter { !tickets.contains($0.key) }
        for ticket in departing.keys { held.removeValue(forKey: ticket) }
        lock.unlock()
        for connection in departing.values { close(connection.descriptor) }
    }

    /// Closes everything, for a listener shutting down.
    func releaseAll() {
        retain(only: [])
    }

    /// Writes the whole body, looping past short writes and signals.
    private static func write(_ body: Data, to descriptor: Int32) -> Bool {
        var written = 0
        return body.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            while written < raw.count {
                let count = Darwin.write(descriptor, base + written, raw.count - written)
                if count > 0 {
                    written += count
                    continue
                }
                if count < 0, errno == EINTR { continue }
                // `EPIPE` is the ordinary shape of "the product stopped
                // waiting", so this is logged rather than reported: the caller
                // already learns it from the return value and is the only place
                // that can say anything useful to the person who typed it.
                Self.log.debug(
                    "an answer could not be written to a held hook connection (errno \(errno))"
                )
                return false
            }
            return true
        }
    }
}

import Foundation
import os

/// Receives one product's hook payloads over a Unix domain socket and hands
/// them, in arrival order, to the store.
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
/// **Both products arrive here now.** The Codex side used to write one JSON
/// file per event into a queue directory, because its helper was a script that
/// could not talk to a running process — and this listener then wrote Claude
/// Code's payloads to disk in the same shape, so that a directory-reading
/// reducer could read them back. Removing the queue removed that reader's last
/// client. Same store, same reducer, one transport each.
///
/// The helper is ``AgentHookHelper/script(socketPath:)``: `nc -U` and an
/// unconditional `exit 0`. One connection carries one payload and is closed by
/// the writer, so the frame is simply "read to EOF" — there is no request line,
/// no header, and no token, because the socket is `0600` in this user's own
/// directory and the filesystem answers the question a bearer token used to.
///
/// **Arrival is stamped here.** Claude Code's hook payloads carry no timestamp
/// of any kind — measured 2026-08-16 — and the Codex helper no longer writes
/// one, because a payload that reaches this process arrived a moment ago by
/// construction. The reducer's ordering rules need a moment, so it is taken at
/// the instant the payload lands.
///
/// **Order is preserved by the read queue, not promised by the transport.**
/// Connections are accepted in arrival order and handed to one serial queue, so
/// ``deliver`` runs in the order the payloads landed. That is worth stating
/// because the registration is deliberately synchronous: Claude Code's
/// `command` schema does have an `async` key, unlike its `http` one, and using
/// it was measured to reorder a `PreToolUse` against its own `PostToolUse` and
/// to lose `Stop` entirely under `-p`, where the process exits before a
/// backgrounded hook finishes. Paying 6.3 ms on the session buys both back.
nonisolated final class AgentHookListener: @unchecked Sendable {
    private static let log = Logger(
        subsystem: "com.yinfenglu.CodexInNotch",
        category: "AgentHookListener"
    )

    /// How much of one connection is read before it is cut off.
    ///
    /// It bounds the read queue's time per event, and nothing else — in
    /// particular it is not a bound on what the reducer can be told. Field
    /// selection happens in ``HookPayloadDistiller`` on the way into the store,
    /// so the fields that arrived whole before the cut still land: an event is
    /// no longer lost because the tool result attached to it was large
    /// (CR-030).
    ///
    /// Sixteen mebibytes because the point is to stop a client that has stopped
    /// making sense, not to have an opinion about payload sizes. What it has to
    /// stay inside is the helper's own `nc -w 1`, which is in turn inside the
    /// registration's `timeout: 3`; measured on a Release build, a payload at
    /// the ceiling costs 55–75 ms from the client's first write to the
    /// hand-off, so the innermost of the three bounds is still the one that
    /// fires first.
    static let maximumBodyBytes = 16 << 20

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

    private let clock: any MonitorClock
    private let fileManager: FileManager
    /// Where one payload goes, called on ``readQueue`` in arrival order.
    private let deliver: @Sendable (Data, Date) -> Void

    /// Listening state, under a lock rather than a queue.
    ///
    /// The accept handler runs on one GCD queue, payloads are read on another,
    /// and the shared state is three fields.
    private let socketLock = NSLock()
    private var listeningDescriptor: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var boundSocketURL: URL?
    /// Which file the bound socket actually *is*, rather than what it is
    /// called.
    ///
    /// A path is a name, and a name can come to mean something else while this
    /// process holds the thing it used to mean. That is not hypothetical: a
    /// second copy of this app binds the same path, and binding starts by
    /// unlinking whatever is there -- so the first copy goes on holding a
    /// perfectly good listening socket that no helper can reach any more, and
    /// says nothing, because it is still listening. Recording the node is what
    /// lets ``start(socketURL:)`` tell "already bound" from "bound to a name
    /// somebody else has taken", and ``stop()`` tell its own socket from the
    /// one that replaced it.
    private var boundSocketNode: SocketNode?

    private let acceptQueue = DispatchQueue(
        label: "com.yinfenglu.CodexInNotch.hook-listener.accept"
    )
    /// Serial on purpose: it is what makes ``deliver`` see payloads in the
    /// order they arrived.
    private let readQueue = DispatchQueue(
        label: "com.yinfenglu.CodexInNotch.hook-listener.read"
    )

    init(
        clock: any MonitorClock = SystemMonitorClock(),
        fileManager: FileManager = .default,
        deliver: @escaping @Sendable (Data, Date) -> Void
    ) {
        self.clock = clock
        self.fileManager = fileManager
        self.deliver = deliver
    }

    /// One file, identified the way the filesystem identifies it.
    private struct SocketNode: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    deinit {
        stop()
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
    /// consequence — the helper the registration names has nothing to hand its
    /// payloads to.
    /// - Note: **Bound is checked against the file, not against the name.** It
    ///   used to be enough that this listener held a descriptor and remembered
    ///   the same path, which is true of a listener whose socket somebody else
    ///   has since replaced -- and that listener is deaf, permanently, while
    ///   reporting itself healthy. The caller re-binds on every refresh
    ///   precisely so that a support folder emptied under the running app is
    ///   repaired; until now that promise covered the helper and not the socket
    ///   the helper writes to.
    @discardableResult
    func start(socketURL: URL) -> Bool {
        socketLock.lock()
        let alreadyBound = listeningDescriptor >= 0
            && boundSocketURL == socketURL
            && boundSocketNode == Self.node(at: socketURL.path)
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
        // Somebody is already answering here. That is one case and one case
        // only -- a second copy of this app, launched beside the one already
        // running -- and taking the socket from it is how this app used to
        // leave *both* copies deaf: the first goes on holding an unlinked
        // socket no helper can reach, and this one inherits a registration it
        // will lose again the moment the first is asked to re-bind. Standing
        // down says so instead. A crashed copy leaves a socket nothing answers
        // on, which is refused rather than accepted, so this cannot mistake
        // litter for a live listener.
        if Self.isBeingServed(at: socketURL) {
            Self.log.error(
                "another copy of this app is already receiving hook payloads here; not taking the socket from it"
            )
            return false
        }

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
        // Read after `bind`, so it names the socket this descriptor is: a
        // successful bind is what created the file.
        boundSocketNode = Self.node(at: socketURL.path)
        socketLock.unlock()

        source.resume()
        return true
    }

    /// Stops accepting, and takes down the socket **this** listener put there.
    ///
    /// The qualification is the whole of it. Removing whatever happens to be at
    /// the path is how one copy of this app used to leave another deaf on its
    /// way out: the departing copy unlinked a socket the copy still running had
    /// bound, and that copy never noticed, because it was still holding a
    /// perfectly good descriptor.
    func stop() {
        socketLock.lock()
        let source = acceptSource
        let url = boundSocketURL
        let node = boundSocketNode
        acceptSource = nil
        listeningDescriptor = -1
        boundSocketURL = nil
        boundSocketNode = nil
        socketLock.unlock()

        source?.cancel()
        if let url, Self.node(at: url.path) == node {
            unlink(url.path)
        }
    }

    /// Which file this path names, or nil when it names none.
    private static func node(at path: String) -> SocketNode? {
        var attributes = stat()
        guard stat(path, &attributes) == 0 else { return nil }
        return SocketNode(device: attributes.st_dev, inode: attributes.st_ino)
    }

    /// Whether something is accepting connections on this path right now.
    ///
    /// A connect and an immediate close, which is what the helper does anyway
    /// -- the listener on the other end reads an empty body and reports it, and
    /// that report is a truer thing to say than nothing at all. `ENOENT` and
    /// `ECONNREFUSED` both answer no: a path with no file, and a socket file
    /// whose owner has gone, are the two ordinary shapes of "free".
    private static func isBeingServed(at socketURL: URL) -> Bool {
        let pathBytes = Array(socketURL.path.utf8)
        guard pathBytes.count < MemoryLayout<sockaddr_un>.size
            - MemoryLayout<UInt8>.size * 2 else {
            return false
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }
        address.sun_len = UInt8(
            MemoryLayout<sockaddr_un>.size - MemoryLayout.size(ofValue: address.sun_path)
                + pathBytes.count
        )
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        } == 0
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

    /// Reads one payload and hands it over.
    ///
    /// One connection is one payload: the helper writes what it was given on
    /// stdin and closes, so the end of the message is the end of the stream and
    /// there is no framing to get wrong.
    ///
    /// **The close is the acknowledgement**, so it happens after the hand-off
    /// rather than before it. Every registration is synchronous: the agent's
    /// `nc` waits for this end to close, and a talking turn waits three times a
    /// second. Nothing this app does may sit on a user's session, and there is
    /// no configuration doing that for us — what keeps it off the critical path
    /// is that the work between the read and the close is bounded to one pass
    /// selecting the fields, one decode of the few hundred bytes that leaves,
    /// and for a delta a scan that stops at the head's cap. Measured at 2.06 ms
    /// per event, indifferent to a 60 KB delta; selection moved that by 3 µs
    /// for an ordinary payload and took 4.7× off a payload near a megabyte,
    /// which no longer has its tool result decoded (CR-030).
    ///
    /// Closing first would be a few microseconds cheaper and would cost the
    /// only back-pressure in the path: two payloads from one session could then
    /// be in flight at once, and the order the read queue exists to preserve
    /// would be decided by the scheduler.
    private func receivePayload(on descriptor: Int32) {
        defer { close(descriptor) }

        var body = Data()
        readBody(on: descriptor, into: &body)
        // Handed over whatever it turned out to be, including nothing at all.
        // A body that reached the ceiling used to be dropped here, on the
        // reasoning that half a payload decodes to nothing useful -- true while
        // the whole payload had to decode, and no longer so now that selection
        // takes whole fields off the front (CR-030). An empty body used to be
        // dropped here too, and that left this end with two silent exits: only
        // this user's own processes can reach a `0600` socket in a directory
        // this app owns, so a connection that delivers nothing is the helper
        // failing to deliver, which is exactly the kind of thing CR-029 says
        // must stop being silent. There is one place that can say so -- the
        // store -- so everything that arrives goes there and it decides.
        deliver(body, clock.now())
    }

    private func readBody(on descriptor: Int32, into payload: inout Data) {
        // Darwin hands `accept` a descriptor that inherits the listening
        // socket's file status flags, and the listening socket is `O_NONBLOCK`
        // so the accept handler can drain its backlog rather than park on the
        // next connection. Inherited here that is silent data loss: a client
        // that has connected but whose write has not landed yet makes `read`
        // fail with `EAGAIN`, which the loop below cannot tell from the end of
        // a payload, so the event is dropped for good instead of waited for
        // (CC-023). Clearing the flag is what makes the timeout below the thing
        // that bounds this.
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

        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
        while payload.count < Self.maximumBodyBytes {
            let wanted = min(buffer.count, Self.maximumBodyBytes - payload.count)
            let readCount = read(descriptor, &buffer, wanted)
            if readCount > 0 {
                payload.append(contentsOf: buffer[0 ..< readCount])
                continue
            }
            // A signal delivered mid-read is not the end of the payload, and
            // treating it as one would drop an event for a reason that has
            // nothing to do with the client. Every other answer -- zero for the
            // writer's close, and the receive timeout's `EAGAIN` for a client
            // that stopped making progress -- ends the read; what arrived is
            // then whatever it is, and selection decides what survives.
            if readCount < 0, errno == EINTR { continue }
            break
        }
    }
}

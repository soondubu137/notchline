import Foundation
import os

/// Receives one product's hook payloads over a Unix domain socket and hands them to the store
/// in arrival order.
///
/// - A `0600` socket in this app's directory, not a localhost port: an unowned port prints
///   `ECONNREFUSED` per event while the app is closed and can be taken by any local process
///   (CC-021, CC-014). No token needed.
/// - One connection carries one payload, framed by EOF. The helper
///   (``AgentHookHelper/script(socketPath:answerWindowSeconds:)``: `nc -U`, always `exit 0`)
///   half-closes, so a held connection can carry the answer back (``Disposition/held``).
/// - Payloads carry no timestamp (measured 2026-08-16), so arrival is stamped here.
/// - Order comes from the serial read queue. Hooks stay synchronous: `async` reordered
///   `PreToolUse`/`PostToolUse` and lost `Stop` under `-p`. Costs 6.3 ms per event.
nonisolated final class AgentHookListener: @unchecked Sendable {
    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "AgentHookListener"
    )

    /// How much of one connection is read before it is cut off. It bounds only the read queue's
    /// time per event: ``HookPayloadDistiller`` selects fields, so fields before the cut still land
    /// (CR-030). Must stay inside the helper's `nc -w 1`, itself inside `timeout: 3`; a payload at
    /// the ceiling costs 55–75 ms to the hand-off (Release).
    static let maximumBodyBytes = 16 << 20

    /// How long one connection may take to deliver its payload; well inside the helper's
    /// `nc -w 1` and the registration's `timeout: 3`. Only bounds a blocking descriptor
    /// (``receivePayload(on:)``).
    static let receiveTimeoutMicroseconds: Int32 = 250_000

    /// What becomes of a connection once its payload has been handed over.
    nonisolated enum Disposition: Sendable {
        /// Close it, which is the acknowledgement. Every lifecycle event.
        case close
        /// Somebody else has taken the descriptor and will close it: the answer to a wait for a
        /// person travels back on this connection. See ``HookReplyRegistry``.
        case held
    }

    private let clock: any MonitorClock
    private let fileManager: FileManager
    /// Where one payload goes, called on ``readQueue`` in arrival order. Gets the descriptor too:
    /// whether an answer travels back depends on the payload, which this type does not read.
    private let deliver: @Sendable (Data, Date, Int32) -> Disposition

    /// Listening state, under a lock: accept and read run on separate queues.
    private let socketLock = NSLock()
    private var listeningDescriptor: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var boundSocketURL: URL?
    /// The bound socket's file identity, not its name. A second copy binding the same path unlinks
    /// ours and leaves this one listening unreachably; the node lets ``start(socketURL:)`` and
    /// ``stop()`` tell this listener's socket from a replacement.
    private var boundSocketNode: SocketNode?

    private let acceptQueue = DispatchQueue(
        label: "com.yinfenglu.Notchline.hook-listener.accept"
    )
    /// Serial: it is what makes ``deliver`` see payloads in arrival order.
    private let readQueue = DispatchQueue(
        label: "com.yinfenglu.Notchline.hook-listener.read"
    )

    init(
        clock: any MonitorClock = SystemMonitorClock(),
        fileManager: FileManager = .default,
        deliver: @escaping @Sendable (Data, Date, Int32) -> Disposition
    ) {
        self.clock = clock
        self.fileManager = fileManager
        self.deliver = deliver
    }

    private struct SocketNode: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    deinit {
        stop()
    }

    var socketURL: URL? {
        socketLock.lock()
        defer { socketLock.unlock() }
        return boundSocketURL
    }

    /// Binds the socket and starts accepting. Returns `false` rather than throwing: the caller can
    /// only report it in the settings card.
    /// - Note: Bound is checked against the file, not the name: a listener whose socket was
    ///   replaced is deaf while reporting healthy. The caller re-binds on every refresh to repair
    ///   an emptied support folder.
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
        // `sun_path` is a fixed 104-byte field; overflowing it would fail inside `bind` with an
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
        // A second copy of this app is already listening. Taking its socket leaves both copies deaf,
        // so stand down. A crashed copy's socket refuses connections, so it is not mistaken for one.
        if Self.isBeingServed(at: socketURL) {
            Self.log.error(
                "another copy of this app is already receiving hook payloads here; not taking the socket from it"
            )
            return false
        }

        // A socket left by a crash blocks `bind`; it is ours, in a directory this app owns.
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

        // Only this user's processes may hand events to this app; this is the whole access control.
        chmod(socketURL.path, 0o600)

        guard listen(descriptor, 64) == 0 else {
            close(descriptor)
            unlink(socketURL.path)
            return false
        }

        // Non-blocking so the accept handler drains the backlog rather than parking on a connection.
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
        // Read after `bind`: a successful bind created the file, so this names this descriptor's socket.
        boundSocketNode = Self.node(at: socketURL.path)
        socketLock.unlock()

        source.resume()
        return true
    }

    /// Stops accepting, and removes the socket only if it is still the one this listener bound:
    /// unlinking whatever is at the path deafens another running copy.
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

    private static func node(at path: String) -> SocketNode? {
        var attributes = stat()
        guard stat(path, &attributes) == 0 else { return nil }
        return SocketNode(device: attributes.st_dev, inode: attributes.st_ino)
    }

    /// Whether something accepts connections on this path now, by connecting and closing (the
    /// listener reports the empty body). `ENOENT` and `ECONNREFUSED` both mean free.
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

    /// Reads one payload, to EOF, and hands it over.
    ///
    /// - The close is the acknowledgement, so it follows the hand-off: `nc` waits for it, and it is
    ///   the only back-pressure keeping one session's payloads in order. The work before it is
    ///   bounded; measured 2.06 ms per event, indifferent to a 60 KB delta (CR-030).
    /// - A payload a person has to answer hands the descriptor to ``HookReplyRegistry`` and returns
    ///   without closing; the wait never runs on this serial queue.
    private func receivePayload(on descriptor: Int32) {
        var body = Data()
        readBody(on: descriptor, into: &body)
        // Hand over everything, including a truncated or empty body: selection keeps whole fields
        // (CR-030), and the store reports a helper that failed to deliver (CR-029).
        if deliver(body, clock.now(), descriptor) == .close {
            close(descriptor)
        }
    }

    private func readBody(on descriptor: Int32, into payload: inout Data) {
        // An accepted descriptor inherits the listening socket's `O_NONBLOCK`; a client whose write
        // has not landed then fails `read` with `EAGAIN` and the event is dropped (CC-023). Clearing
        // it lets the receive timeout bound the read.
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
            // `EINTR` is not the end of the payload. Zero (writer closed) or the timeout's `EAGAIN` ends
            // the read.
            if readCount < 0, errno == EINTR { continue }
            break
        }
    }
}

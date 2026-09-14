import Darwin
import Dispatch
import Foundation

/// Newline framing, connection lifetimes and boundary order live on this
/// serial queue. Only typed evidence crosses into the reducer actor.
nonisolated final class TraeBridgeTransport: TraeReadReporting, @unchecked Sendable {
    private final class Peer {
        var identity = UUID()
        let fd: Int32
        let reader: DispatchSourceRead
        var bytes = Data()
        var hello = false
        var healthy = false
        var lastRead = Date()
        init(fd: Int32, reader: DispatchSourceRead) { self.fd = fd; self.reader = reader }
    }
    let repository: MonitoringRepository
    let changes = MonitoringChangeBroadcast()
    private let queue = DispatchQueue(label: "com.yinfenglu.notchline.trae")
    private let directory: URL
    private var peers: [String: Peer] = [:]
    private var boundary = TraeEvidenceBoundary()
    private var timer: DispatchSourceTimer?
    private var watcher: DispatchSourceFileSystemObject?
    private var epoch: MonitoringEpoch?
    private var lastDiagnostic: String?
    private var active = false
    private var failedPaths: Set<String> = []

    init(directory: URL, repository: MonitoringRepository) {
        self.directory = directory; self.repository = repository
    }
    func start() {
        queue.async { [self] in
            guard !active else { return }
            active = true; epoch = repository.observationEpoch
            discover()
            let fd = Darwin.open(directory.path, O_EVTONLY | O_CLOEXEC)
            if fd >= 0 {
                let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
                source.setEventHandler { [weak self] in self?.discover() }
                source.setCancelHandler { Darwin.close(fd) }
                watcher = source; source.resume()
            }
            let clock = DispatchSource.makeTimerSource(queue: queue)
            clock.schedule(deadline: .now() + 10, repeating: 10, leeway: .seconds(1))
            clock.setEventHandler { [weak self] in self?.discover() }
            timer = clock; clock.resume()
        }
    }
    func stop() {
        queue.async { [self] in
            active = false; epoch = nil; timer?.cancel(); timer = nil; watcher?.cancel(); watcher = nil
            for path in Array(peers.keys) { close(path, diagnostic: nil) }
            boundary = TraeEvidenceBoundary(); lastDiagnostic = nil; failedPaths = []
        }
    }
    func reading() async -> (Bool, String?) {
        await withCheckedContinuation { c in queue.async { [self] in
            c.resume(returning: (peers.values.contains(where: \.healthy), lastDiagnostic))
        } }
    }
    func connectionFacts() async -> (healthy: Int, failed: Int, diagnostic: String?) {
        await withCheckedContinuation { c in queue.async { [self] in
            failedPaths = failedPaths.filter { FileManager.default.fileExists(atPath: $0) }
            if failedPaths.isEmpty { lastDiagnostic = nil }
            c.resume(returning: (peers.values.filter(\.healthy).count, failedPaths.count, lastDiagnostic))
        } }
    }
    func content() async -> [String: TraeDisplayedTurn] {
        await withCheckedContinuation { c in queue.async { [self] in c.resume(returning: boundary.current.filter { entry in
            boundary.peer(for: entry.key).map { peers[$0]?.healthy == true } ?? false
        }) } }
    }
    func route(for threadID: String) async -> String? {
        await withCheckedContinuation { c in queue.async { [self] in
            let path = boundary.peer(for: threadID)
            c.resume(returning: path.flatMap { peers[$0]?.healthy == true ? $0 : nil })
        } }
    }
    func readCompletions() async -> [TraeReadProof] {
        let paths: [String: UUID] = await withCheckedContinuation { c in queue.async { [self] in
            c.resume(returning: peers.filter { $0.value.healthy }.mapValues(\.identity))
        } }
        let requestedAt = Date()
        let readings = await withTaskGroup(of: (String, TraeReadProof?).self) { group in
            for path in paths.keys {
                group.addTask { await Task.detached { (path, TraeReadQuery.read(path: path)) }.value }
            }
            var result: [String: TraeReadProof] = [:]
            for await (path, proof) in group { if let proof { result[path] = proof } }
            return result
        }
        return await withCheckedContinuation { c in queue.async { [self] in
            let now = Date()
            c.resume(returning: readings.compactMap { path, proof in
                guard active, let peer = peers[path], peer.healthy, peer.identity == paths[path],
                      let current = boundary.current[proof.threadID],
                      proof.matches(current, requestedAt: requestedAt, receivedAt: now) else { return nil }
                // Any healthy window may prove reading; this never transfers lifecycle ownership.
                return proof
            })
        } }
    }
    private func discover() {
        guard active else { return }
        for (path, peer) in peers where Date().timeIntervalSince(peer.lastRead) > 35 {
            close(path, diagnostic: TraeBridgeError.unavailable.localizedDescription)
        }
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files.prefix(64) where file.pathExtension == "sock" && peers[file.path] == nil {
            if peers.count >= 16 { break }
            connect(file)
        }
    }
    private func connect(_ file: URL) {
        var info = stat()
        guard lstat(file.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { return }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        // A local Unix socket connect, with a bounded send timeout; no DNS/network.
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        guard Self.connect(fd, path: file.path) == 0 else { Darwin.close(fd); return }
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { Darwin.close(fd); return }
        guard let body = try? JSONSerialization.data(withJSONObject: ["op":"watch", "schema":1,
            "retainedThreadIDs":boundary.observedThreadIDs]) else { Darwin.close(fd); return }
        let request = body + Data([10])
        let sent = request.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard sent == request.count else { Darwin.close(fd); return }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let peer = Peer(fd: fd, reader: reader)
        peers[file.path] = peer
        reader.setEventHandler { [weak self] in self?.read(file.path) }
        reader.setCancelHandler { Darwin.close(fd) }
        reader.resume()
    }
    private func read(_ path: String) {
        guard let peer = peers[path], let epoch else { return }
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(peer.fd, &buffer, buffer.count)
            if count == 0 { close(path, diagnostic: TraeBridgeError.unavailable.localizedDescription); return }
            if count < 0 {
                if errno != EAGAIN && errno != EWOULDBLOCK { close(path, diagnostic: TraeBridgeError.unavailable.localizedDescription) }
                return
            }
            peer.bytes.append(contentsOf: buffer.prefix(count))
            if peer.bytes.count > 2 * 1_048_576 { close(path, diagnostic: TraeBridgeError.schema.localizedDescription); return }
            while let newline = peer.bytes.firstIndex(of: 10) {
                let line = Data(peer.bytes[..<newline]); peer.bytes.removeSubrange(...newline)
                do {
                    guard line.count <= 1_048_576 else { throw TraeBridgeError.schema }
                    let frame = try JSONDecoder().decode(TraeFrame.self, from: line)
                    peer.lastRead = Date()
                    switch frame.type {
                    case "hello":
                        guard !peer.hello, frame.schema == 1, frame.version == TraeInstallation.traeVersion,
                              frame.bridgeVersion == TraeInstallation.companionVersion,
                              frame.pid.map(String.init) == URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent else { throw TraeBridgeError.version }
                        peer.hello = true
                    case "snapshot":
                        guard peer.hello else { throw TraeBridgeError.schema }
                        try boundary.consume(frame, peer: path, repository: repository, epoch: epoch)
                        if frame.baseline == true { peer.identity = UUID() }
                        let wasHealthy = peer.healthy; peer.healthy = true; failedPaths.remove(path); if failedPaths.isEmpty { lastDiagnostic = nil }
                        if !wasHealthy || !(frame.rows?.isEmpty ?? true) || !(frame.excluded?.isEmpty ?? true) { changes.signal() }
                    case "heartbeat":
                        guard peer.hello, frame.schema == 1, frame.version == TraeInstallation.traeVersion else { throw TraeBridgeError.schema }
                    case "unavailable":
                        peer.identity = UUID()
                        boundary.lost(peer: path)
                        if peer.healthy { peer.healthy = false; changes.signal() }
                        failedPaths.insert(path)
                        lastDiagnostic = "Trae’s companion reported that observation is unavailable."
                    default: throw TraeBridgeError.schema
                    }
                } catch { close(path, diagnostic: error.localizedDescription); return }
            }
        }
    }
    private func close(_ path: String, diagnostic: String?) {
        guard let peer = peers.removeValue(forKey: path) else { return }
        peer.reader.cancel(); boundary.lost(peer: path)
        if let diagnostic { failedPaths.insert(path); lastDiagnostic = diagnostic }
        if failedPaths.isEmpty { lastDiagnostic = nil }
        changes.signal()
    }
    static func connect(_ fd: Int32, path: String) -> Int32 {
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return -1 }
        withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        } }
    }
}

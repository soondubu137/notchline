import Darwin
import Dispatch
import Foundation

/// Carries a Hook event's preview text from the helper into this process's
/// memory, and nowhere else.
///
/// The helper used to put `prompt` and `last_assistant_message` straight into
/// the event file, which contradicted the product's absolute promise that no
/// prompt or answer is persisted. Persisting them also bought nothing: an event
/// written while this app is not running is discarded on the next launch
/// anyway -- see ``HookEventRepository``'s live cutoff -- so the queue's
/// durability only ever applied to text the reducer would refuse to read.
///
/// So the queue keeps carrying identity and lifecycle, which genuinely have to
/// survive the gap between the hook firing and the next refresh, and the text
/// comes over this socket instead. If nothing is listening the helper drops it,
/// which is the correct degradation: a missing preview rather than a stale one.
///
/// `@unchecked Sendable` with an explicit lock, matching
/// ``DirectoryChangeWatcher``: the accept handler runs on a GCD queue while the
/// reducer reads from an actor, and the shared state is a small dictionary.
/// Making this an actor would put an `await` inside the reducer's synchronous
/// event walk for no benefit.
final class HookPreviewChannel: @unchecked Sendable {
    /// One event's preview text, as the helper observed it.
    nonisolated struct Preview: Sendable, Equatable {
        let prompt: String?
        let assistantMessage: String?

        nonisolated init(prompt: String?, assistantMessage: String?) {
            self.prompt = prompt
            self.assistantMessage = assistantMessage
        }

        nonisolated var isEmpty: Bool {
            prompt == nil && assistantMessage == nil
        }
    }

    private struct Message: Decodable {
        let eventID: String
        let prompt: String?
        let lastAssistantMessage: String?

        enum CodingKeys: String, CodingKey {
            case eventID = "event_id"
            case prompt
            case lastAssistantMessage = "last_assistant_message"
        }
    }

    /// Most a single connection may send.
    ///
    /// The helper sends two fields it has already truncated to 240 characters
    /// each, so this is orders of magnitude above any legitimate message and
    /// exists only so a stuck or hostile writer cannot grow this process.
    nonisolated private static let maximumMessageByteCount = 8 * 1_024

    /// How long a connection may take to deliver its line.
    ///
    /// The helper connects, writes once and closes, so anything slower is a
    /// client that has stopped making progress. It must be well inside the
    /// hook's own 3s budget on the other side.
    nonisolated private static let receiveTimeoutMicroseconds: Int32 = 250_000

    /// How many unclaimed previews are held before the oldest is dropped.
    ///
    /// A preview is normally claimed within one refresh. Entries only pile up
    /// when the file that would claim them never arrives -- a quarantined
    /// event, or a helper that sent text and then failed to write its file --
    /// so this is a leak stop, not a working set.
    nonisolated private let maximumRetainedPreviews: Int

    nonisolated private let socketURL: URL
    private let lock = NSLock()
    nonisolated private let acceptQueue = DispatchQueue(
        label: "com.yinfenglu.codex-in-notch.preview-channel.accept"
    )
    nonisolated private let readQueue = DispatchQueue(
        label: "com.yinfenglu.codex-in-notch.preview-channel.read"
    )

    nonisolated(unsafe) private var listeningDescriptor: Int32 = -1
    nonisolated(unsafe) private var acceptSource: DispatchSourceRead?
    nonisolated(unsafe) private var previewsByEventID: [String: Preview] = [:]
    nonisolated(unsafe) private var claimOrder: [String] = []
    nonisolated(unsafe) private var acceptsText = true
    nonisolated(unsafe) private var listenDiagnostic: String?

    nonisolated init(socketURL: URL, maximumRetainedPreviews: Int = 256) {
        self.socketURL = socketURL
        self.maximumRetainedPreviews = max(1, maximumRetainedPreviews)
    }

    deinit {
        stop()
    }

    /// Binds and starts accepting. Safe to call when the directory does not
    /// exist yet; the caller retries after installing.
    @discardableResult
    nonisolated func start() -> Bool {
        lock.lock()
        let alreadyListening = listeningDescriptor >= 0
        lock.unlock()
        if alreadyListening { return true }

        let pathBytes = Array(socketURL.path.utf8)
        // `sun_path` is a fixed 104-byte field, and a home directory deep
        // enough to overflow it would otherwise fail inside `bind` with a
        // errno nobody could act on.
        guard pathBytes.count < MemoryLayout<sockaddr_un>.size
            - MemoryLayout<UInt8>.size * 2 else {
            setListenDiagnostic(
                "预览通道路径过长，无法创建；本次运行不显示会话正文预览。"
            )
            return false
        }

        // A socket left behind by a crash keeps `bind` from succeeding, and it
        // is ours by construction -- it lives in a directory this app owns.
        unlink(socketURL.path)

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            setListenDiagnostic("预览通道创建失败；本次运行不显示会话正文预览。")
            return false
        }

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
            setListenDiagnostic("预览通道绑定失败；本次运行不显示会话正文预览。")
            return false
        }

        // Only this user's processes may hand text to this app.
        chmod(socketURL.path, 0o600)

        guard listen(descriptor, 16) == 0 else {
            close(descriptor)
            unlink(socketURL.path)
            setListenDiagnostic("预览通道监听失败；本次运行不显示会话正文预览。")
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

        lock.lock()
        listeningDescriptor = descriptor
        acceptSource = source
        listenDiagnostic = nil
        lock.unlock()

        source.resume()
        return true
    }

    nonisolated func stop() {
        lock.lock()
        let source = acceptSource
        acceptSource = nil
        listeningDescriptor = -1
        previewsByEventID.removeAll()
        claimOrder.removeAll()
        lock.unlock()

        source?.cancel()
        unlink(socketURL.path)
    }

    /// Whether received text is retained at all.
    ///
    /// This is the privacy switch. It is a single in-memory flag rather than a
    /// setting written to the helper, which is what makes it ordered and
    /// infallible: there is no write to lose, no revision to race, and no way
    /// for the UI to show "off" while text is still being collected.
    nonisolated func setAcceptsText(_ accepts: Bool) {
        lock.lock()
        acceptsText = accepts
        if !accepts {
            previewsByEventID.removeAll()
            claimOrder.removeAll()
        }
        lock.unlock()
    }

    /// Removes and returns the preview for one event, if it arrived.
    nonisolated func claimPreview(forEventID eventID: String) -> Preview? {
        lock.lock()
        defer { lock.unlock() }
        guard let preview = previewsByEventID.removeValue(forKey: eventID) else {
            return nil
        }
        claimOrder.removeAll { $0 == eventID }
        return preview
    }

    nonisolated var diagnostic: String? {
        lock.lock()
        defer { lock.unlock() }
        return listenDiagnostic
    }

    nonisolated var retainedPreviewCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return previewsByEventID.count
    }

    nonisolated private func setListenDiagnostic(_ message: String) {
        lock.lock()
        listenDiagnostic = message
        lock.unlock()
    }

    nonisolated private func acceptPendingConnections() {
        lock.lock()
        let descriptor = listeningDescriptor
        lock.unlock()
        guard descriptor >= 0 else { return }

        while true {
            let connection = accept(descriptor, nil, nil)
            guard connection >= 0 else { return }
            readQueue.async { [weak self] in
                self?.receiveMessage(on: connection)
            }
        }
    }

    nonisolated private func receiveMessage(on descriptor: Int32) {
        defer { close(descriptor) }

        var timeout = timeval(
            tv_sec: 0,
            tv_usec: Self.receiveTimeoutMicroseconds
        )
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var message = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)

        while message.count <= Self.maximumMessageByteCount {
            let readCount = read(descriptor, &buffer, buffer.count)
            guard readCount > 0 else { break }
            message.append(contentsOf: buffer[0 ..< readCount])
            if buffer[0 ..< readCount].contains(0x0A) { break }
        }

        guard !message.isEmpty,
              message.count <= Self.maximumMessageByteCount else {
            return
        }
        if let newline = message.firstIndex(of: 0x0A) {
            message = message[message.startIndex ..< newline]
        }

        guard let decoded = try? JSONDecoder().decode(
            Message.self,
            from: message
        ) else {
            return
        }
        let eventID = decoded.eventID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !eventID.isEmpty else { return }

        let preview = Preview(
            prompt: decoded.prompt,
            assistantMessage: decoded.lastAssistantMessage
        )
        guard !preview.isEmpty else { return }

        store(preview, forEventID: eventID)
    }

    nonisolated private func store(_ preview: Preview, forEventID eventID: String) {
        lock.lock()
        defer { lock.unlock() }
        guard acceptsText else { return }

        if previewsByEventID.updateValue(preview, forKey: eventID) == nil {
            claimOrder.append(eventID)
        }
        while claimOrder.count > maximumRetainedPreviews {
            let evicted = claimOrder.removeFirst()
            previewsByEventID.removeValue(forKey: evicted)
        }
    }
}

import Foundation
import OSLog

indirect enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    nonisolated subscript(key: String) -> JSONValue? {
        guard case let .object(object) = self else { return nil }
        return object[key]
    }

    nonisolated var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    nonisolated var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    nonisolated var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    nonisolated var doubleValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }

    /// Truncated toward zero, so `42.5` reads `42`. A number the type cannot hold is nil: valid JSON
    /// such as `1e300` would otherwise trap in `Int.init(_: Double)` and end the process.
    nonisolated var intValue: Int? {
        doubleValue.flatMap { Int(exactly: $0.rounded(.towardZero)) }
    }

    nonisolated var int64Value: Int64? {
        doubleValue.flatMap { Int64(exactly: $0.rounded(.towardZero)) }
    }

    nonisolated var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }
}

nonisolated protocol CodexAppServerCommunicating: Sendable {
    func connect() async throws
    func request(
        method: String,
        params: JSONValue?,
        timeoutNanoseconds: UInt64?
    ) async throws -> JSONValue
    func disconnect() async
}

extension CodexAppServerCommunicating {
    func request(method: String, params: JSONValue?) async throws -> JSONValue {
        try await request(
            method: method,
            params: params,
            timeoutNanoseconds: nil
        )
    }
}

enum CodexAppServerError: LocalizedError, Equatable, Sendable {
    case executableNotFound
    case launchFailed(String)
    case disconnected
    case timeout(method: String)
    case protocolViolation(String)
    case remote(code: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            "Could not find Codex CLI or the executable shipped with Codex Desktop."
        case let .launchFailed(message):
            "Could not start the Codex App Server: \(message)"
        case .disconnected:
            "The Codex App Server has disconnected."
        case let .timeout(method):
            "A Codex App Server call timed out: \(method)"
        case let .protocolViolation(message):
            "The Codex App Server returned data that could not be understood: \(message)"
        case let .remote(code, message):
            "Codex App Server error \(code): \(message)"
        }
    }

    var isUnsupportedMethod: Bool {
        if case let .remote(code, _) = self {
            return code == -32601
        }
        return false
    }

    var requiresConnectionReset: Bool {
        switch self {
        case .disconnected, .launchFailed:
            true
        case .executableNotFound, .timeout, .protocolViolation, .remote:
            false
        }
    }

    var isTransientRequestFailure: Bool {
        switch self {
        case .timeout, .protocolViolation:
            true
        case .remote:
            !isUnsupportedMethod
        case .executableNotFound, .launchFailed, .disconnected:
            false
        }
    }
}

enum CodexExecutableLocator {
    nonisolated static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [String] = []

        if let override = environment["NOTCHLINE_CODEX_PATH"], !override.isEmpty {
            candidates.append(override)
        }

        candidates.append(contentsOf: [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ])

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                String($0) + "/codex"
            })
        }

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}

struct NewlineDelimitedMessageBuffer {
    private var partialMessage = Data()
    private var totalScannedByteCount = 0

    nonisolated init() {}

    nonisolated var bufferedByteCount: Int {
        partialMessage.count
    }

    nonisolated var scannedByteCount: Int {
        totalScannedByteCount
    }

    nonisolated mutating func append(_ data: Data) -> [Data] {
        guard !data.isEmpty else { return [] }

        var messages: [Data] = []
        var segmentStart = data.startIndex

        while segmentStart < data.endIndex,
              let newline = data[segmentStart...].firstIndex(of: 0x0A) {
            totalScannedByteCount += data.distance(
                from: segmentStart,
                to: data.index(after: newline)
            )

            let segment = data[segmentStart..<newline]
            if partialMessage.isEmpty {
                messages.append(Data(segment))
            } else {
                partialMessage.append(contentsOf: segment)
                messages.append(partialMessage)
                partialMessage = Data()
            }

            segmentStart = data.index(after: newline)
        }

        if segmentStart < data.endIndex {
            totalScannedByteCount += data.distance(
                from: segmentStart,
                to: data.endIndex
            )
            partialMessage.append(contentsOf: data[segmentStart...])
        }

        return messages
    }

    nonisolated mutating func reset() {
        partialMessage.removeAll(keepingCapacity: false)
        totalScannedByteCount = 0
    }
}

/// One ordered, already-framed unit from the App Server output stream.
enum AppServerStreamEvent: Sendable {
    case frame(Data)
    case framingOverflow(bufferedByteCount: Int)
    case streamEnded
}

/// Frames the App Server's stdout into newline-delimited messages on `FileHandle`'s serial
/// readability queue, not behind an actor hop: one reordered chunk corrupts every later frame.
final class AppServerStreamPump: @unchecked Sendable {
    private let maximumFrameByteCount: Int
    private let continuation: AsyncStream<AppServerStreamEvent>.Continuation
    nonisolated(unsafe) private var buffer = NewlineDelimitedMessageBuffer()
    nonisolated(unsafe) private var hasEnded = false

    nonisolated init(
        maximumFrameByteCount: Int,
        continuation: AsyncStream<AppServerStreamEvent>.Continuation
    ) {
        self.maximumFrameByteCount = maximumFrameByteCount
        self.continuation = continuation
    }

    /// Must only be called from the serialized queue that owns this pump.
    nonisolated func ingest(_ data: Data) {
        guard !hasEnded else { return }

        guard !data.isEmpty else {
            end(with: .streamEnded)
            return
        }

        for frame in buffer.append(data) {
            continuation.yield(.frame(frame))
        }

        // A frame this large is not a plausible response; fail closed rather than grow without bound.
        guard buffer.bufferedByteCount <= maximumFrameByteCount else {
            end(
                with: .framingOverflow(
                    bufferedByteCount: buffer.bufferedByteCount
                )
            )
            return
        }
    }

    nonisolated private func end(with event: AppServerStreamEvent) {
        hasEnded = true
        buffer.reset()
        continuation.yield(event)
        continuation.finish()
    }
}

actor CodexAppServerClient: CodexAppServerCommunicating {
    nonisolated private static let logger = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "AppServerTransport"
    )

    private enum RequestPurpose {
        case regular
        case livenessProbe
    }

    private enum ConnectionPhase: Equatable {
        case disconnected
        case connecting(Int)
        case connected(Int)

        var generation: Int? {
            switch self {
            case .disconnected:
                nil
            case let .connecting(generation), let .connected(generation):
                generation
            }
        }
    }

    private struct PendingRequest {
        let method: String
        let purpose: RequestPurpose
        let continuation: CheckedContinuation<JSONValue, Error>
    }

    private let executableURL: URL?
    private let requestTimeoutNanoseconds: UInt64
    private let livenessProbeGraceNanoseconds: UInt64
    private let livenessProbeTimeoutNanoseconds: UInt64
    private let killGraceNanoseconds: UInt64
    private let maximumFrameByteCount: Int
    private let clock: any MonitorClock
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var streamContinuation: AsyncStream<AppServerStreamEvent>.Continuation?
    private var streamConsumerTask: Task<Void, Never>?
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var nextRequestID = 1
    private var connectionPhase = ConnectionPhase.disconnected
    private var connectionGeneration = 0
    private var connectionWaiters: [CheckedContinuation<Void, Error>] = []
    private var responseSequence: UInt64 = 0
    private var undecodableFrameCount = 0
    private var livenessProbeTask: Task<Void, Never>?
    private var livenessProbeID = 0

    init(
        executableURL: URL? = CodexExecutableLocator.locate(),
        requestTimeoutNanoseconds: UInt64 = 15_000_000_000,
        livenessProbeGraceNanoseconds: UInt64 = 3_000_000_000,
        livenessProbeTimeoutNanoseconds: UInt64 = 5_000_000_000,
        killGraceNanoseconds: UInt64 = 2_000_000_000,
        maximumFrameByteCount: Int = 64 * 1_024 * 1_024,
        clock: any MonitorClock = SystemMonitorClock()
    ) {
        self.executableURL = executableURL
        self.requestTimeoutNanoseconds = requestTimeoutNanoseconds
        self.livenessProbeGraceNanoseconds = livenessProbeGraceNanoseconds
        self.livenessProbeTimeoutNanoseconds = livenessProbeTimeoutNanoseconds
        self.killGraceNanoseconds = killGraceNanoseconds
        self.maximumFrameByteCount = maximumFrameByteCount
        self.clock = clock
    }

    func connect() async throws {
        switch connectionPhase {
        case .connected:
            return
        case .connecting:
            return try await withCheckedThrowingContinuation { continuation in
                connectionWaiters.append(continuation)
            }
        case .disconnected:
            break
        }

        guard let executableURL else {
            throw CodexAppServerError.executableNotFound
        }

        connectionGeneration += 1
        let generation = connectionGeneration
        connectionPhase = .connecting(generation)

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        let (streamEvents, streamContinuation) = AsyncStream.makeStream(
            of: AppServerStreamEvent.self,
            bufferingPolicy: .unbounded
        )
        let pump = AppServerStreamPump(
            maximumFrameByteCount: maximumFrameByteCount,
            continuation: streamContinuation
        )

        let outputHandle = outputPipe.fileHandleForReading
        // Frame synchronously on the readability queue; no actor hop, so server byte order survives.
        outputHandle.readabilityHandler = { handle in
            pump.ingest(handle.availableData)
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            let reason = process.terminationReason.rawValue
            Task {
                await self?.serverTerminated(
                    generation: generation,
                    status: status,
                    reason: reason
                )
            }
        }

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            streamContinuation.finish()
            let launchError = CodexAppServerError.launchFailed(
                error.localizedDescription
            )
            connectionPhase = .disconnected
            finishConnectionWaiters(with: .failure(launchError))
            throw launchError
        }

        self.process = process
        self.inputHandle = inputPipe.fileHandleForWriting
        self.outputHandle = outputHandle
        self.streamContinuation = streamContinuation
        self.streamConsumerTask = consumeStream(
            streamEvents,
            generation: generation
        )

        do {
            _ = try await request(
                method: "initialize",
                params: .object([
                    "clientInfo": .object([
                        "name": .string("notchline"),
                        "title": .string("Notchline"),
                        "version": .string("0.1.0")
                    ]),
                    "capabilities": .object([
                        "experimentalApi": .bool(true)
                    ])
                ])
            )
            guard connectionPhase == .connecting(generation) else {
                throw CodexAppServerError.disconnected
            }
            try sendNotification(method: "initialized", params: nil)
            connectionPhase = .connected(generation)
            finishConnectionWaiters(with: .success(()))
        } catch {
            if connectionPhase.generation == generation {
                tearDownConnection()
                connectionPhase = .disconnected
                failPendingRequests(with: error)
                finishConnectionWaiters(with: .failure(error))
            }
            throw error
        }
    }

    func request(
        method: String,
        params: JSONValue?,
        timeoutNanoseconds: UInt64? = nil
    ) async throws -> JSONValue {
        try await performRequest(
            method: method,
            params: params,
            timeoutNanoseconds: timeoutNanoseconds,
            purpose: .regular
        )
    }

    private func performRequest(
        method: String,
        params: JSONValue?,
        timeoutNanoseconds: UInt64?,
        purpose: RequestPurpose
    ) async throws -> JSONValue {
        guard inputHandle != nil else {
            throw CodexAppServerError.disconnected
        }

        let requestID = nextRequestID
        nextRequestID += 1

        let envelope = JSONValue.object([
            "id": .number(Double(requestID)),
            "method": .string(method),
            "params": params ?? .null
        ])

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestID] = PendingRequest(
                method: method,
                purpose: purpose,
                continuation: continuation
            )

            do {
                try write(envelope)
            } catch {
                pendingRequests.removeValue(forKey: requestID)
                continuation.resume(throwing: error)
                return
            }

            let timeout = timeoutNanoseconds ?? requestTimeoutNanoseconds
            let clock = clock
            Task { [weak self] in
                try? await clock.sleep(nanoseconds: timeout)
                await self?.timeOutRequest(id: requestID)
            }
        }
    }

    func disconnect() async {
        cancelLivenessProbe()
        connectionGeneration += 1
        connectionPhase = .disconnected
        tearDownConnection()
        failPendingRequests(with: CodexAppServerError.disconnected)
        finishConnectionWaiters(with: .failure(CodexAppServerError.disconnected))
    }

    private func tearDownConnection() {
        outputHandle?.readabilityHandler = nil
        outputHandle = nil
        inputHandle?.closeFile()
        inputHandle = nil

        // The pump owning the frame buffer was just released; finishing ends framing and consumer together.
        streamContinuation?.finish()
        streamContinuation = nil
        streamConsumerTask?.cancel()
        streamConsumerTask = nil

        if let process, process.isRunning {
            process.terminate()
            escalateKill(of: process)
        }
        process = nil
    }

    /// `SIGKILL` a server that outlived the `SIGTERM`: a wedged one otherwise piles up `codex`
    /// processes across resets (CR-Fable-014). Does not wait for exit, which would park this actor.
    /// The pid is read before the delay: it is 0 before launch, and `kill(0, ...)` signals this
    /// app's own process group.
    private func escalateKill(of process: Process) {
        let pid = process.processIdentifier
        guard pid > 0 else { return }
        Task {
            try? await self.clock.sleep(nanoseconds: self.killGraceNanoseconds)
            guard process.isRunning else { return }
            Self.logger.warning(
                "App Server outlived SIGTERM; killing pid=\(pid, privacy: .public)"
            )
            kill(pid, SIGKILL)
        }
    }

    private func sendNotification(method: String, params: JSONValue?) throws {
        try write(.object([
            "method": .string(method),
            "params": params ?? .null
        ]))
    }

    private func write(_ value: JSONValue) throws {
        guard let inputHandle else {
            throw CodexAppServerError.disconnected
        }

        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        do {
            try inputHandle.write(contentsOf: data)
        } catch {
            throw CodexAppServerError.disconnected
        }
    }

    /// Drains framed events in order and decodes them off the actor (`nonisolated`, so a `Task` does
    /// not inherit the actor).
    nonisolated private func consumeStream(
        _ events: AsyncStream<AppServerStreamEvent>,
        generation: Int
    ) -> Task<Void, Never> {
        Task { [weak self] in
            for await event in events {
                switch event {
                case let .frame(frame):
                    guard !frame.isEmpty else { continue }
                    // thread/list decodes are the heaviest work; off the actor they delay nothing else.
                    guard let envelope = try? JSONDecoder().decode(
                        JSONValue.self,
                        from: frame
                    ) else {
                        await self?.discardUndecodableFrame(
                            byteCount: frame.count,
                            generation: generation
                        )
                        continue
                    }
                    await self?.handleEnvelope(envelope, generation: generation)
                case let .framingOverflow(bufferedByteCount):
                    await self?.handleFramingOverflow(
                        bufferedByteCount: bufferedByteCount,
                        generation: generation
                    )
                case .streamEnded:
                    await self?.streamEnded(generation: generation)
                }
            }
        }
    }

    private func discardUndecodableFrame(byteCount: Int, generation: Int) {
        guard connectionPhase.generation == generation else { return }

        // Non-fatal, but logged so it does not surface only as a timeout. Never log the payload.
        undecodableFrameCount += 1
        Self.logger.warning(
            "Discarded an undecodable App Server frame: bytes=\(byteCount, privacy: .public) total=\(self.undecodableFrameCount, privacy: .public)"
        )
    }

    private func handleFramingOverflow(
        bufferedByteCount: Int,
        generation: Int
    ) {
        guard connectionPhase.generation == generation else { return }

        Self.logger.warning(
            "App Server frame exceeded the transport limit: buffered=\(bufferedByteCount, privacy: .public) limit=\(self.maximumFrameByteCount, privacy: .public); resetting transport"
        )
        failConnection(
            with: .protocolViolation(
                "App Server frame exceeded \(maximumFrameByteCount) bytes"
            )
        )
    }

    private func streamEnded(generation: Int) {
        guard connectionPhase.generation == generation else { return }

        let hasExited = process?.isRunning == false
        serverTerminated(
            generation: generation,
            status: hasExited ? process?.terminationStatus : nil,
            reason: hasExited ? process?.terminationReason.rawValue : nil
        )
    }

    private func handleEnvelope(_ envelope: JSONValue, generation: Int) {
        guard connectionPhase.generation == generation else { return }
        guard let id = envelope["id"]?.intValue else {
            // Notifications and server requests are ignored; this client never answers them.
            return
        }
        // A late response still proves the transport and server event loop are alive.
        responseSequence &+= 1
        guard let pending = pendingRequests.removeValue(forKey: id) else {
            return
        }

        if let error = envelope["error"], case .object = error {
            pending.continuation.resume(
                throwing: CodexAppServerError.remote(
                    code: error["code"]?.intValue ?? -1,
                    message: error["message"]?.stringValue ?? "Unknown error"
                )
            )
            return
        }

        guard let result = envelope["result"] else {
            pending.continuation.resume(
                throwing: CodexAppServerError.protocolViolation(
                    "response to \(pending.method) has no result"
                )
            )
            return
        }
        pending.continuation.resume(returning: result)
    }

    private func timeOutRequest(id: Int) {
        guard let pending = pendingRequests.removeValue(forKey: id) else { return }
        Self.logger.warning(
            "Request timed out: method=\(pending.method, privacy: .public) id=\(id, privacy: .public) outstanding=\(self.pendingRequests.count, privacy: .public)"
        )
        pending.continuation.resume(
            throwing: CodexAppServerError.timeout(method: pending.method)
        )

        guard case .regular = pending.purpose else {
            return
        }
        scheduleLivenessProbeIfNeeded(triggeredBy: pending.method)
    }

    private func scheduleLivenessProbeIfNeeded(triggeredBy method: String) {
        guard livenessProbeTask == nil,
              case let .connected(generation) = connectionPhase else {
            return
        }

        livenessProbeID += 1
        let probeID = livenessProbeID
        let baselineResponseSequence = responseSequence
        livenessProbeTask = Task { [weak self] in
            await self?.runLivenessProbe(
                id: probeID,
                connectionGeneration: generation,
                baselineResponseSequence: baselineResponseSequence,
                triggeredBy: method
            )
        }
    }

    private func runLivenessProbe(
        id: Int,
        connectionGeneration: Int,
        baselineResponseSequence: UInt64,
        triggeredBy method: String
    ) async {
        defer { finishLivenessProbe(id: id) }

        do {
            try await clock.sleep(nanoseconds: livenessProbeGraceNanoseconds)
        } catch {
            return
        }

        guard connectionPhase == .connected(connectionGeneration),
              responseSequence == baselineResponseSequence else {
            return
        }

        do {
            _ = try await performRequest(
                method: "thread/loaded/list",
                params: .object([:]),
                timeoutNanoseconds: livenessProbeTimeoutNanoseconds,
                purpose: .livenessProbe
            )
            Self.logger.info(
                "App Server liveness probe recovered after timeout: method=\(method, privacy: .public)"
            )
        } catch let error as CodexAppServerError {
            guard connectionPhase == .connected(connectionGeneration),
                  responseSequence == baselineResponseSequence else {
                return
            }

            switch error {
            case .timeout, .disconnected, .launchFailed:
                resetUnresponsiveTransport(
                    generation: connectionGeneration,
                    triggeredBy: method
                )
            case .executableNotFound, .protocolViolation, .remote:
                // Responses: handleEnvelope already advanced responseSequence, so this means the
                // connection changed concurrently.
                return
            }
        } catch {
            return
        }
    }

    private func finishLivenessProbe(id: Int) {
        guard id == livenessProbeID else { return }
        livenessProbeTask = nil
    }

    private func cancelLivenessProbe() {
        livenessProbeID += 1
        livenessProbeTask?.cancel()
        livenessProbeTask = nil
    }

    private func resetUnresponsiveTransport(
        generation: Int,
        triggeredBy method: String
    ) {
        guard connectionPhase == .connected(generation) else { return }

        Self.logger.warning(
            "App Server liveness probe timed out after request timeout: method=\(method, privacy: .public); resetting transport"
        )
        connectionPhase = .disconnected
        tearDownConnection()
        failPendingRequests(with: CodexAppServerError.disconnected)
        finishConnectionWaiters(with: .failure(CodexAppServerError.disconnected))
    }

    private func serverTerminated(
        generation: Int,
        status: Int32?,
        reason: Int?
    ) {
        guard connectionPhase.generation == generation else { return }
        let statusText = status.map { String($0) } ?? "unknown"
        let reasonText = reason.map { String($0) } ?? "unknown"
        Self.logger.warning(
            "App Server stream ended; status=\(statusText, privacy: .public) reason=\(reasonText, privacy: .public)"
        )
        failConnection(with: .disconnected)
    }

    private func failConnection(with error: CodexAppServerError) {
        cancelLivenessProbe()
        tearDownConnection()
        connectionPhase = .disconnected
        failPendingRequests(with: error)
        finishConnectionWaiters(with: .failure(error))
    }

    private func failPendingRequests(with error: Error) {
        let requests = pendingRequests.values
        pendingRequests.removeAll()
        for request in requests {
            request.continuation.resume(throwing: error)
        }
    }

    private func finishConnectionWaiters(with result: Result<Void, Error>) {
        let waiters = connectionWaiters
        connectionWaiters.removeAll()
        for waiter in waiters {
            switch result {
            case .success:
                waiter.resume()
            case let .failure(error):
                waiter.resume(throwing: error)
            }
        }
    }
}

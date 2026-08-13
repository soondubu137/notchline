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

    nonisolated var intValue: Int? {
        doubleValue.map(Int.init)
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
            "找不到 Codex Desktop 随附的 codex 可执行文件。"
        case let .launchFailed(message):
            "无法启动 Codex App Server：\(message)"
        case .disconnected:
            "Codex App Server 已断开。"
        case let .timeout(method):
            "Codex App Server 调用超时：\(method)"
        case let .protocolViolation(message):
            "Codex App Server 返回了无法识别的数据：\(message)"
        case let .remote(code, message):
            "Codex App Server 错误 \(code)：\(message)"
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

        if let override = environment["CODEX_IN_NOTCH_CODEX_PATH"], !override.isEmpty {
            candidates.append(override)
        }

        candidates.append(contentsOf: [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
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

actor CodexAppServerClient: CodexAppServerCommunicating {
    nonisolated private static let logger = Logger(
        subsystem: "com.yinfenglu.CodexInNotch",
        category: "AppServerTransport"
    )

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
        let continuation: CheckedContinuation<JSONValue, Error>
    }

    private let executableURL: URL?
    private let requestTimeoutNanoseconds: UInt64
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var messageBuffer = NewlineDelimitedMessageBuffer()
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var nextRequestID = 1
    private var connectionPhase = ConnectionPhase.disconnected
    private var connectionGeneration = 0
    private var connectionWaiters: [CheckedContinuation<Void, Error>] = []

    init(
        executableURL: URL? = CodexExecutableLocator.locate(),
        requestTimeoutNanoseconds: UInt64 = 15_000_000_000
    ) {
        self.executableURL = executableURL
        self.requestTimeoutNanoseconds = requestTimeoutNanoseconds
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

        let outputHandle = outputPipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task {
                await self?.receive(data, generation: generation)
            }
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

        do {
            _ = try await request(
                method: "initialize",
                params: .object([
                    "clientInfo": .object([
                        "name": .string("codex-in-notch"),
                        "title": .string("Codex in Notch"),
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
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeout)
                await self?.timeOutRequest(id: requestID)
            }
        }
    }

    func disconnect() async {
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

        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        messageBuffer.reset()
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

    private func receive(_ data: Data, generation: Int) {
        guard connectionPhase.generation == generation else { return }
        guard !data.isEmpty else {
            serverTerminated(
                generation: generation,
                status: process?.isRunning == false ? process?.terminationStatus : nil,
                reason: process?.isRunning == false ? process?.terminationReason.rawValue : nil
            )
            return
        }

        for line in messageBuffer.append(data) {
            guard !line.isEmpty else { continue }

            do {
                let envelope = try JSONDecoder().decode(JSONValue.self, from: line)
                handleEnvelope(envelope)
            } catch {
                // A malformed notification must not destroy otherwise healthy
                // read-only monitoring. Requests still have their own timeout.
                continue
            }
        }
    }

    private func handleEnvelope(_ envelope: JSONValue) {
        guard let id = envelope["id"]?.intValue,
              let pending = pendingRequests.removeValue(forKey: id) else {
            // Notifications and server-initiated requests are deliberately
            // ignored. This client never answers approval or input requests.
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
        Self.logger.warning("Request timed out: \(pending.method, privacy: .public)")
        pending.continuation.resume(
            throwing: CodexAppServerError.timeout(method: pending.method)
        )
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
        tearDownConnection()
        connectionPhase = .disconnected
        failPendingRequests(with: CodexAppServerError.disconnected)
        finishConnectionWaiters(with: .failure(CodexAppServerError.disconnected))
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

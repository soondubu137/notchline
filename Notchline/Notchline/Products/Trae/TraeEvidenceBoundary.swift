import Foundation

/// The companion wire schema is private, versioned and bounded. No native JSON
/// crosses this boundary into the shared Turn reducer.
nonisolated struct TraeFrame: Decodable, Sendable {
    let type: String
    var schema: Int?
    var version: String?
    var bridgeVersion: String?
    var pid: Int32?
    var sequence: Int?
    var baseline: Bool?
    var observedAt: Double?
    var rows: [TraeDisplayedTurn]?
    var excluded: [String]? = nil
}

nonisolated struct TraeDisplayedTurn: Decodable, Sendable, Equatable {
    let threadID: String
    let turnID: String
    let messageID: String
    let userMessageID: String
    let title: String
    let folder: String?
    let status: String
    let startedAt: Double?
    let endedAt: Double?
    let historical: Bool
    let preview: String?
    let requests: [TraeDisplayedRequest]

    func validate() throws {
        guard [threadID, turnID, messageID, userMessageID].allSatisfy(TraeEvidenceBoundary.validID),
              ["in_progress", "completed", "canceled", "failed"].contains(status),
              title.utf8.count <= 16_384, (preview?.utf8.count ?? 0) <= 16_384,
              folder == nil || (folder!.hasPrefix("/") && folder!.utf8.count <= 4096),
              startedAt.map({ $0.isFinite && $0 > 0 }) ?? true,
              endedAt.map({ $0.isFinite && $0 > 0 }) ?? true,
              requests.count <= 64, Set(requests.map(\.id)).count == requests.count,
              status == "in_progress" || requests.isEmpty else { throw TraeBridgeError.schema }
        for request in requests { try request.validate() }
    }
}

nonisolated struct TraeDisplayedRequest: Decodable, Sendable, Equatable {
    let id: String
    let toolID: String
    let producer: String
    let name: String
    let kind: String
    let command: String?
    let details: [String: JSONValue]?
    let questions: [TraeDisplayedQuestion]?

    func validate() throws {
        guard TraeEvidenceBoundary.validID(id), TraeEvidenceBoundary.validID(toolID),
              producer.utf8.count <= 512, name.utf8.count <= 256,
              ["command", "questions", "unsupported"].contains(kind) else { throw TraeBridgeError.schema }
        if kind == "command" {
            guard name == "RunCommand", let command, command.utf8.count <= 131_072 else { throw TraeBridgeError.schema }
        }
        if kind == "questions" {
            guard name == "AskUserQuestion", let questions, !questions.isEmpty, questions.count <= 33,
                  Set(questions.map(\.id)).count == questions.count else { throw TraeBridgeError.schema }
            for question in questions { try question.validate() }
        }
    }

    var requestIdentity: String { producer + ":" + id }

    func request() -> AgentRequest {
        let form: AgentRequest.Form
        var arguments: [ApprovalArgument] = []
        switch kind {
        case "command":
            form = .command(command ?? "")
            var fields = details ?? [:]
            fields["command"] = .string(command ?? "")
            arguments = AgentRequestReading.approvalFields(in: .object(fields))
        case "questions":
            form = .questions((questions ?? []).enumerated().map { offset, question in
                AgentQuestion(id: offset, header: question.header, text: question.text,
                    options: question.options.enumerated().map {
                        AgentQuestionOption(id: $0.offset, label: $0.element.label,
                            description: $0.element.description, nativeID: $0.element.id)
                    }, allowsSeveralAnswers: question.multiple, nativeID: question.id,
                    acceptsFreeText: question.freeText,
                    readingHint: question.readingHint)
            })
        default: form = .unsupported
        }
        return AgentRequest(id: requestIdentity, toolName: name, form: form,
                            argumentFields: arguments, operations: .readingOnly)
    }
}

nonisolated struct TraeDisplayedQuestion: Decodable, Sendable, Equatable {
    nonisolated struct Option: Decodable, Sendable, Equatable {
        let id: String
        let label: String
        let description: String?
    }
    let id: String
    let header: String?
    let text: String
    let options: [Option]
    let multiple: Bool
    let freeText: Bool
    let optional: Bool
    let maximumTextLength: Int?

    func validate() throws {
        guard !id.isEmpty, id.utf8.count <= 256, text.utf8.count <= 131_072,
              (header?.count ?? 0) <= 64, options.count <= 65,
              Set(options.map(\.id)).count == options.count,
              maximumTextLength == nil || [500, 1000].contains(maximumTextLength!),
              options.allSatisfy({ !$0.id.isEmpty && $0.label.utf8.count <= 16_384 && ($0.description?.utf8.count ?? 0) <= 32_768 }) else {
            throw TraeBridgeError.schema
        }
    }

    var readingHint: String {
        var parts: [String] = []
        if optional { parts.append("Optional.") }
        else if !options.isEmpty { parts.append(multiple ? "Choose one or more options." : "Choose one option.") }
        if let maximumTextLength { parts.append("Custom text: up to \(maximumTextLength) characters.") }
        return parts.joined(separator: " ")
    }
}

nonisolated enum TraeBridgeError: Error, LocalizedError {
    case schema, version, unavailable, installation(String)
    var errorDescription: String? {
        switch self {
        case .schema: "Trae's displayed data could not be verified. Reopen its window to reconnect."
        case .version: "This integration requires Trae 3.5.91 with the verified application build."
        case .unavailable: "Trae's companion is not connected. Reopen the Trae window after installing it."
        case let .installation(message): message
        }
    }
}

/// Transport serial queue only; source order is kept into MonitoringRepository's ordered inbox.
nonisolated struct TraeEvidenceBoundary {
    private(set) var current: [String: TraeDisplayedTurn] = [:]
    private var sequences: [String: Int] = [:]
    private var baselines: [String: Double] = [:]
    private var owners: [String: String] = [:]
    private var admitted: Set<String> = []
    private var excluded: Set<String> = []

    static func validID(_ value: String) -> Bool {
        value.count == 24 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    mutating func consume(_ frame: TraeFrame, peer: String, repository: MonitoringRepository,
                          epoch: MonitoringEpoch) throws {
        guard frame.type == "snapshot", frame.schema == 1, frame.version == TraeInstallation.traeVersion,
              let sequence = frame.sequence, sequence > 0, let baseline = frame.baseline,
              let stamp = frame.observedAt, stamp.isFinite, stamp > 0,
              let rows = frame.rows, rows.count <= 128,
              Set(rows.map(\.threadID)).count == rows.count else { throw TraeBridgeError.schema }
        let exclusions = frame.excluded ?? []
        guard exclusions.count <= 512, exclusions.allSatisfy(Self.validID),
              Set(exclusions).isDisjoint(with: rows.map(\.threadID)) else { throw TraeBridgeError.schema }
        // Validate the whole frame before mutating any held value or request.
        for row in rows { try row.validate() }
        if sequence <= (sequences[peer] ?? 0) { return }
        if baseline {
            guard sequence == 1 else { throw TraeBridgeError.schema }
            baselines[peer] = stamp
        } else {
            guard baselines[peer] != nil, sequence == (sequences[peer] ?? 0) + 1 else { throw TraeBridgeError.schema }
        }
        guard Set(current.keys).union(rows.map(\.threadID)).count <= 512 else { throw TraeBridgeError.schema }
        sequences[peer] = sequence
        let observedAt = Date(timeIntervalSince1970: stamp)
        for id in exclusions where owners[id] == peer { excluded.insert(id) }
        for row in rows {
            if let owner = owners[row.threadID], owner != peer { continue }
            owners[row.threadID] = peer
            excluded.remove(row.threadID)
            let previous = current[row.threadID]
            let sameTurn = previous?.turnID == row.turnID
            // A second window may hold an old view of an ended Turn; reconnecting must not reopen it.
            if sameTurn, previous?.status != "in_progress", row.status == "in_progress" { continue }
            if !sameTurn, let previousStart = previous?.startedAt, let nextStart = row.startedAt,
               nextStart < previousStart { continue }
            let key = row.threadID + ":" + row.turnID
            // A baseline is history: only a live, native, non-history assistant created after attachment
            // opens a row.
            let newlyStarted = !baseline && !row.historical && row.status == "in_progress"
                && !sameTurn && (row.startedAt.map { $0 >= (baselines[peer] ?? stamp) - 1 } ?? false)
            if newlyStarted {
                if let previous { admitted.remove(row.threadID + ":" + previous.turnID) }
                admitted.insert(key)
                repository.submit(MonitoringEvidence(signal: .turnStarted, threadID: row.threadID,
                    observedAt: row.startedAt.map(Date.init(timeIntervalSince1970:)) ?? observedAt,
                    turnID: row.turnID, workingDirectory: row.folder), in: epoch)
            }
            current[row.threadID] = row
            guard admitted.contains(key) else { continue }
            if row.preview != previous?.preview || !sameTurn, let preview = row.preview {
                repository.recordProgress(MonitoringProgress(threadID: row.threadID, turnID: row.turnID,
                    messageID: row.messageID, text: preview), in: epoch)
            }
            if row.status != "in_progress" {
                if previous?.status == "in_progress" || newlyStarted {
                    let end = row.endedAt.map(Date.init(timeIntervalSince1970:)) ?? observedAt
                    repository.submit(MonitoringEvidence(signal: .turnEnded, threadID: row.threadID,
                        observedAt: max(end, row.startedAt.map(Date.init(timeIntervalSince1970:)) ?? end),
                        turnID: row.turnID, finalText: row.preview), in: epoch)
                }
                continue
            }
            let oldRequests = sameTurn ? previous?.requests ?? [] : []
            for old in oldRequests where !row.requests.contains(where: { $0.requestIdentity == old.requestIdentity }) {
                repository.submit(MonitoringEvidence(signal: .requestResolved, threadID: row.threadID,
                    observedAt: observedAt, turnID: row.turnID, requestID: old.requestIdentity), in: epoch)
            }
            for request in row.requests where !oldRequests.contains(request) || baseline {
                repository.submit(MonitoringEvidence(
                    signal: request.kind == "questions" || request.name == "AskUserQuestion" ? .inputWaitOpened : .approvalWaitOpened,
                    threadID: row.threadID, observedAt: observedAt, turnID: row.turnID,
                    requestID: request.requestIdentity, toolName: request.name, request: request.request()), in: epoch)
            }
        }
    }

    var observedThreadIDs: [String] {
        current.values.filter { admitted.contains($0.threadID + ":" + $0.turnID) }.map(\.threadID).sorted()
    }
    mutating func lost(peer: String) {
        sequences[peer] = nil; baselines[peer] = nil
        // Keep known Turn identity for correction but release the window route.
        owners = owners.filter { $0.value != peer }
    }
    func peer(for threadID: String) -> String? { excluded.contains(threadID) ? nil : owners[threadID] }
}

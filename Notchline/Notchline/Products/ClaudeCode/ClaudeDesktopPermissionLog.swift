import Foundation
import os

/// When Claude Desktop last recorded a human answering one of its permission
/// dialogs, per Desktop session.
nonisolated protocol DesktopPermissionResponseReporting: Sendable {
    /// - Returns: Desktop session id to its newest answered instant; absent is not evidence.
    func answeredAt() async -> [String: Date]
}

/// The desktop half of "the human has answered", read out of Claude Desktop's own log.
///
/// No hook fires on approval (all 31 events registered, CLI 2.1.241, 2026-08-23), and a
/// desktop-hosted session publishes no status (CC-022 / #41; ADR 0011). Log lines pair by id:
/// `Emitted tool permission request <id> for Bash in session local_…` and
/// `Received permission response for <id>: once (tool: Bash)`. An unpaired response is never
/// attributed; the decision is never read. Bounded tail of `~/Library/Logs/Claude/main.log`,
/// owned regular file only, with a cursor apart from ``ClaudeDesktopFocusLogReader``'s.
actor ClaudeDesktopPermissionLogReader: DesktopPermissionResponseReporting {
    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "ClaudeDesktopPermissionLog"
    )

    nonisolated private static let requestStatement = "Emitted tool permission request "
    nonisolated private static let requestSessionMarker = " in session "
    nonisolated private static let responseStatement = "Received permission response for "
    /// A byte ceiling on one reading, as ``ClaudeDesktopFocusLogReader``'s (log grows ~800 KiB/day).
    nonisolated private static let maximumRead = 256 * 1_024
    /// Longer than any Desktop id, short enough that a misread line cannot pass as one.
    nonisolated private static let maximumIdentifierLength = 200
    /// How many unanswered dialogs to remember; a bound against an uncontrolled file.
    nonisolated private static let maximumTrackedRequests = 256
    /// How many sessions to remember an answer for; same reason.
    nonisolated private static let maximumTrackedSessions = 128
    nonisolated private static let newline = UInt8(ascii: "\n")
    /// The stamp every line begins with: local time, one-second resolution, no zone.
    nonisolated private static let timestampLength = 19

    private struct FileRevision: Equatable {
        let size: UInt64
        let fileNumber: UInt64?
    }

    private let url: URL
    private let fileManager: FileManager
    private var offset: UInt64?
    private var fileNumber: UInt64?
    /// Desktop session id to the newest answer. Sticky, since it may be read before the event opening
    /// its wait is drained; waits compare it to their own opening instant.
    private var answeredByDesktopSessionID: [String: Date] = [:]
    /// Learning order, oldest first, for eviction.
    private var answeredOrder: [String] = []
    private var sessionByRequestID: [String: String] = [:]
    private var requestOrder: [String] = []

    nonisolated private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    init(
        logURL: URL = ClaudeDesktopFocusLogReader.liveLogURL(),
        fileManager: FileManager = .default
    ) {
        self.url = logURL
        self.fileManager = fileManager
    }

    func answeredAt() async -> [String: Date] {
        guard let revision = fileRevision() else {
            // Gone or not a plain file this user owns: keep answers, forget only the read position.
            offset = nil
            fileNumber = nil
            return answeredByDesktopSessionID
        }

        let start: UInt64
        if let offset, fileNumber == revision.fileNumber, offset <= revision.size {
            start = max(offset, Self.floor(under: revision.size))
        } else {
            // First read, rotated or truncated: read the tail; opening-instant checks refuse stale answers.
            start = Self.floor(under: revision.size)
        }
        let read = read(from: start, upTo: revision.size)
        consume(read.completeLines)
        // Only up to the last newline: a line still being written is incomplete.
        self.offset = start + UInt64(read.consumed)
        fileNumber = revision.fileNumber
        return answeredByDesktopSessionID
    }

    /// The earliest offset a reading of a file this size may start at; compared, not subtracted,
    /// because the values are unsigned.
    nonisolated private static func floor(under size: UInt64) -> UInt64 {
        size > UInt64(maximumRead) ? size - UInt64(maximumRead) : 0
    }

    /// - Returns: the bytes up to and including the last newline, and how many
    ///   bytes of the chunk that was.
    private func read(from start: UInt64, upTo end: UInt64) -> (
        completeLines: Data,
        consumed: Int
    ) {
        guard end > start, let handle = try? FileHandle(forReadingFrom: url) else {
            return (Data(), 0)
        }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: start)
        } catch {
            Self.log.debug(
                "unreadable Claude Desktop log: \(error.localizedDescription, privacy: .public)"
            )
            return (Data(), 0)
        }
        let wanted = Int(min(end - start, UInt64(Self.maximumRead)))
        guard let data = try? handle.read(upToCount: wanted), !data.isEmpty else {
            return (Data(), 0)
        }
        guard let lastNewline = data.lastIndex(of: Self.newline) else {
            return (Data(), 0)
        }
        let consumed = data.distance(from: data.startIndex, to: lastNewline) + 1
        return (data.prefix(consumed), consumed)
    }

    /// Reads both line shapes in written order: a response needs its opening line seen first.
    private func consume(_ data: Data) {
        for line in data.split(separator: Self.newline, omittingEmptySubsequences: true) {
            let text = String(decoding: line, as: UTF8.self)
            if let opened = Self.request(in: text) {
                remember(request: opened.requestID, of: opened.desktopSessionID)
            } else if let answered = Self.response(in: text),
                      let desktopSessionID = sessionByRequestID[answered.requestID] {
                // The dialog is over, so the pairing is dropped; this keeps the table small without eviction.
                forget(request: answered.requestID)
                remember(answer: answered.at, of: desktopSessionID)
            }
        }
    }

    /// - Returns: the request a line raised, and the session that raised it.
    nonisolated private static func request(
        in text: String
    ) -> (requestID: String, desktopSessionID: String)? {
        guard let marker = text.range(of: requestStatement),
              let session = text.range(
                of: requestSessionMarker,
                range: marker.upperBound..<text.endIndex
              ) else {
            return nil
        }
        // The tool is not read: the reducer already knows which call it holds.
        let requestID = text[marker.upperBound...]
            .prefix { !$0.isWhitespace }
        let desktopSessionID = text[session.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isIdentifier(requestID), isIdentifier(desktopSessionID) else { return nil }
        return (String(requestID), desktopSessionID)
    }

    /// - Returns: the request a line answered, and when it was answered.
    nonisolated private static func response(
        in text: String
    ) -> (requestID: String, at: Date)? {
        guard let marker = text.range(of: responseStatement),
              let at = timestamp(of: text) else {
            return nil
        }
        // The decision after the colon is not read: any answer ends the wait.
        let requestID = text[marker.upperBound...]
            .prefix { $0 != ":" && !$0.isWhitespace }
        guard isIdentifier(requestID) else { return nil }
        return (String(requestID), at)
    }

    /// The line's local-time stamp. One-second truncation only makes an answer look older (refused).
    nonisolated private static func timestamp(of text: String) -> Date? {
        guard text.count > timestampLength else { return nil }
        let head = String(text.prefix(timestampLength))
        return timestampFormatter.date(from: head)
    }

    nonisolated private static func isIdentifier(_ candidate: some StringProtocol) -> Bool {
        !candidate.isEmpty && candidate.count <= maximumIdentifierLength
    }

    private func remember(request requestID: String, of desktopSessionID: String) {
        if sessionByRequestID.updateValue(desktopSessionID, forKey: requestID) == nil {
            requestOrder.append(requestID)
        }
        while requestOrder.count > Self.maximumTrackedRequests {
            sessionByRequestID.removeValue(forKey: requestOrder.removeFirst())
        }
    }

    private func forget(request requestID: String) {
        guard sessionByRequestID.removeValue(forKey: requestID) != nil else { return }
        requestOrder.removeAll { $0 == requestID }
    }

    private func remember(answer at: Date, of desktopSessionID: String) {
        // Monotonic: a line read out of order must not wind an answer backwards.
        let newest = max(answeredByDesktopSessionID[desktopSessionID] ?? at, at)
        if answeredByDesktopSessionID.updateValue(newest, forKey: desktopSessionID) == nil {
            answeredOrder.append(desktopSessionID)
        }
        while answeredOrder.count > Self.maximumTrackedSessions {
            answeredByDesktopSessionID.removeValue(forKey: answeredOrder.removeFirst())
        }
    }

    private func fileRevision() -> FileRevision? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular else {
            return nil
        }
        if let owner = attributes[.ownerAccountID] as? NSNumber,
           owner.uint32Value != getuid() {
            return nil
        }
        return FileRevision(
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        )
    }
}

import Darwin
import Foundation
import os

/// What Claude Desktop says is on its screen, including when the answer is nothing.
///
/// `lastFocusedAt` records a session being put on screen, never taken off, so opening the
/// composer for a new session left a stale claim that retired an unread row (measured
/// 2026-08-19; ADR 0012 第二、三、四条). Desktop logs
/// `[CCD] LocalSessions.setFocusedSession: sessionId=` with the id or `null` on every
/// navigation (Claude Desktop `1.32885.1`). Only a veto over the records
/// (``ClaudeCodeMonitorService``); a bad log degrades to ``DesktopDisplayedSession/unknown``.
nonisolated protocol DesktopDisplayedSessionReporting: Sendable {
    func displayedSession() async -> DesktopDisplayedSession
}

/// One statement by Claude Desktop about what it has on screen.
nonisolated enum DesktopDisplayedSession: Equatable, Sendable {
    /// Desktop's own id, verbatim (`local_<uuid>` when hosted, `session_<id>` for cloud), joined
    /// to hook ids through Desktop's records. An id that joins to nothing belongs to no row.
    case session(desktopSessionID: String)
    /// Not a session (composer, home view, settings): no session is on screen, which the records
    /// cannot say.
    case nothing
    /// Nothing believable has been said: a fresh launch, or an unreadable log.
    case unknown
}

/// Claude Desktop's `~/Library/Logs/Claude/main.log`, read from the end and only forwards;
/// one line shape, and only a regular file this user owns.
///
/// - Only lines appended while watching are statements (`AGENTS.md` §6.2); the older tail may
///   only say ``DesktopDisplayedSession/nothing``.
/// - No change stream: the composer transition only keeps a row, which
///   ``MonitorTiming/terminalUnreadRecheckInterval`` picks up; other transitions have edges.
actor ClaudeDesktopFocusLogReader: DesktopDisplayedSessionReporting {
    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "ClaudeDesktopFocusLog"
    )

    /// Log path override for tests and unusual installs, like `NOTCHLINE_CLAUDE_DESKTOP_HOME`.
    nonisolated static let logOverrideKey = "NOTCHLINE_CLAUDE_DESKTOP_LOG"

    nonisolated private static let statement =
        "[CCD] LocalSessions.setFocusedSession: sessionId="
    /// What Claude Desktop writes when what is on screen is not a session.
    nonisolated private static let nothingOnScreen = "null"
    /// A ceiling on one reading, in bytes. The log grows ~800 KiB a day; this bounds the first
    /// reading of a long-accumulated log.
    nonisolated private static let maximumRead = 256 * 1_024
    /// Longer than any Desktop id, and short enough that a misread line cannot pass as one.
    nonisolated private static let maximumIdentifierLength = 200
    nonisolated private static let newline = UInt8(ascii: "\n")

    private struct FileRevision: Equatable {
        let size: UInt64
        let fileNumber: UInt64?
    }

    private let url: URL
    private let fileManager: FileManager
    /// Next reading's offset and its file; `nil` before the first look (``seed(upTo:)``).
    private var offset: UInt64?
    private var fileNumber: UInt64?
    /// The last statement this app is willing to believe. A statement stands
    /// until Desktop makes another one: losing the file does not unsay it.
    private var current: DesktopDisplayedSession = .unknown

    nonisolated static func liveLogURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let configured = environment[logOverrideKey], !configured.isEmpty {
            return URL(fileURLWithPath: (configured as NSString).expandingTildeInPath)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Claude/main.log")
    }

    init(
        logURL: URL = ClaudeDesktopFocusLogReader.liveLogURL(),
        fileManager: FileManager = .default
    ) {
        self.url = logURL
        self.fileManager = fileManager
    }

    func displayedSession() async -> DesktopDisplayedSession {
        guard let revision = fileRevision() else {
            // Gone, unreadable, or not a plain owned file: the statement stands, and a log that comes
            // back is read from its current end rather than replayed.
            offset = nil
            fileNumber = nil
            return current
        }

        if let offset, fileNumber == revision.fileNumber, offset <= revision.size {
            let start = max(offset, Self.floor(under: revision.size))
            let read = read(from: start, upTo: revision.size)
            if let statement = Self.lastStatement(in: read.completeLines) {
                current = statement
            }
            // Only up to the last newline: a line still being written is missing its tail.
            self.offset = start + UInt64(read.consumed)
        } else {
            // Not watched before (first reading, rotation or truncation): history may only say `nothing`.
            current = seed(upTo: revision.size)
            self.offset = revision.size
        }
        fileNumber = revision.fileNumber
        return current
    }

    /// The one thing the tail written before this app looked is allowed to say.
    private func seed(upTo size: UInt64) -> DesktopDisplayedSession {
        let read = read(from: Self.floor(under: size), upTo: size)
        guard Self.lastStatement(in: read.completeLines) == .nothing else {
            return .unknown
        }
        return .nothing
    }

    /// The earliest offset a reading may start at; compared, not subtracted, as these are unsigned.
    nonisolated private static func floor(under size: UInt64) -> UInt64 {
        size > UInt64(maximumRead) ? size - UInt64(maximumRead) : 0
    }

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

    /// The newest statement in a chunk, or nil. Later lines win; a chunk starting mid-line loses
    /// only that line's head, so the id is intact.
    nonisolated private static func lastStatement(
        in data: Data
    ) -> DesktopDisplayedSession? {
        var found: DesktopDisplayedSession?
        for line in data.split(separator: newline, omittingEmptySubsequences: true) {
            let text = String(decoding: line, as: UTF8.self)
            guard let marker = text.range(of: statement) else { continue }
            let identifier = text[marker.upperBound...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty,
                  identifier.count <= maximumIdentifierLength else {
                continue
            }
            found = identifier == nothingOnScreen
                ? .nothing
                : .session(desktopSessionID: identifier)
        }
        return found
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

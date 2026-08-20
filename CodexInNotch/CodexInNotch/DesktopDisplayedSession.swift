import Darwin
import Foundation
import os

/// What Claude Desktop says is on its screen, **including when the answer is
/// nothing at all**.
///
/// **Why this exists.** Every route that retires a finished Claude Code row
/// rests on one claim: *this session is the one Claude Desktop has on screen*
/// (ADR 0012, 第二、三、四条). That claim was answered by the newest
/// `lastFocusedAt` in Desktop's own records, and those records only ever record
/// a session **being put** on screen -- never one being taken off. So the
/// moment the user navigates to something that is not a session, the newest
/// stamp goes on naming a session that is no longer in front of anybody, and it
/// is the composer for a *new* session that most often does it.
///
/// Measured on this machine, 2026-08-19, with a finished row that nobody read:
///
/// | time | what happened | what the records say |
/// | --- | --- | --- |
/// | 21:02:30 | the user switches to session A | `lastFocusedAt` ← now |
/// | 21:03:30 | the user opens the composer for a new session | **nothing at all** |
/// | 21:03:58 | A's Turn ends | the row goes Completed, and this app still believes A is on screen |
/// | 21:04:18 | the user sends the new session's first message | that session is displayed, A is "moved on from", **and the row is retired as read** |
///
/// The row left on the gesture that started an unrelated session, and the user
/// never saw the answer. The same stale claim retires the row even earlier when
/// Claude Desktop happens to hold the front while the composer is open
/// (第三条), and hands an activation to the wrong session when the user comes
/// back to the composer to send (第二条).
///
/// **What answers it.** Claude Desktop states the transition itself, in its own
/// log, and states it in both directions -- which is the correction to the note
/// in ADR 0012 第三条 that the log was "`lastFocusedAt` 盖章时刻的子集". It is a
/// superset in the one direction that matters:
///
/// ```js
/// setFocusedSession(e){ log.info(`[CCD] LocalSessions.setFocusedSession: sessionId=${e ?? `null`}`), … }
/// ```
///
/// (Claude Desktop `1.32885.1`.) The call is made on every navigation, the
/// `info` is unconditional, and `null` is exactly the case the records cannot
/// write down.
///
/// **It may only ever keep a row listed.** The wiring in
/// ``ClaudeCodeMonitorService`` treats this as a veto over the records and
/// never as a source of its own: a session is on screen only when the records
/// and this agree, and ``DesktopDisplayedSession/unknown`` is the behaviour the
/// app had before this existed. A log that is missing, unreadable, rotated, or
/// written by some future Desktop in a shape this cannot parse therefore
/// degrades to that behaviour rather than retiring anything early.
nonisolated protocol DesktopDisplayedSessionReporting: Sendable {
    func displayedSession() async -> DesktopDisplayedSession
}

/// One statement by Claude Desktop about what it has on screen.
nonisolated enum DesktopDisplayedSession: Equatable, Sendable {
    /// Desktop's own id for the session it put there -- `local_<uuid>` for a
    /// session it hosts, and other shapes for the ones it does not (a cloud
    /// session is `session_<id>`). Carried verbatim, and joined to the id the
    /// hooks carry through Desktop's own records; an id that joins to nothing
    /// is a session none of these rows belong to.
    case session(desktopSessionID: String)
    /// Something that is not a session: the composer for a new one, the home
    /// view, a settings pane. **No session is on screen**, which is a claim the
    /// records cannot make.
    case nothing
    /// Nothing has said anything this app is willing to believe. The state a
    /// freshly launched app is in, and the state a log it cannot read leaves it
    /// in.
    case unknown
}

/// Claude Desktop's own log, read from the end and only forwards.
///
/// **Only what was appended while this app was watching counts as a
/// statement.** `AGENTS.md` §6.2 says business state comes from a current
/// snapshot or from live events observed since this process started, and a log
/// line written last Tuesday is neither. The tail that was already there when
/// this app started is read exactly once, and it is allowed to say one thing
/// and one thing only: ``DesktopDisplayedSession/nothing``. That direction can
/// only keep a row listed, so believing it costs nothing the product is not
/// already willing to pay; a *positive* claim out of history is the mistake
/// §6.2 names, and answers ``DesktopDisplayedSession/unknown`` instead.
///
/// **No change stream of its own, deliberately.** Every transition that can
/// *retire* a row already arrives on another edge -- Desktop writes the record
/// of the session it just displayed, and a session starting fires hooks. The
/// transition only this file can see is the one into a composer, and that one
/// only ever keeps a row, which a listed row's own
/// ``MonitorTiming/terminalUnreadRecheckInterval`` re-check picks up within a
/// second. Watching the file instead would buy a wake-up for every line Claude
/// Desktop logs -- oauth lookups, git diff timings -- and none of them mean
/// anything here.
///
/// **What it reads.** `~/Library/Logs/Claude/main.log`, a bounded chunk from
/// the end, matching one line shape and decoding one field out of it. No other
/// line is parsed, nothing is written, and the file is rejected outright unless
/// it is a regular file owned by this user.
actor ClaudeDesktopFocusLogReader: DesktopDisplayedSessionReporting {
    private static let log = Logger(
        subsystem: "com.yinfenglu.CodexInNotch",
        category: "ClaudeDesktopFocusLog"
    )

    /// An override for tests and for an install somewhere unusual, the way
    /// `CODEX_IN_NOTCH_CLAUDE_DESKTOP_HOME` points at Desktop's state tree.
    nonisolated static let logOverrideKey = "CODEX_IN_NOTCH_CLAUDE_DESKTOP_LOG"

    nonisolated private static let statement =
        "[CCD] LocalSessions.setFocusedSession: sessionId="
    /// What Claude Desktop writes when what is on screen is not a session.
    nonisolated private static let nothingOnScreen = "null"
    /// A ceiling on one reading, in bytes.
    ///
    /// The log grows by roughly 800 KiB a day on this machine, and a listed
    /// finished row re-reads it once a second, so this is orders of magnitude
    /// more than any refresh can find. It is here for the one case that is not
    /// a refresh: the first reading of a log that has been accumulating since
    /// the user installed Claude Desktop.
    nonisolated private static let maximumRead = 256 * 1_024
    /// Longer than any id Desktop has ever written, and short enough that a
    /// line this app has misunderstood cannot be carried around as one.
    nonisolated private static let maximumIdentifierLength = 200
    nonisolated private static let newline = UInt8(ascii: "\n")

    private struct FileRevision: Equatable {
        let size: UInt64
        let fileNumber: UInt64?
    }

    private let url: URL
    private let fileManager: FileManager
    /// Where the next reading starts, and which file that offset belongs to.
    /// `nil` for a log this app has not looked at yet -- see ``seed(upTo:)``.
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
            // Gone, unreadable, or not a plain file this user owns. The last
            // statement stands; only the place being read from is forgotten,
            // so a log that comes back is picked up from its current end
            // rather than replayed.
            offset = nil
            fileNumber = nil
            return current
        }

        if let offset, fileNumber == revision.fileNumber, offset <= revision.size {
            // Appended while this app was watching, so it may say anything.
            let start = max(offset, Self.floor(under: revision.size))
            let read = read(from: start, upTo: revision.size)
            if let statement = Self.lastStatement(in: read.completeLines) {
                current = statement
            }
            // Only up to the last newline: a line still being written has its
            // tail missing, and half an id is not a statement about anything.
            self.offset = start + UInt64(read.consumed)
        } else {
            // A log this app has not been watching: its first reading, or one
            // that was rotated or truncated underneath it. Everything in it is
            // history, and history may only ever say `nothing`.
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

    /// The earliest offset a reading of a file this size may start at.
    ///
    /// Written as a comparison rather than a subtraction because these are
    /// unsigned: a log smaller than one chunk would otherwise wrap rather than
    /// start at nought.
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

    /// The newest statement in a chunk, or nil when it carries none.
    ///
    /// Later lines win outright. A chunk that begins mid-line loses the *head*
    /// of that line, never its tail, so the id in it is intact whether or not
    /// the timestamp in front of it is.
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

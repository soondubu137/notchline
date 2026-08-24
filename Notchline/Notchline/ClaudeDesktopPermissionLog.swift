import Foundation
import os

/// When Claude Desktop last recorded a human answering one of its permission
/// dialogs, per Desktop session.
nonisolated protocol DesktopPermissionResponseReporting: Sendable {
    /// - Returns: Desktop session id to the newest instant a dialog of that
    ///   session was answered. A session that has never had one is absent, and
    ///   absent is never evidence of anything.
    func answeredAt() async -> [String: Date]
}

/// The desktop half of "the human has answered", read out of Claude Desktop's
/// own log.
///
/// **Why this exists at all.** Claude Code fires no hook when a person approves
/// a permission request. Measured 2026-08-23 against CLI 2.1.241 with *all
/// thirty-one* hook events registered on a throwaway settings file: between the
/// `PermissionRequest` that opened the dialog and the call's own `PostToolUse`
/// twenty-six seconds later, the only event of any kind was an unrelated
/// agent's `SubagentStop`. There is no approval hook to miss -- so the wait can
/// only be closed by evidence that is not a hook event, and the two products
/// keep that evidence in different places.
///
/// A terminal-hosted session answers for itself: it publishes `busy` again the
/// moment the dialog goes away, which is what
/// ``HookEventRepository/endAnsweredApprovalWaits(_:)`` reads. **A
/// desktop-hosted session publishes no status at all** -- the terminal
/// interface writes that field and Claude Desktop runs the CLI as a
/// `stream-json` subprocess with no terminal interface, so its
/// `~/.claude/sessions/<pid>.json` never grows one (measured the same day: the
/// desktop-hosted record carries `entrypoint: "claude-desktop"` and no
/// `status`, `updatedAt` or `statusUpdatedAt`, and is not rewritten after the
/// session starts). That is the same shape as CC-022 / #41, and it is answered
/// the same way ADR 0011 answered it there: with a second, differently-shaped
/// piece of evidence that the desktop app leaves behind.
///
/// **What it leaves behind.** Claude Desktop logs both ends of every dialog it
/// raises, with an id joining them:
///
/// ```text
/// 18:10:40 Emitted tool permission request c930390d-… for Bash in session local_6c63f909-…
/// 18:10:45 LocalSessions.respondToToolPermission: requestId=c930390d-…, decision=once, …
/// 18:10:45 Received permission response for c930390d-…: once (tool: Bash)
/// ```
///
/// Only the first line names the session, and only the last proves a human
/// answered, so the request id is what pairs them -- the same shape the reducer
/// already uses to pair `PermissionRequest` with the call it is asking about. A
/// response whose opening line is not in the window read is never attributed to
/// anything; a wait left standing is the direction this fails in.
///
/// **The decision is deliberately not read.** `once`, an always-allow, or a
/// refusal are all a human answering, and the wait is over either way. Reading
/// it would also be the first time this app took an interest in *what* the user
/// decided, which is not a question it has any business asking.
///
/// **What it reads.** `~/Library/Logs/Claude/main.log`, a bounded chunk from
/// the end, matching two line shapes and decoding an id, a session and a
/// timestamp out of them. No other line is parsed, nothing is written, and the
/// file is rejected outright unless it is a regular file owned by this user --
/// all of it exactly as ``ClaudeDesktopFocusLogReader`` treats the same file.
///
/// **Its own cursor, not that one's.** Two questions over one file cannot share
/// an offset: whichever asked first would consume the lines the other needed.
/// The cost is a second bounded read of a file already in the page cache.
actor ClaudeDesktopPermissionLogReader: DesktopPermissionResponseReporting {
    private static let log = Logger(
        subsystem: "com.yinfenglu.Notchline",
        category: "ClaudeDesktopPermissionLog"
    )

    nonisolated private static let requestStatement = "Emitted tool permission request "
    nonisolated private static let requestSessionMarker = " in session "
    nonisolated private static let responseStatement = "Received permission response for "
    /// A ceiling on one reading, in bytes. The same figure
    /// ``ClaudeDesktopFocusLogReader`` uses, and for the same reason: the log
    /// grows by roughly 800 KiB a day here, so this is far more than any
    /// refresh can find and exists for the first reading of a log that has been
    /// accumulating since Claude Desktop was installed.
    nonisolated private static let maximumRead = 256 * 1_024
    /// Longer than any id Desktop has ever written, short enough that a line
    /// this app has misunderstood cannot be carried around as one.
    nonisolated private static let maximumIdentifierLength = 200
    /// How many unanswered dialogs to remember the session of.
    ///
    /// A dialog is answered seconds after it is raised, so this is orders of
    /// magnitude more than the one or two ever open at once. It is a bound on a
    /// table fed by a file this app does not control, not a working size.
    nonisolated private static let maximumTrackedRequests = 256
    /// How many sessions to remember an answer for. Bounded for the same
    /// reason, and larger than any plausible number of live Desktop sessions.
    nonisolated private static let maximumTrackedSessions = 128
    nonisolated private static let newline = UInt8(ascii: "\n")
    /// The stamp every line of this log begins with: local time, one-second
    /// resolution, no zone. Parsed in the machine's own zone because that is
    /// what wrote it.
    nonisolated private static let timestampLength = 19

    private struct FileRevision: Equatable {
        let size: UInt64
        let fileNumber: UInt64?
    }

    private let url: URL
    private let fileManager: FileManager
    private var offset: UInt64?
    private var fileNumber: UInt64?
    /// Desktop session id to the newest answer seen for it.
    ///
    /// **Sticky, and that is the point.** A reading is not the only thing that
    /// happens between an answer and the next time a row is built, so an answer
    /// that is only reported once could be reported into a refresh that had not
    /// yet drained the event opening the wait. Held instead, it is compared
    /// against each wait's own opening instant every refresh, and the
    /// comparison is what makes reporting it twice harmless.
    private var answeredByDesktopSessionID: [String: Date] = [:]
    /// The order those were learned in, oldest first, for eviction.
    private var answeredOrder: [String] = []
    /// Request id to the Desktop session that raised it.
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
            // Gone, unreadable, or not a plain file this user owns. What has
            // already been learned stands -- losing the file does not unsay an
            // answer -- and only the place being read from is forgotten, so a
            // log that comes back is picked up from its current end.
            offset = nil
            fileNumber = nil
            return answeredByDesktopSessionID
        }

        let start: UInt64
        if let offset, fileNumber == revision.fileNumber, offset <= revision.size {
            start = max(offset, Self.floor(under: revision.size))
        } else {
            // A log this app has not been watching: its first reading, or one
            // rotated or truncated underneath it. Its tail is read like any
            // other chunk rather than being treated as history, because
            // nothing here is believed on its own -- every answer is held
            // against the opening instant of the wait it would close, and an
            // answer older than the dialog is refused by that comparison
            // whether it came from history or from a moment ago.
            start = Self.floor(under: revision.size)
        }
        let read = read(from: start, upTo: revision.size)
        consume(read.completeLines)
        // Only up to the last newline: a line still being written has its tail
        // missing, and half an id is not a statement about anything.
        self.offset = start + UInt64(read.consumed)
        fileNumber = revision.fileNumber
        return answeredByDesktopSessionID
    }

    /// The earliest offset a reading of a file this size may start at.
    ///
    /// A comparison rather than a subtraction because these are unsigned: a log
    /// smaller than one chunk would otherwise wrap rather than start at nought.
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

    /// Reads both line shapes out of one chunk, in the order they were written.
    ///
    /// Order matters here in a way it does not for the focus reader: a response
    /// can only be attributed to the session its own opening line named, so the
    /// opening line has to have been seen first. A chunk that begins mid-line
    /// loses the head of that line, which is where both the timestamp and the
    /// statement live, so such a line matches nothing and is skipped.
    private func consume(_ data: Data) {
        for line in data.split(separator: Self.newline, omittingEmptySubsequences: true) {
            let text = String(decoding: line, as: UTF8.self)
            if let opened = Self.request(in: text) {
                remember(request: opened.requestID, of: opened.desktopSessionID)
            } else if let answered = Self.response(in: text),
                      let desktopSessionID = sessionByRequestID[answered.requestID] {
                // The dialog is over, so the pairing has done its job. Dropped
                // rather than kept, which is also what keeps the table small
                // without relying on the eviction bound.
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
        // `… request <id> for <tool> in session <desktop id>`. The tool is
        // between them and is deliberately not read: the reducer already knows
        // which call it is holding, and a second opinion out of a log would
        // only be a way to disagree with it.
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
        // `… response for <id>: <decision> (tool: <name>)`. Everything after
        // the colon is the user's decision, and this app does not read it: any
        // answer ends the wait.
        let requestID = text[marker.upperBound...]
            .prefix { $0 != ":" && !$0.isWhitespace }
        guard isIdentifier(requestID) else { return nil }
        return (String(requestID), at)
    }

    /// The stamp at the head of a log line, in the zone that wrote it.
    ///
    /// One-second resolution, which is coarser than the hook arrival instants
    /// it is compared against -- and coarse in the safe direction, because
    /// truncating an answer towards the past can only make it look older than
    /// the dialog it closes and be refused.
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
        // Monotonic, like every other stamp this app keeps: a line read out of
        // order must not wind an answer backwards.
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

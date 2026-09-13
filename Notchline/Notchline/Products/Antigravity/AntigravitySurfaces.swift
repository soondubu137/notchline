import Foundation

/// Which of Antigravity's two surfaces a conversation is running on.
///
/// **One product, two surfaces**, the way Claude Code is one product with a
/// desktop host and a terminal host. Antigravity CLI (`agy`) and Antigravity
/// Desktop are the same engine: measured 2026-09-12, Desktop 2.13.0's
/// `language_server` and `agy` 1.2.2 carry the same hook executors, the same
/// transcript writer and the same RPC surface, read the same
/// `~/.gemini/config/` (hooks, projects, MCP servers), and send the same
/// payloads to the same registration. What differs is everything around a
/// Turn — whether it is open, what it belongs to, whether it has been read,
/// where a click goes — and that is what this value selects between.
nonisolated enum AntigravitySurface: Sendable, Equatable {
    /// `agy`, in a terminal or under `-p`.
    case cli
    /// Antigravity Desktop, `com.google.antigravity`.
    case desktop

    /// The surface a payload's transcript path names, or nil for a sibling
    /// product's.
    ///
    /// The engine's own guide says the transcript's state directory is the one
    /// thing that differs by surface — `antigravity-cli/`, `antigravity/`,
    /// `antigravity-ide/` — and nothing else in a payload does. The directory
    /// is taken as the component under `.gemini`, rather than found anywhere in
    /// the path, so a workspace folder that happens to be called `antigravity`
    /// cannot decide it.
    ///
    /// A payload naming no transcript at all is the CLI's, which is how every
    /// such payload was treated before a second surface existed.
    init?(transcriptPath: String?) {
        guard let transcriptPath else {
            self = .cli
            return
        }
        let components = transcriptPath.split(separator: "/")
        let stateDirectory: Substring?
        if let gemini = components.lastIndex(of: ".gemini"), gemini + 1 < components.count {
            stateDirectory = components[gemini + 1]
        } else {
            stateDirectory = components.last { $0 == "antigravity-cli" || $0 == "antigravity" || $0 == "antigravity-ide" }
        }
        switch stateDirectory {
        case "antigravity-cli":
            self = .cli
        case "antigravity":
            self = .desktop
        default:
            return nil
        }
    }
}

/// Which surface each conversation this process has seen belongs to.
///
/// Written by ``AntigravityPayloadTranslator`` for every event it accepts, and
/// read by the sources that treat the surfaces differently. A conversation is
/// on exactly one surface: Desktop 2.13.0 lists none of the CLI's
/// conversations (its sidebar's `CLI Project` reads `No conversations yet`, and
/// its server logs `failed to load external trajectory` for each), so a
/// conversation id never moves between them. Unrecorded is the CLI, for the
/// same reason as a payload with no transcript.
nonisolated final class AntigravitySurfaceLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var surfaces: [String: AntigravitySurface] = [:]

    init() {}

    func record(_ surface: AntigravitySurface, forConversation conversationID: String) {
        lock.lock()
        surfaces[conversationID] = surface
        lock.unlock()
    }

    func surface(ofConversation conversationID: String) -> AntigravitySurface {
        lock.lock()
        defer { lock.unlock() }
        return surfaces[conversationID] ?? .cli
    }
}

/// Whether Antigravity is open and which conversations it vouches for, across
/// both surfaces, from one reading of each.
///
/// - **The CLI** answers from the presence locks its `agy` processes hold
///   (``AntigravityConversationScanner``): a conversation is live while a
///   process holds its lock.
/// - **Desktop** answers from whether its application is running. It keeps
///   every conversation in one long-lived `language_server` and holds no lock
///   per conversation, so while it runs it vouches for every conversation this
///   app has observed on it, and once it has quit for none of them — the
///   Desktop half of the list is ADR 0017's "every observed Thread", bounded
///   by the application's life. A Desktop Turn left `Running` by a quit is
///   retired by the next reading rather than left claiming work.
///
/// The product is open while either surface is.
final class AntigravitySessions: ProductSessionReading, SessionProcessLocating, @unchecked Sendable {
    let cli: AntigravityConversationScanner
    private let desktop: any AntigravityDesktopLocating
    private let surfaces: AntigravitySurfaceLedger

    init(
        cli: AntigravityConversationScanner,
        desktop: any AntigravityDesktopLocating,
        surfaces: AntigravitySurfaceLedger
    ) {
        self.cli = cli
        self.desktop = desktop
        self.surfaces = surfaces
    }

    func read(observing state: HookStateSnapshot) async -> SessionReading {
        let reading = cli.read()
        let desktopIsRunning = await desktop.runningApplication() != nil
        guard reading.listedAnything else {
            // The kernel would not list processes, so nothing the CLI runs can
            // be vouched for or retired. Desktop's own answer still stands for
            // whether the product is open.
            return SessionReading(presence: desktopIsRunning ? .open : .unknown, admission: .unknown)
        }
        let cliConversations = Set(reading.conversations.map(\.conversationID))
        let desktopConversations: Set<String> = desktopIsRunning
            ? Set(state.turns.map(\.threadID).filter { surfaces.surface(ofConversation: $0) == .desktop })
            : []
        return SessionReading(
            presence: cliConversations.isEmpty && !desktopIsRunning ? .closed : .open,
            admission: .exactly(cliConversations.union(desktopConversations), readAt: reading.readAt)
        )
    }

    func stopWatching() async {}

    /// The CLI process running a conversation. A Desktop conversation has
    /// none: its engine is shared by every conversation and has no terminal,
    /// so neither the terminal's read evidence nor its tab route applies.
    func processIdentifier(forThreadID threadID: String) async -> Int32? {
        guard surfaces.surface(ofConversation: threadID) == .cli else { return nil }
        return await cli.processIdentifier(forThreadID: threadID)
    }
}

/// Each row's project, title and line: the working directory's name for a CLI
/// conversation, and Desktop's own Project assignment for a Desktop one.
///
/// **Desktop owns its Projects**, so a folder name is not allowed to stand in
/// for one (`docs/product-support.md` §2, L2). A Desktop Project is a named
/// object the user creates, renames and files conversations under; a
/// conversation can sit in none (Desktop's own sidebar calls that
/// `Standalone`), and two Projects can share a folder. The CLI has no such
/// object — its conversations are filed under Desktop's `CLI Project`
/// placeholder whatever folder they ran in — so its row keeps the folder.
///
/// Title and line are the same for both surfaces: the prompt and the model's
/// words from the transcript.
struct AntigravityRowContent: RowContentSource {
    let surfaces: AntigravitySurfaceLedger
    let projects: any AntigravityDesktopProjectResolving

    func content(
        for turns: [HookTurnState],
        messages: TurnMessageReading
    ) async -> [String: RowContent] {
        var content = await WorkingDirectoryRowContent().content(for: turns, messages: messages)
        for turn in turns where surfaces.surface(ofConversation: turn.threadID) == .desktop {
            guard let row = content[turn.threadID] else { continue }
            content[turn.threadID] = RowContent(
                projectName: projects.resolution(forConversation: turn.threadID).displayName,
                title: row.title,
                preview: row.preview
            )
        }
        return content
    }
}

/// Whether a finished Antigravity row has been read: at its terminal, for a
/// CLI conversation, and by Desktop's own record, for a Desktop one.
///
/// The terminal half is ``TerminalReadEvidence`` unchanged. The Desktop half is
/// the product's read record, and the rule is the one Desktop's own sidebar
/// applies to draw its unread dot: a conversation is unread when it has been
/// marked unread, or when it changed after it was last viewed
/// (``AntigravityDesktopReadRecord``). Here "changed" is this Turn's end.
struct AntigravityReadEvidence: ReadEvidenceSource {
    let surfaces: AntigravitySurfaceLedger
    let terminal: TerminalReadEvidence
    let desktopRecords: any AntigravityDesktopReadRecordReading
    /// The terminal half's, so the two halves wait on one screen.
    let screen: any ScreenAvailabilityReporting

    init(
        surfaces: AntigravitySurfaceLedger,
        terminal: TerminalReadEvidence,
        desktopRecords: any AntigravityDesktopReadRecordReading = AntigravityDesktopReadRecords()
    ) {
        self.surfaces = surfaces
        self.terminal = terminal
        self.desktopRecords = desktopRecords
        screen = terminal.screen
    }

    func verdicts(for candidates: [ReadGateCandidate], now: Date) async -> ReadEvidenceJudgement {
        var desktopCandidates: [ReadGateCandidate] = []
        var cliCandidates: [ReadGateCandidate] = []
        for candidate in candidates {
            if surfaces.surface(ofConversation: candidate.row.threadID) == .desktop {
                desktopCandidates.append(candidate)
            } else {
                cliCandidates.append(candidate)
            }
        }
        let terminalJudgement = await terminal.verdicts(for: cliCandidates, now: now)
        var verdicts = terminalJudgement.verdicts
        for candidate in desktopCandidates {
            verdicts[candidate.row.id] = desktopVerdict(for: candidate, now: now)
        }
        return ReadEvidenceJudgement(verdicts: verdicts, diagnostic: terminalJudgement.diagnostic)
    }

    func forget() async {
        await terminal.forget()
    }

    /// Desktop's record of one finished Turn.
    ///
    /// A record that is missing or unreadable is a question with no answer, so
    /// the row is kept out of the gate rather than re-asked once a second
    /// (CR-Fable-036): Desktop writes the record when a conversation is
    /// submitted to, so a finished Turn without one is not waiting on a write.
    func desktopVerdict(for candidate: ReadGateCandidate, now: Date) -> ReadGateVerdict {
        guard TerminalUnreadMembershipGate.isTerminal(
            MonitorAggregation.effectiveStatus(of: candidate.row)
        ) else {
            return .judged(by: TerminalReadEvidence.reading(unread: [], at: now))
        }
        guard let record = desktopRecords.record(forConversation: candidate.row.threadID) else {
            return .cannotBeAsked
        }
        let read = !record.markedAsUnread
            && (record.lastViewedAt.map { $0 >= candidate.turnEndedAt } ?? false)
        return .judged(
            by: TerminalReadEvidence.reading(unread: read ? [] : [candidate.row.threadID], at: now)
        )
    }
}

/// Takes an Antigravity row back to where its conversation is: the terminal
/// running `agy`, or Antigravity Desktop.
///
/// **Desktop is raised, not reopened on the conversation.** Its application
/// handles exactly one deep link, `antigravity://teleport/ai_studio`
/// (measured in 2.13.0's renderer bundle: the handler checks that host and
/// path and ignores every other URL), so no supported route selects a
/// conversation, and the outcome says the session itself was not reached.
/// Raising it is still worth more than it sounds: Desktop records a
/// conversation as viewed when its window regains focus on it, so a click
/// that lands on the conversation already on screen reads it.
@MainActor
final class AntigravityNavigator: AgentNavigating {
    private let surfaces: AntigravitySurfaceLedger
    private let desktop: any AntigravityDesktopLocating
    private let terminal: any AgentNavigating
    private let activator: any HostApplicationActivating

    init(
        surfaces: AntigravitySurfaceLedger,
        desktop: any AntigravityDesktopLocating,
        terminal: any AgentNavigating,
        activator: (any HostApplicationActivating)? = nil
    ) {
        self.surfaces = surfaces
        self.desktop = desktop
        self.terminal = terminal
        self.activator = activator ?? AppKitHostApplicationActivator()
    }

    @discardableResult
    func open(_ session: MonitoredSession) async throws -> NavigationOutcome {
        guard surfaces.surface(ofConversation: session.threadID) == .desktop else {
            return try await terminal.open(session)
        }
        guard let application = await desktop.runningApplication() else {
            throw ProcessHostNavigationError.sessionGone
        }
        guard await activator.activate(application) else {
            throw ProcessHostNavigationError.activationFailed(application.displayName)
        }
        return .raisedApplication(host: application.displayName)
    }
}

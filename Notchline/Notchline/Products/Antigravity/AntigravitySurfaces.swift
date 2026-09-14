import Foundation

/// Which of Antigravity's two surfaces a conversation runs on. `agy` 1.2.2 and Desktop 2.13.0
/// are one engine with the same hooks, transcripts and payloads (measured 2026-09-12); they
/// differ around a Turn.
nonisolated enum AntigravitySurface: Sendable, Equatable {
    /// `agy`, in a terminal or under `-p`.
    case cli
    /// Antigravity Desktop, `com.google.antigravity`.
    case desktop

    /// The surface a transcript path names, or nil for a sibling product's. Only the component
    /// under `.gemini` counts, so a workspace named `antigravity` cannot decide it. No path: CLI.
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

/// Which surface each conversation seen belongs to. A conversation never moves (Desktop 2.13.0
/// lists none of the CLI's); unrecorded means the CLI.
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

/// Whether Antigravity is open and which conversations it vouches for. CLI: a conversation is
/// live while an `agy` process holds its lock. Desktop has no per-conversation lock, so while
/// it runs it vouches for every conversation observed on it (ADR 0017), and none once it quits.
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
            // Processes could not be listed: nothing CLI is vouched for or retired.
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

    /// Nil for Desktop, whose shared engine has no terminal.
    func processIdentifier(forThreadID threadID: String) async -> Int32? {
        guard surfaces.surface(ofConversation: threadID) == .cli else { return nil }
        return await cli.processIdentifier(forThreadID: threadID)
    }
}

/// A CLI row's project is its working directory's name; a Desktop row's is Desktop's own
/// Project, never a folder (`docs/product-support.md` §2, L2). Title and line: the transcript.
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

/// CLI rows use ``TerminalReadEvidence``; Desktop rows use its sidebar's rule: marked unread, or
/// the Turn ended after the last view.
struct AntigravityReadEvidence: ReadEvidenceSource {
    let surfaces: AntigravitySurfaceLedger
    let terminal: TerminalReadEvidence
    let desktopRecords: any AntigravityDesktopReadRecordReading
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

    /// A missing or unreadable record keeps the row out of the gate (CR-Fable-036): Desktop writes
    /// it on submit, so none is coming.
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

/// Takes an Antigravity row back to the terminal running `agy`, or raises Desktop. Desktop
/// 2.13.0 handles only `antigravity://teleport/ai_studio`, so no route selects a conversation;
/// regaining focus still records the on-screen conversation as viewed.
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

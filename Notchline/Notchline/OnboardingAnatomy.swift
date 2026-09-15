// The first-run window's two drawings and their pins (`figma-design.md` §7). Specimens are the
// real `NotchOverlayView` over a fixed-snapshot `MonitorStore`, so they cannot drift.
import Combine
import SwiftUI

/// The fixed moment both specimens draw, so bar and panel are the same instant. Only the elapsed
/// reading moves.
@MainActor
enum NotchSpecimen {
    /// A `46` pt menu bar and no notch: the pill is self-contained and carries the status name, so
    /// it teaches best inside a window. The parts are identical on both forms.
    static let display = DisplayOption(
        id: "specimen",
        displayID: nil,
        ordinal: 1,
        name: "Specimen",
        frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: NSRect(
            x: 0,
            y: 0,
            width: 1440,
            height: 900 - PanelMetrics.referenceCompactHeight
        ),
        safeAreaInsets: NSEdgeInsets(),
        auxiliaryTopLeftArea: nil,
        auxiliaryTopRightArea: nil,
        fallbackMenuBarHeight: PanelMetrics.referenceCompactHeight
    )

    /// One tuple so both stores share one `Date()`, are re-staged together, and the wrap knows when.
    /// Lazy, so a first run that never reaches page two builds no store.
    private static var staged: (at: Date, shut: MonitorStore, hovered: MonitorStore) = {
        let now = Date()
        return (
            at: now,
            shut: makeStore(isExpanded: false, at: now),
            hovered: makeStore(isExpanded: true, at: now)
        )
    }()

    static var shut: MonitorStore { staged.shut }

    /// The staged moment with the panel open.
    static var hovered: MonitorStore { staged.hovered }

    /// Both specimens' sessions, one list per product.
    ///
    /// - Codex head row: an answerable approval (bar says `Approval needed`, row draws `Approve`).
    /// - Three Codex turns finished and unread: the shut bar's breathing dot.
    /// - Second Codex turn finished with subagents working: the badge row; keeps the mark on radar.
    /// - One Claude Code row: two headings plus three rows fill the `32 + 240 + 32` viewport.
    /// - A sixth Codex turn departs for the Recent seam (`expanded-panel-v2.md` §2.1);
    ///   `includingDeparted` selects that list.
    private static func sessions(
        at now: Date,
        includingDeparted: Bool = false
    ) -> [AgentKind: [MonitoredSession]] {
        [
            .codex: [
                approvalRow(at: now),
                subagentRow(at: now),
                finished(
                    id: "audit",
                    title: "Audit the hook payload paths",
                    preview: "Both products reach the reducer.",
                    at: now,
                    endedAgo: 540
                )
            ]
                + (includingDeparted ? [departing(at: now)] : []),
            .claudeCode: [
                finished(
                    agent: .claudeCode,
                    id: "edges",
                    title: "Keep the collapsed bar's edges still",
                    preview: "The trailing slot is billed for a fixed width.",
                    at: now,
                    endedAgo: 1_260
                )
            ]
        ]
    }

    /// Finished with subagents still working: `Running` to the summary and sort
    /// (``MonitorAggregation/effectiveStatus(of:)``), `Completed` itself.
    ///
    /// Codex's, because grouped by product a Claude Code row here sorted below the fold.
    private static func subagentRow(at now: Date) -> MonitoredSession {
        MonitoredSession(
            agent: .codex,
            threadID: "specimen-subagents",
            turnID: "specimen-subagents-turn",
            projectName: "notchline",
            title: "Validate the notch positioning",
            preview: "Positioning tests pass on this Mac.",
            status: .completed,
            startedAt: now.addingTimeInterval(-247),
            runningSubagentCount: 4,
            finishedAt: now.addingTimeInterval(-96)
        )
    }

    /// The head row: stopped on an approval. Page two draws it shut and page three open, both
    /// reading title, preview and request from here.
    private static func approvalRow(at now: Date) -> MonitoredSession {
        MonitoredSession(
            agent: .codex,
            threadID: "specimen-codex-approval",
            turnID: "specimen-codex-approval-turn",
            projectName: "notchline",
            title: "Wire the quota footer to the fold control",
            preview: "Reading PanelMetrics to find the trailing slot.",
            status: .approvalNeeded,
            // The clock this window teaches from (``clockPeriod``). An approval keeps timing
            // (`SessionStatus.keepsTiming`), so the collapsed reading still draws it.
            startedAt: now,
            runningSubagentCount: 3,
            request: approval
        )
    }

    /// ``AgentRequest/canBeAnswered`` needs a `replyTicket` (`answer-in-notch.md` §11 rule 03), so this
    /// carries one that leads nowhere; ``NotchSpecimenView`` disables hit testing.
    private static let approval = AgentRequest(
        id: "specimen-codex-approval-request",
        toolName: "Bash",
        form: .command("swiftformat Notchline/Notchline/MonitorStore.swift"),
        answerHandle: AnswerHandle(ticket: 0)
    )

    /// The row that leaves, so the panel has a Recent seam. Finished on a connected product: the
    /// ordinary `read` arrow (``MonitorStore/departureReason(for:connectedAgents:)``).
    private static func departing(at now: Date) -> MonitoredSession {
        finished(
            id: "departed",
            title: "Name every quota window as its product does",
            preview: "Both tables read the way each product writes them.",
            at: now,
            endedAgo: 3_300
        )
    }

    private static func finished(
        agent: AgentKind = .codex,
        id: String,
        title: String,
        preview: String?,
        at now: Date,
        endedAgo: TimeInterval
    ) -> MonitoredSession {
        MonitoredSession(
            agent: agent,
            threadID: "specimen-codex-\(id)",
            turnID: "specimen-codex-\(id)-turn",
            projectName: "notchline",
            title: title,
            preview: preview,
            status: .completed,
            startedAt: now.addingTimeInterval(-endedAgo - 90),
            finishedAt: now.addingTimeInterval(-endedAgo)
        )
    }

    /// Every product's answer at one instant: what both stores are built from and ``cycle()``
    /// restages.
    private static func snapshots(
        at now: Date,
        includingDeparted: Bool = false
    ) -> [AgentSnapshot] {
        let rows = sessions(at: now, includingDeparted: includingDeparted)
        let quotas = quota(at: now)
        return [AgentKind.codex, .claudeCode].map { agent in
            AgentSnapshot(
                agent: agent,
                availability: .ready,
                sessions: rows[agent] ?? [],
                quota: quotas[agent] ?? .unavailable,
                diagnostic: nil,
                setupStatus: .active,
                presence: .open
            )
        }
    }

    /// Codex publishes one window, Claude Code two. Resets are relative to the staged instant.
    private static func quota(at now: Date) -> [AgentKind: QuotaSnapshot] {
        [
            .codex: QuotaSnapshot(
                windows: [
                    QuotaWindow(
                        label: "Weekly limit",
                        remainingPercent: 72,
                        resetsAt: now.addingTimeInterval(3 * 86_400 + 12 * 3_600)
                    )
                ],
                todayTokens: 310_100_000
            ),
            .claudeCode: QuotaSnapshot(
                windows: [
                    QuotaWindow(
                        label: "Current session",
                        remainingPercent: 40,
                        resetsAt: now.addingTimeInterval(2 * 3_600 + 34 * 60)
                    ),
                    QuotaWindow(
                        label: "All models",
                        remainingPercent: 87,
                        resetsAt: now.addingTimeInterval(3 * 86_400 + 11 * 3_600)
                    ),
                    QuotaWindow(
                        label: "Fable",
                        remainingPercent: 96,
                        resetsAt: now.addingTimeInterval(3 * 86_400 + 11 * 3_600)
                    )
                ],
                todayTokens: 208_600_000
            )
        ]
    }

    /// Belongs to the reading page; building it must not construct the answer examples.
    private static var recent: MonitorStore?

    static var recentQueue: MonitorStore {
        if let recent { return recent }
        let now = Date()
        let store = makeStore(isExpanded: true, at: now)
        store.isRecentExpanded = true
        store.stageSpecimenQueue(departedQueue(at: now))
        recent = store
        return store
    }

    // MARK: - Page three: answering requests

    /// The page-three examples and the instant they share. Built on first visit to page three;
    /// question variants stay isolated, and the cache is separate from the Recent queue.
    private static var opened: Opened?

    struct Opened {
        /// A permission request, open: the row page two draws shut.
        let command: MonitorStore
        let question: MonitorStore
        let multipleChoice: MonitorStore
        let typedAnswer: MonitorStore
    }

    static func openedSpecimens() -> Opened {
        if let opened { return opened }
        let built = makeOpened(at: Date())
        opened = built
        return built
    }

    private static func makeOpened(at now: Date) -> Opened {
        let command = makeStore(isExpanded: true, at: now, sessions: [approvalRow(at: now)])
        command.toggleOpenRow(approvalRow(at: now))

        func questionStore(
            multiple: Bool,
            selected: Set<Int>? = nil,
            draft: String = ""
        ) -> MonitorStore {
            let asked = questionRow(at: now, multiple: multiple)
            let store = makeStore(isExpanded: true, at: now, sessions: [asked])
            store.toggleOpenRow(asked)
            store.stageSpecimenAnswer(
                selectedOptions: selected ?? (multiple ? [0, 1] : [0]),
                draft: draft
            )
            return store
        }
        let question = questionStore(multiple: false)
        let multipleChoice = questionStore(multiple: true)
        // Nothing ticked: that is the state this lesson is about (`answer-in-notch.md` §5.4). A
        // selection outranks the field, so ticks plus a draft would teach the ticks as the answer.
        let typedAnswer = questionStore(
            multiple: true,
            selected: [],
            draft: "Use a compact summary with optional details."
        )

        return Opened(command: command, question: question, multipleChoice: multipleChoice, typedAnswer: typedAnswer)
    }

    /// Three rows that left at different times (`2m`, `18m`, `1h`), staged directly via
    /// ``MonitorStore/stageSpecimenQueue(_:)`` because one merge pass would give them one age.
    private static func departedQueue(at now: Date) -> [RecentDeparture] {
        let left: [(id: String, title: String, ago: TimeInterval)] = [
            ("named", "Name every quota window as its product does", 2 * 60),
            ("rail", "Stand the scroll rail on the panel’s margin", 18 * 60),
            ("ink", "Draw every control in one ink", 66 * 60)
        ]
        return left.map { row in
            RecentDeparture(
                session: finished(
                    id: row.id,
                    title: row.title,
                    preview: nil,
                    at: now,
                    endedAgo: row.ago + 30
                ),
                departedAt: now.addingTimeInterval(-row.ago),
                reason: .read
            )
        }
    }

    /// Both selection modes, with a description long enough to show Show more.
    private static func questionRow(at now: Date, multiple: Bool = false) -> MonitoredSession {
        MonitoredSession(
            agent: .claudeCode,
            threadID: "specimen-claude-question",
            turnID: "specimen-claude-question-turn",
            projectName: "notchline",
            title: "Improve the quota summary",
            preview: nil,
            status: .inputNeeded,
            startedAt: now.addingTimeInterval(-38),
            request: AgentRequest(
                id: "specimen-claude-question-request",
                toolName: "AskUserQuestion",
                form: .questions([
                    AgentQuestion(
                        id: 0,
                        header: "Summary",
                        text: multiple ? "Which details should the summary include?" : "Which detail should the summary emphasise?",
                        options: [
                            AgentQuestionOption(id: 0, label: "Usage by product", description: "Show the usage reported by each product, with its own window names and reset times. Keep the totals easy to compare, and make the complete breakdown available without adding every detail to the compact summary."),
                            AgentQuestionOption(id: 1, label: "Time until reset", description: "Show when each usage window resets."),
                            AgentQuestionOption(id: 2, label: "Today's total", description: "Keep the summary focused on today's usage.")
                        ],
                        allowsSeveralAnswers: multiple
                    )
                ]),
                answerHandle: AnswerHandle(ticket: 0)
            )
        )
    }

    private static func makeStore(
        isExpanded: Bool,
        at now: Date,
        sessions: [MonitoredSession]
    ) -> MonitorStore {
        let store = MonitorStore(
            displays: [display],
            services: [],
            initialSnapshots: [AgentKind.codex, .claudeCode].map { agent in
                AgentSnapshot(
                    agent: agent,
                    availability: .ready,
                    sessions: sessions.filter { $0.agent == agent },
                    quota: quota(at: now)[agent] ?? .unavailable,
                    diagnostic: nil,
                    setupStatus: .active,
                    presence: .open
                )
            },
            preferences: nil
        )
        store.isExpanded = isExpanded
        return store
    }

    private static func makeStore(isExpanded: Bool, at now: Date) -> MonitorStore {
        // No services or preferences: nothing watched, no socket bound, no user file read, Settings
        // cannot change the drawing (cf. `MonitorStore.makeShared()`).
        let store = MonitorStore(
            displays: [display],
            services: [],
            initialSnapshots: snapshots(at: now, includingDeparted: true),
            preferences: nil
        )
        store.isExpanded = isExpanded
        stageDeparture(in: store, at: now)
        return store
    }

    /// Lets the sixth row leave, so the panel draws its Recent seam.
    ///
    /// The queue is fed only by merge differences, so the store gets a list with the row, then
    /// without. Re-run on every wrap so the departure ages from the same instant as the rest.
    private static func stageDeparture(in store: MonitorStore, at now: Date) {
        store.restageSpecimen(snapshots(at: now, includingDeparted: true))
        store.restageSpecimen(snapshots(at: now))
    }

    /// How long the specimen clock runs before restarting: ten minutes, less half a second so the
    /// wrap lands between `9:59` (`599.0`) and the `10:00` tick (`600.0`).
    static let clockPeriod: Duration = .milliseconds(599_500)

    /// Restarts both clocks while the window is up (`.task` cancels it). Each pass re-reads ``staged``
    /// and waits only the remainder, so `Back` or a Mac sleep cannot drift past `9:59`.
    static func cycle() async {
        while !Task.isCancelled {
            let wait = remainingBeforeWrap(stagedAt: staged.at, now: Date())
            if wait > .zero {
                try? await Task.sleep(for: wait)
            }
            guard !Task.isCancelled else { return }
            if remainingBeforeWrap(stagedAt: staged.at, now: Date()) <= .zero {
                restage()
            }
        }
    }

    /// Zero once spent, so a late wake-up wraps at once.
    static func remainingBeforeWrap(stagedAt: Date, now: Date) -> Duration {
        let remaining = clockPeriod - .seconds(now.timeIntervalSince(stagedAt))
        return max(remaining, .zero)
    }

    /// Restages both stores' rows from now, including the departure, so the seam belongs to the
    /// new instant.
    private static func restage() {
        let now = Date()
        staged.at = now
        stageDeparture(in: staged.shut, at: now)
        stageDeparture(in: staged.hovered, at: now)
        // The Recent queue wraps too. Open answer rows draw no clock and must not be re-merged or closed.
        recent?.stageSpecimenQueue(departedQueue(at: now))
    }

    static func bodySize(of store: MonitorStore) -> CGSize {
        store.currentPanelSize
    }

    /// One shoulder wider on each side, where `PanelContour` curves back up.
    static func windowSize(of store: MonitorStore) -> CGSize {
        let body = bodySize(of: store)
        return CGSize(
            width: body.width + store.surfaceShoulderRadius * 2,
            height: body.height
        )
    }
}

/// One specimen: the overlay at its own size. Hit testing is off, so a pointer never opens the
/// panel or answers a click, and the shut specimen stays shut.
private struct NotchSpecimenView: View {
    let store: MonitorStore

    var body: some View {
        let size = NotchSpecimen.windowSize(of: store)
        NotchOverlayView()
            .environmentObject(store)
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Pins

/// One numbered pin and what it points at. Internal, with `pins`, for the test that no two pins
/// on a figure share a point.
struct AnatomyPin: Identifiable {
    enum Leader {
        /// A stem dropping from the pin to the specimen's top edge.
        case down(CGFloat)
        /// A stem rising from the specimen's bottom edge to the pin.
        case up(CGFloat)
        /// A stem reaching sideways, drawn over the specimen itself.
        case left(CGFloat)
        case right(CGFloat)
        /// A stem to a spine with a foot off each end, opening rightwards: one pin for a row's Project
        /// and title, which are one reading.
        case forkRight(stem: CGFloat, spread: CGFloat, foot: CGFloat)
    }

    let id: Int
    /// The pin's centre, in the specimen's own coordinates.
    let x: CGFloat
    let y: CGFloat
    let leader: Leader
    /// Two to four words; it only names the part.
    let label: String
}

enum AnatomyMetrics {
    static let pinSize: CGFloat = 13
    static let pinFontSize: CGFloat = 8
    /// The clear space a stem crosses between a pin and the part it names.
    static let leaderClearance: CGFloat = 6
    static let keyRowHeight: CGFloat = 16
    static let keyColumns = 3
    static let keySpacing: CGFloat = 12
}

/// The pin: a numeral in a ring, in the window's control colours. Pins stand in the card's
/// margins, never on the drawing.
private struct AnatomyPinBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.system(size: AnatomyMetrics.pinFontSize, weight: .semibold))
            .foregroundStyle(MacOSWindowColor.secondaryText)
            .frame(width: AnatomyMetrics.pinSize, height: AnatomyMetrics.pinSize)
            .background { Circle().fill(MacOSWindowColor.hoverBackground) }
            .overlay {
                Circle().strokeBorder(MacOSWindowColor.groupStroke, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

private struct AnatomyLeader: View {
    let leader: AnatomyPin.Leader

    var body: some View {
        Group {
            if case let .forkRight(stem, spread, foot) = leader {
                ForkPath(stem: stem, spread: spread, foot: foot)
                    .stroke(MacOSWindowColor.separator, lineWidth: 1)
            } else {
                Rectangle().fill(MacOSWindowColor.separator)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    private var size: CGSize {
        switch leader {
        case let .down(length), let .up(length):
            return CGSize(width: 1, height: length)
        case let .left(length), let .right(length):
            return CGSize(width: length, height: 1)
        case let .forkRight(stem, spread, foot):
            return CGSize(width: stem + foot, height: spread * 2)
        }
    }
}

private struct ForkPath: Shape {
    let stem: CGFloat
    let spread: CGFloat
    let foot: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spine = rect.maxX - foot
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: spine, y: rect.midY))
        path.move(to: CGPoint(x: spine, y: rect.minY))
        path.addLine(to: CGPoint(x: spine, y: rect.maxY))
        path.move(to: CGPoint(x: spine, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.move(to: CGPoint(x: spine, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// A specimen with its pins over it and the key underneath, in three columns (`11` pt across
/// `504`).
private struct PinnedFigure<Specimen: View>: View {
    let pins: [AnatomyPin]
    /// Clear room the pins need above and below the specimen; zero where every pin is drawn over it.
    var margin: (top: CGFloat, bottom: CGFloat) = (0, 0)
    /// What the key steps in by, for a specimen drawn to the card's own edges.
    var keyInset: CGFloat = 0
    let specimenSize: CGSize
    @ViewBuilder let specimen: () -> Specimen

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                specimen()
                    .offset(y: margin.top)

                ForEach(pins) { pin in
                    leader(for: pin)
                    AnatomyPinBadge(number: pin.id)
                        .offset(
                            x: pin.x - AnatomyMetrics.pinSize / 2,
                            y: margin.top + pin.y - AnatomyMetrics.pinSize / 2
                        )
                }
            }
            .frame(
                width: specimenSize.width,
                height: margin.top + specimenSize.height + margin.bottom,
                alignment: .topLeading
            )
            .frame(maxWidth: .infinity)

            key.padding(.horizontal, keyInset)
        }
    }

    @ViewBuilder
    private func leader(for pin: AnatomyPin) -> some View {
        let half = AnatomyMetrics.pinSize / 2
        switch pin.leader {
        case .down:
            AnatomyLeader(leader: pin.leader)
                .offset(x: pin.x, y: margin.top + pin.y + half)
        case let .up(length):
            AnatomyLeader(leader: pin.leader)
                .offset(x: pin.x, y: margin.top + pin.y - half - length)
        case let .left(length):
            AnatomyLeader(leader: pin.leader)
                .offset(x: pin.x - half - length, y: margin.top + pin.y)
        case .right:
            AnatomyLeader(leader: pin.leader)
                .offset(x: pin.x + half, y: margin.top + pin.y)
        case let .forkRight(_, spread, _):
            AnatomyLeader(leader: pin.leader)
                .offset(x: pin.x + half, y: margin.top + pin.y - spread)
        }
    }

    private var key: some View {
        let columns = Array(
            repeating: GridItem(
                .flexible(),
                spacing: AnatomyMetrics.keySpacing,
                alignment: .topLeading
            ),
            count: AnatomyMetrics.keyColumns
        )
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(pins) { pin in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(pin.id)")
                        .font(.system(size: 11))
                        .foregroundStyle(MacOSWindowColor.tertiaryText)

                    Text(pin.label)
                        .font(.system(size: 11))
                        .foregroundStyle(MacOSWindowColor.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: AnatomyMetrics.keyRowHeight, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Shut

/// The collapsed bar, named part by part (`compact-view-v2.md` §8).
///
/// Every pin's `x` is composed from `PanelMetrics`, never measured off a drawing.
struct CollapsedBarAnatomy: View {
    private let store = NotchSpecimen.shut

    /// The bar at its own size, which the pins are placed against. Internal for tests.
    var specimenSize: CGSize { NotchSpecimen.windowSize(of: store) }

    var body: some View {
        PinnedFigure(
            pins: pins,
            margin: (top: pinRow, bottom: pinRow),
            specimenSize: specimenSize
        ) {
            NotchSpecimenView(store: store)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "The collapsed bar: one mark for every product at once showing the "
                + "most urgent state, the number of sessions and the number of "
                + "subagents, the Project being worked on, a dot for a finished "
                + "turn nobody has read, and the longest running turn."
        )
    }

    private var pinRow: CGFloat {
        AnatomyMetrics.pinSize + AnatomyMetrics.leaderClearance
    }

    /// Where the parts stand, in the specimen's coordinates. Internal for the no-overlap test.
    ///
    /// The counts column's numerals are `16.6` pt apart on one x, so it takes one pin from above and
    /// one from below.
    var pins: [AnatomyPin] {
        let size = NotchSpecimen.windowSize(of: store)
        let shoulder = store.surfaceShoulderRadius
        let matrix = PanelMetrics.statusMatrixSize
        let leading = shoulder + PanelMetrics.expandedHorizontalPadding
        let mark = leading + matrix / 2
        // Both numerals start one gap past the mark; the narrower subagents numeral centres within a
        // point of this, so one x serves both leaders.
        let counts = leading
            + matrix
            + PanelMetrics.aggregateCountsGap
            + PanelMetrics.countsDigitWidth / 2
        // The middle starts past the leading group's reserved width plus one notch clearance. The pin
        // goes on the name, not the slot: a short name leaves the slot's middle black.
        let middleWidth = PanelMetrics.pillMiddleWidth(
            trailing: store.compactTrailingReading
        )
        let name = store.compactProjectNames.first ?? ""
        let middle = leading
            + PanelMetrics.reservedLeadingGroupWidth
            + PanelMetrics.expandedNotchClearance
            + min(
                PanelMetrics.textWidth(name, font: PanelMetrics.projectNameFont),
                middleWidth
            ) / 2
        let trailing = size.width - shoulder - PanelMetrics.expandedHorizontalPadding
        // Trailing pins measured inwards from the panel edge: the reading ends one trailing padding in,
        // the dot and its `8` stand before it.
        var reading: CGFloat = 0
        if let timerText = store.compactTimerText {
            reading = PanelMetrics.drawnCompactReadingWidth(timerText)
        }
        let timer = trailing - reading / 2
        let dot = trailing
            - reading
            - PanelMetrics.buriedFinishDotSpacing
            - PanelMetrics.buriedFinishDotSize / 2
        let top = -AnatomyMetrics.leaderClearance - AnatomyMetrics.pinSize / 2
        let bottom = store.currentPanelSize.height
            + AnatomyMetrics.leaderClearance
            + AnatomyMetrics.pinSize / 2
        let stem = AnatomyMetrics.leaderClearance

        return [
            AnatomyPin(
                id: 1,
                x: mark,
                y: top,
                leader: .down(stem),
                label: "Most urgent state"
            ),
            AnatomyPin(
                id: 2,
                x: counts,
                y: top,
                leader: .down(stem),
                label: "Sessions on the list"
            ),
            AnatomyPin(id: 3, x: counts, y: bottom, leader: .up(stem), label: "Subagents"),
            AnatomyPin(
                id: 4,
                x: middle,
                y: bottom,
                leader: .up(stem),
                label: "The Project"
            ),
            AnatomyPin(
                id: 5,
                x: dot,
                y: bottom,
                leader: .up(stem),
                label: "A finished turn, unread"
            ),
            AnatomyPin(id: 6, x: timer, y: bottom, leader: .up(stem), label: "Longest turn")
        ]
    }
}

// MARK: - Hovered

/// The expanded panel, named part by part. `0.624` keeps it at `436.8` pt inside the `532` card.
struct ExpandedPanelAnatomy: View {
    private let store = NotchSpecimen.hovered

    static let scale: CGFloat = 0.624

    /// The panel as this page draws it. Internal for the edge test.
    var specimenSize: CGSize {
        let panel = NotchSpecimen.windowSize(of: store)
        return CGSize(width: panel.width * Self.scale, height: panel.height * Self.scale)
    }

    var body: some View {
        let scale = Self.scale
        let drawn = specimenSize

        return PinnedFigure(pins: pins, keyInset: 14, specimenSize: drawn) {
            NotchSpecimenView(store: store)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: drawn.width, height: drawn.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Hovering the notch opens one list of both products, most urgent "
                + "first: each row names its product, Project and title, says "
                + "the last thing the agent said, and ends in a reading while "
                + "it runs, in a badge where the turn has finished and a "
                + "subagent has not, or in a control offering the answer it is "
                + "waiting for. Under the list, a seam holding the rows that "
                + "have left it; under that, what both products have spent "
                + "today and a control that opens their rate-limit windows."
        )
    }

    /// Every part named from the margins: left for row leads and footer, right for line-ending marks.
    /// Panel units, scaled with it; every y composed, never measured. Internal for tests.
    var pins: [AnatomyPin] {
        let scale = Self.scale
        let size = NotchSpecimen.windowSize(of: store)
        let header = store.compactHeight
        let inset = PanelMetrics.sessionRowVerticalPadding
        // The first block's header sits between the band and the first row at every product count.
        let blockHeader = PanelMetrics.leadingProductGroupHeaderHeight
        let firstRow = header + blockHeader
        let secondRow = firstRow + PanelMetrics.sessionRowHeight
        let caption = firstRow + inset + PanelMetrics.sessionRowCaptionHeight / 2
        let title = firstRow
            + inset
            + PanelMetrics.sessionRowCaptionHeight
            + PanelMetrics.sessionRowLineSpacing
            + PanelMetrics.sessionRowTitleHeight / 2
        let lastSaid = firstRow
            + PanelMetrics.sessionRowHeight
            - inset
            - PanelMetrics.sessionRowPreviewHeight / 2
        // A row's mark is centred on the row, not on any of its lines.
        let firstMark = firstRow + PanelMetrics.sessionRowHeight / 2
        let secondMark = secondRow + PanelMetrics.sessionRowHeight / 2
        // Height from the store, which counts the headers; a row count alone misplaced these pins by
        // `64` with two products. Both closing bars are one `32` pt height (`quota-footer-v2.md` §2).
        let list = header + store.sessionViewportHeight
        let seam = list + PanelMetrics.recentSeamHeight / 2
        let footer = list + store.recentSectionHeight
        let spend = footer + PanelMetrics.recentSeamHeight / 2

        func left(
            _ id: Int,
            _ y: CGFloat,
            _ label: String
        ) -> AnatomyPin {
            AnatomyPin(
                id: id,
                x: leftMargin * scale,
                y: y * scale,
                leader: .right(gutter),
                label: label
            )
        }

        func right(
            _ id: Int,
            _ y: CGFloat,
            _ label: String
        ) -> AnatomyPin {
            AnatomyPin(
                id: id,
                x: rightMargin(of: size) * scale,
                y: y * scale,
                leader: .left(gutter),
                label: label
            )
        }

        // The block heading; rows no longer name their own product.
        let key: [AnatomyPin] = [
            left(1, header / 2, "Same as above"),
            right(2, header / 2, "Settings"),
            left(3, header + blockHeader / 2, "Whose these are")
        ]
        let next = key.count + 1
        return key + [
            // One pin, two feet: Project and title are one reading. The product is not one of them; the
            // heading says it (`panel-v2.md` §3.4).
            AnatomyPin(
                id: next,
                x: leftMargin * scale,
                y: (caption + title) / 2 * scale,
                leader: .forkRight(
                    stem: gutter - forkFoot,
                    spread: (title - caption) / 2 * scale,
                    foot: forkFoot
                ),
                label: "Project and title"
            ),
            left(next + 1, lastSaid, "The last thing said"),
            // The only part that does something: the mark opens the Thread's request
            // (`answer-in-notch.md` §3).
            right(next + 2, firstMark, "Answer it here"),
            right(next + 3, secondMark, "Subagents"),
            left(next + 4, seam, "Rows that have left"),
            left(next + 5, spend, "Today’s tokens"),
            // The footer's only control; rate-limit windows are behind it, not drawn at rest.
            right(next + 6, spend, "Rate limits")
        ]
    }

    /// How far either column stands off the panel, in panel units.
    private static let margin: CGFloat = 30

    /// Negative because the figure's origin is the specimen's leading edge.
    private var leftMargin: CGFloat { -Self.margin }

    private func rightMargin(of size: CGSize) -> CGFloat { size.width + Self.margin }

    /// Half the unscaled `13` pt badge off the scaled margin, so the leader stops on the panel's edge.
    private var gutter: CGFloat {
        Self.margin * Self.scale - AnatomyMetrics.pinSize / 2
    }

    /// How far a forked leader's feet reach past its spine, in drawing units.
    private var forkFoot: CGFloat { 10 }
}

// MARK: - Opened

/// Shared by the open-request and Recent figures: the panel's ground without header or footer,
/// row block inset by the panel's gutter.
private enum OpenedSpecimen {
    static var gutter: CGFloat { PanelMetrics.sessionRowGutter }

    /// Pin centres bisect each card margin in drawing units; badges never scale.
    static let drawnWidth: CGFloat = 436.8
    static let margin = (OnboardingLayout.cardWidth - drawnWidth) / 4

    /// The clear space a leader crosses, badge edge to plate edge.
    static var gutterToPlate: CGFloat { margin - AnatomyMetrics.pinSize / 2 }

    /// The panel's width, and the specimen's height with the panel's gutter above and below.
    static func plateSize(store: MonitorStore, height: CGFloat) -> CGSize {
        let scale = scale(plateWidth: store.currentPanelSize.width)
        return CGSize(
            width: store.currentPanelSize.width * scale,
            height: (height + gutter * 2) * scale
        )
    }

    /// Pin margins are reserved before scaling, since the pins themselves never scale.
    static func scale(plateWidth: CGFloat) -> CGFloat {
        drawnWidth / plateWidth
    }

    /// Measured inwards from the trailing edge: field, refusal, affirmative, each hugging its word
    /// (``PanelMetrics/drawnAnswerControlWidth(_:)``), `8` apart.
    static func answerCentres(
        rowWidth: CGFloat,
        shape: AnswerRowShape
    ) -> (field: CGFloat, refusal: CGFloat?, affirmative: CGFloat) {
        let trailing = rowWidth - PanelMetrics.sessionRowPadding
        let affirmativeWidth = PanelMetrics.drawnAnswerControlWidth(shape.affirmative)
        let affirmative = trailing - affirmativeWidth / 2
        var fieldEnd = trailing - affirmativeWidth - 8
        var refusal: CGFloat?
        if let word = shape.refusal {
            let width = PanelMetrics.drawnAnswerControlWidth(word)
            refusal = fieldEnd - width / 2
            fieldEnd -= width + 8
        }
        return (
            field: (PanelMetrics.sessionRowPadding + fieldEnd) / 2,
            refusal: refusal,
            affirmative: affirmative
        )
    }
}

/// Pins in the left margin and along the bottom: side-by-side controls in one column overlap (§7.1).
private struct OpenedFigure<Specimen: View>: View {
    let store: MonitorStore
    let pins: [AnatomyPin]
    /// The specimen's own height, in panel units.
    let height: CGFloat
    @ViewBuilder let specimen: () -> Specimen

    var body: some View {
        let scale = OpenedSpecimen.scale(plateWidth: store.currentPanelSize.width)
        let plate = OpenedSpecimen.plateSize(store: store, height: height)

        return PinnedFigure(
            pins: pins,
            margin: (top: 0, bottom: AnatomyMetrics.pinSize + AnatomyMetrics.leaderClearance),
            keyInset: 14,
            specimenSize: plate
        ) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black)

                specimen()
                    .environmentObject(store)
                    .frame(
                        width: PanelMetrics.sessionViewportWidth(
                            panelWidth: store.currentPanelSize.width
                        )
                    )
                    .padding(OpenedSpecimen.gutter)
            }
            // Drawn at panel size and scaled as one, so ground and content cannot come apart.
            .frame(
                width: store.currentPanelSize.width,
                height: height + OpenedSpecimen.gutter * 2,
                alignment: .topLeading
            )
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: plate.width, height: plate.height, alignment: .topLeading)
            // Drawings in a settings window: no hover, no armed answer, no click.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A permission request, open: the same row page two draws shut.
struct OpenCommandAnatomy: View {
    private let store = NotchSpecimen.openedSpecimens().command

    /// Composed by the store from the request's own layout.
    private var height: CGFloat { store.openRowHeight ?? PanelMetrics.sessionRowHeight }

    /// The plate it is drawn on. Internal, with ``pins``, for the edge and overlap test.
    var specimenSize: CGSize {
        OpenedSpecimen.plateSize(store: store, height: height)
    }

    var body: some View {
        OpenedFigure(store: store, pins: pins, height: height) {
            if let session = store.openSession {
                OpenRow(session: session)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "A permission request, open on the notch: the row names its "
                + "product, Project and title, then draws the command the agent "
                + "is asking to run, and a row of answers — a field for what to "
                + "do instead, Deny, and Approve, which holds the white ground "
                + "and is what the return key takes."
        )
    }

    var pins: [AnatomyPin] {
        let scale = OpenedSpecimen.scale(plateWidth: store.currentPanelSize.width)
        let rowWidth = PanelMetrics.sessionViewportWidth(
            panelWidth: store.currentPanelSize.width
        )
        let shape = store.openAnswerRow
        let centres = shape.map {
            OpenedSpecimen.answerCentres(rowWidth: rowWidth, shape: $0)
        }
        let body = OpenRowGeometry(store: store)

        return [
            AnatomyPin(
                id: 1,
                x: -OpenedSpecimen.margin,
                y: (OpenedSpecimen.gutter + body.bodyCentre) * scale,
                leader: .right(OpenedSpecimen.gutterToPlate),
                label: "The command it sent"
            ),
            below(2, centres?.field, "Say what instead", scale: scale, body: body),
            below(3, centres?.refusal, "Turn it down", scale: scale, body: body),
            below(
                4,
                centres?.affirmative,
                "Approve, or ⏎",
                scale: scale,
                body: body
            )
        ].compactMap { $0 }
    }

    private func below(
        _ id: Int,
        _ x: CGFloat?,
        _ label: String,
        scale: CGFloat,
        body: OpenRowGeometry
    ) -> AnatomyPin? {
        guard let x else { return nil }
        return AnatomyPin(
            id: id,
            x: (OpenedSpecimen.gutter + x) * scale,
            y: (body.height + OpenedSpecimen.gutter * 2) * scale
                + AnatomyMetrics.leaderClearance
                + AnatomyMetrics.pinSize / 2,
            leader: .up(AnatomyMetrics.leaderClearance),
            label: label
        )
    }
}

/// A question with options, open: the other shape a product asks in.
struct OpenQuestionAnatomy: View {
    var lesson: QuestionLesson = .singleChoice
    private var store: MonitorStore {
        let examples = NotchSpecimen.openedSpecimens()
        return switch lesson {
        case .singleChoice: examples.question
        case .multipleChoice: examples.multipleChoice
        case .typedAnswer: examples.typedAnswer
        }
    }

    /// Composed by the store from the request's own layout.
    private var height: CGFloat { store.openRowHeight ?? PanelMetrics.sessionRowHeight }

    /// The plate it is drawn on. Internal, with ``pins``, for the edge and overlap test.
    var specimenSize: CGSize {
        OpenedSpecimen.plateSize(store: store, height: height)
    }

    var body: some View {
        OpenedFigure(store: store, pins: pins, height: height) {
            if let session = store.openSession {
                OpenRow(session: session)
            }
        }
        // Examples share a specimen Thread ID but each has its own draft; recreate the answer field.
        .id(lesson)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(lesson.rawValue). \(lesson.explanation) The example has a long description with Show more, an answer field and Submit."
        )
    }

    var pins: [AnatomyPin] {
        let scale = OpenedSpecimen.scale(plateWidth: store.currentPanelSize.width)
        let rowWidth = PanelMetrics.sessionViewportWidth(
            panelWidth: store.currentPanelSize.width
        )
        let shape = store.openAnswerRow
        let centres = shape.map {
            OpenedSpecimen.answerCentres(rowWidth: rowWidth, shape: $0)
        }
        let body = OpenRowGeometry(store: store)

        var pins: [AnatomyPin] = [
            AnatomyPin(
                id: 1,
                x: -OpenedSpecimen.margin,
                y: (OpenedSpecimen.gutter + body.questionCentre) * scale,
                leader: .right(OpenedSpecimen.gutterToPlate),
                label: "What it is asking"
            )
        ]

        // One bracketed pin over the whole option list: the options are one part.
        if let options = body.optionList {
            pins.append(
                AnatomyPin(
                    id: 2,
                    x: -OpenedSpecimen.margin,
                    y: (OpenedSpecimen.gutter + options.centre) * scale,
                    leader: .forkRight(
                        stem: OpenedSpecimen.gutterToPlate - 10,
                        spread: options.spread * scale,
                        foot: 10
                    ),
                    label: lesson == .typedAnswer ? "None of them chosen" : "Select, then Submit"
                )
            )
        }

        if let field = centres?.field {
            pins.append(
                below(3, field, lesson == .typedAnswer ? "Your words are the answer" : "Or type your answer", scale: scale, body: body)
            )
        }
        // Uses the specimen's own word, so the pin follows it (a set of one submits, §5.8).
        if let shape, let affirmative = centres?.affirmative {
            pins.append(
                below(4, affirmative, "\(shape.affirmative), or ⏎", scale: scale, body: body)
            )
        }
        return pins
    }

    private func below(
        _ id: Int,
        _ x: CGFloat,
        _ label: String,
        scale: CGFloat,
        body: OpenRowGeometry
    ) -> AnatomyPin {
        AnatomyPin(
            id: id,
            x: (OpenedSpecimen.gutter + x) * scale,
            y: (body.height + OpenedSpecimen.gutter * 2) * scale
                + AnatomyMetrics.leaderClearance
                + AnatomyMetrics.pinSize / 2,
            leader: .up(AnatomyMetrics.leaderClearance),
            label: label
        )
    }
}

/// Where an open row's parts stand, composed from the figures the row stacks (`12.5` of air,
/// caption, title, body, answer row), never measured off a drawing.
private struct OpenRowGeometry {
    let store: MonitorStore

    var height: CGFloat { store.openRowHeight ?? PanelMetrics.sessionRowHeight }

    /// Where the request's body begins, under the caption and the title.
    var bodyTop: CGFloat {
        12.5
            + PanelMetrics.sessionRowCaptionHeight
            + PanelMetrics.sessionRowLineSpacing
            + PanelMetrics.sessionRowTitleHeight
            + PanelMetrics.sessionRowLineSpacing
    }

    /// The middle of the whole body, for a one-line command.
    var bodyCentre: CGFloat {
        bodyTop + (store.openRowBody?.drawnHeight ?? 0) / 2
    }

    /// The middle of the question itself: its lines, before its answers.
    var questionCentre: CGFloat {
        guard let body = store.openRowBody else { return bodyCentre }
        let lines = CGFloat(body.lines.count)
            * PanelMetrics.requestLineHeight(for: body.setting)
        return bodyTop + lines / 2
    }

    /// The option list's middle, and its bracket's spread: half the first-to-last option distance.
    var optionList: (centre: CGFloat, spread: CGFloat)? {
        guard let body = store.openRowBody, !body.options.isEmpty else { return nil }
        let lines = CGFloat(body.lines.count)
            * PanelMetrics.requestLineHeight(for: body.setting)
        let top = bodyTop + lines + PanelMetrics.optionListSpacing
        let heights = body.optionLayouts.map(\.height)
        guard let first = heights.first, let last = heights.last else { return nil }
        let list = heights.reduce(0, +) + CGFloat(heights.count - 1) * PanelMetrics.optionSpacing
        let firstCentre = top + first / 2
        let lastCentre = min(top + list - last / 2, bodyTop + body.drawnHeight)
        return (
            centre: (firstCentre + lastCentre) / 2,
            spread: max(0, (lastCentre - firstCentre) / 2)
        )
    }
}

/// The Recent queue, open: what is behind the seam page two names.
struct RecentQueueAnatomy: View {
    private let store = NotchSpecimen.recentQueue

    /// The plate it is drawn on. Internal, with ``pins``, for the edge and overlap test.
    var specimenSize: CGSize {
        OpenedSpecimen.plateSize(store: store, height: height)
    }

    var body: some View {
        OpenedFigure(store: store, pins: pins, height: height) {
            RecentSessionSection()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "The Recent queue, open: a seam saying how many rows have left the "
                + "list, and under it one line each — half the height of a live "
                + "row — ending in how long ago it left. Five hours, and a row "
                + "is gone."
        )
    }

    /// The seam and its own viewport, which is what the section draws.
    private var height: CGFloat { store.recentSectionHeight }

    var pins: [AnatomyPin] {
        let scale = OpenedSpecimen.scale(plateWidth: store.currentPanelSize.width)
        let plate = store.currentPanelSize.width
        let seam = PanelMetrics.recentSeamHeight / 2
        // The first retired row, and its trailing end where `2m` stands, one row padding in. Grouped,
        // the first block's short heading stands between the seam and it (`expanded-panel-v2.md` §4.7).
        let blockHeader = store.recentGroupHeaderCount > 0
            ? PanelMetrics.leadingProductGroupHeaderHeight
            : 0
        let firstRow = PanelMetrics.recentSeamHeight + blockHeader + PanelMetrics.retiredRowHeight / 2
        let age = plate - OpenedSpecimen.gutter - PanelMetrics.sessionRowPadding - 9

        return [
            AnatomyPin(
                id: 1,
                x: -OpenedSpecimen.margin,
                y: (OpenedSpecimen.gutter + seam) * scale,
                leader: .right(OpenedSpecimen.gutterToPlate),
                label: "How many have left"
            ),
            AnatomyPin(
                id: 2,
                x: -OpenedSpecimen.margin,
                y: (OpenedSpecimen.gutter + firstRow) * scale,
                leader: .right(OpenedSpecimen.gutterToPlate),
                label: "Half a live row"
            ),
            AnatomyPin(
                id: 3,
                x: plate * scale + OpenedSpecimen.margin,
                y: (OpenedSpecimen.gutter + firstRow) * scale,
                leader: .left(OpenedSpecimen.gutterToPlate),
                label: "When it left"
            )
        ]
    }
}

#Preview("Collapsed bar") {
    CollapsedBarAnatomy().padding(24).frame(width: 532)
}

#Preview("Expanded panel") {
    ExpandedPanelAnatomy().padding(24).frame(width: 532)
}

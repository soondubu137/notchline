// The two drawings the first-run window teaches from, and the pins that name
// their parts. See `figma-design.md` §7.
//
// **The specimens are the product, not pictures of it.** Each one is
// `NotchOverlayView` over a `MonitorStore` built from fixed snapshots, so the
// bar and the panel here are composed by the same views, from the same
// `PanelMetrics`, as the ones on the notch. Nothing is redrawn for onboarding
// and nothing can drift: a change to the mark, to the counts column, to a
// row's shape or to the width formula arrives in this window on the same build
// it arrives on the surface.
//
// The README's figures (`docs/assets/notch-anatomy-readme.png` and its pair)
// are the same teaching at four thousand pixels wide, with a column of prose
// either side. That layout does not survive a `532` pt content area — the
// labels would land near `4` pt — so the columns become numbered pins and a
// key of two-to-four words, and the artwork keeps its real size.
import Combine
import SwiftUI

/// The fixed moment both specimens draw: two products connected, one turn
/// stopped on an approval a person could give here, one finished with work
/// still in flight, three finished and unread, and one that has left the list.
///
/// One moment for both drawings rather than two, so the shut bar and the open
/// panel are the same instant seen twice — which is the relationship the window
/// is teaching. The readings are live: the store ticks, so the elapsed value
/// counts on exactly as it would on the notch. Nothing else moves, because
/// nothing else on that surface ever does.
@MainActor
enum NotchSpecimen {
    /// A display that is not a display.
    ///
    /// A `46` pt menu bar and no notch, whatever the user is actually running
    /// on. The notch-less pill is the self-contained form — it carries the
    /// status name, and it is the whole of what the app draws rather than a
    /// shape that only makes sense wrapped around a cut-out — so it is the one
    /// to teach from inside a window. The parts are identical on both forms.
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

    /// The staged instant, and the two stores drawing it.
    ///
    /// One tuple rather than two `static let`s, because the two stores have to
    /// be the *same* moment — built from one `Date()` and re-staged together —
    /// and because the wrap has to know when that moment was. Lazily built, so
    /// a first run that never reaches page two composes no store at all.
    private static var staged: (at: Date, shut: MonitorStore, hovered: MonitorStore) = {
        let now = Date()
        return (
            at: now,
            shut: makeStore(isExpanded: false, at: now),
            hovered: makeStore(isExpanded: true, at: now)
        )
    }()

    /// The collapsed bar, shut.
    static var shut: MonitorStore { staged.shut }

    /// The same moment with the panel open.
    static var hovered: MonitorStore { staged.hovered }

    /// Both specimens' sessions, in one list per product.
    ///
    /// Five Codex rows and one Claude Code row, which between them are the
    /// whole of what the two drawings have to say:
    ///
    /// - The Codex turn at the head of the list is **stopped on an approval,
    ///   and the approval can be given here**. That is what makes the bar say
    ///   `Approval needed`, and what puts `Approve` — the answer's own control
    ///   (`answer-in-notch.md` §3) — where the first row's reading would be.
    /// - Three more Codex turns are **finished and nobody has looked at them**.
    ///   A finished turn sitting under a mark that is drawing something else is
    ///   the condition the trailing wing's dot breathes for, so the shut bar
    ///   draws that dot.
    /// - The Claude Code turn is **finished with a subagent still working**.
    ///   That is the one row drawing a badge where a reading would be, and it
    ///   is also why this product's mark is on radar rather than lull: a thread
    ///   with a subagent in flight is still running (``MonitorAggregation``).
    /// - A sixth Codex turn has **finished and left the list**, which is the
    ///   Recent seam under the rows. It is staged by the ordinary arrow rather
    ///   than placed: ``makeStore(isExpanded:at:)`` hands the store the list
    ///   with it and then the list without it, and the merge records the
    ///   departure the way a product going quiet does (`expanded-panel-v2.md`
    ///   §2.1). `includingDeparted` is which of those two lists this is.
    private static func sessions(
        at now: Date,
        includingDeparted: Bool = false
    ) -> [AgentKind: [MonitoredSession]] {
        [
            .codex: [
                approvalRow(at: now),
                finished(
                    id: "audit",
                    title: "Audit the hook payload paths",
                    preview: "Both products reach the reducer.",
                    at: now,
                    endedAgo: 540
                ),
                finished(
                    id: "edges",
                    title: "Keep the collapsed bar's edges still",
                    preview: "The trailing slot is billed for a fixed width.",
                    at: now,
                    endedAgo: 1_260
                ),
                finished(
                    id: "fold",
                    title: "Fold the quota block away",
                    preview: "The chevron leaves the totals line standing.",
                    at: now,
                    endedAgo: 2_400
                )
            ]
                + (includingDeparted ? [departing(at: now)] : []),
            .claudeCode: [
                MonitoredSession(
                    agent: .claudeCode,
                    threadID: "specimen-claude",
                    turnID: "specimen-claude-turn",
                    projectName: "notchline",
                    title: "Validate the notch positioning",
                    preview: "Positioning tests pass on this Mac.",
                    status: .completed,
                    startedAt: now.addingTimeInterval(-247),
                    runningSubagentCount: 4,
                    finishedAt: now.addingTimeInterval(-96)
                )
            ]
        ]
    }

    /// The row at the head of the list: stopped on an approval, and holding
    /// the request page three opens.
    ///
    /// **One row in two figures.** Page two draws it shut, with `Approve` on
    /// its trailing end; page three draws the same row open, with the command
    /// that mark leads to. Building it in one place is what makes the two the
    /// same row rather than two rows that resemble each other — the title, the
    /// preview and the request are read from here by both.
    private static func approvalRow(at now: Date) -> MonitoredSession {
        MonitoredSession(
            agent: .codex,
            threadID: "specimen-codex-approval",
            turnID: "specimen-codex-approval-turn",
            projectName: "notchline",
            title: "Wire the quota footer to the fold control",
            preview: "Reading PanelMetrics to find the trailing slot.",
            status: .approvalNeeded,
            // The clock this window teaches from starts here; see
            // ``clockPeriod``. An approval keeps timing
            // (`SessionStatus.keepsTiming`), so this is still the longest
            // unfinished turn and still what the collapsed reading draws --
            // the row itself spends that slot on the control instead.
            startedAt: now,
            runningSubagentCount: 3,
            request: approval
        )
    }

    /// The approval that row is holding, and the reason its mark says
    /// `Approve` rather than `Read`.
    ///
    /// **A ticket that leads nowhere, on a drawing that declines every hit.**
    /// ``AgentRequest/canBeAnswered`` is `replyTicket != nil` and nothing else,
    /// because offering an act the app cannot deliver is the quiet promise
    /// `answer-in-notch.md` §11 rule 03 forbids — so a specimen that is to
    /// teach the answer control at all has to carry one. That rule protects a
    /// person who can click, and nobody can click this: ``NotchSpecimenView``
    /// turns hit testing off, so the word here is a drawing of a control rather
    /// than a control. If a click ever did arrive, the registry holds no
    /// connection under this number and the row would say so rather than
    /// pretending — which is the same answer a real row gives when the product
    /// has settled the request elsewhere.
    ///
    /// The command is never drawn: the body belongs to an **open** row, and the
    /// specimen's rows are all shut. It is what it is so that the form is a real
    /// one — a command is `Approve` / `Deny`, and a plan or a question would put
    /// different words on the mark.
    private static let approval = AgentRequest(
        id: "specimen-codex-approval-request",
        toolName: "Bash",
        form: .command("swiftformat Notchline/Notchline/MonitorStore.swift"),
        replyTicket: 0
    )

    /// The row that leaves, so the panel has a Recent seam to name.
    ///
    /// Finished, on a product that is still connected — which is the queue's
    /// ordinary arrow, `read`: the turn ended, and then its product stopped
    /// listing it because somebody read it there
    /// (``MonitorStore/departureReason(for:connectedAgents:)``). A dismissal
    /// would have drawn the same seam and taught something rarer.
    private static func departing(at now: Date) -> MonitoredSession {
        finished(
            id: "departed",
            title: "Name every quota window as its product does",
            preview: "Both tables read the way each product writes them.",
            at: now,
            endedAgo: 3_300
        )
    }

    /// One of the finished Codex turns stacked up under the mark.
    private static func finished(
        id: String,
        title: String,
        preview: String?,
        at now: Date,
        endedAgo: TimeInterval
    ) -> MonitoredSession {
        MonitoredSession(
            agent: .codex,
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

    /// Every product's answer at one instant: what both stores are built from,
    /// and what ``cycle()`` hands back to them.
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

    /// One product's rate-limit windows, and what it has spent today.
    ///
    /// Three rules, because that is what the footer has to explain: Codex
    /// publishes one window and Claude Code publishes two, and the panel draws
    /// each product's own rather than one number standing for both. The resets
    /// are relative to the staged instant, so they stay sensible for as long as
    /// the window is up — a fixed date would be counting down towards a moment
    /// that had already passed by the second time somebody opened this.
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

    /// The open Recent queue belongs to the reading page. Building it must
    /// not construct the answer examples before their page is visited.
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

    /// The page-three examples and the instant they share.
    ///
    /// **Built on first use, like the other two and one page later.** Page two
    /// composes no store until it is reached; these compose none until page
    /// three is, so a first run that connects and stops has built nothing at
    /// all. The question variants remain isolated from one another.
    /// Cached separately from the reading page's Recent queue.
    private static var opened: Opened?

    struct Opened {
        /// A permission request, open: the row page two draws shut.
        let command: MonitorStore
        /// A question with options, open.
        let question: MonitorStore
        let multipleChoice: MonitorStore
        let typedAnswer: MonitorStore
    }

    /// The page-three stores, composed if this is the first look at them.
    static func openedSpecimens() -> Opened {
        if let opened { return opened }
        let built = makeOpened(at: Date())
        opened = built
        return built
    }

    private static func makeOpened(at now: Date) -> Opened {
        let command = makeStore(isExpanded: true, at: now, sessions: [approvalRow(at: now)])
        command.toggleOpenRow(approvalRow(at: now))

        func questionStore(multiple: Bool, draft: String = "") -> MonitorStore {
            let asked = questionRow(at: now, multiple: multiple)
            let store = makeStore(isExpanded: true, at: now, sessions: [asked])
            store.toggleOpenRow(asked)
            store.stageSpecimenAnswer(selectedOptions: multiple ? [0, 1] : [0], draft: draft)
            return store
        }
        let question = questionStore(multiple: false)
        let multipleChoice = questionStore(multiple: true)
        let typedAnswer = questionStore(multiple: true, draft: "Use a compact summary with optional details.")

        return Opened(command: command, question: question, multipleChoice: multipleChoice, typedAnswer: typedAnswer)
    }

    /// The queue page two opens: three rows that left at three different
    /// times.
    ///
    /// **The ages are the teaching**, which is why they are staged directly
    /// (``MonitorStore/stageSpecimenQueue(_:)``) rather than through the arrow
    /// page two's single departure takes. A queue is a sequence — this one runs
    /// `2m`, `18m`, `1h` — and rows that all departed in the same pass would
    /// have drawn one age three times and said the opposite.
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
                // The lifecycle's own arrow: the turn ended, and then its
                // product recorded the Thread as read.
                reason: .read
            )
        }
    }

    /// The same example in both selection modes, with a description long
    /// enough to expose the real Show more control.
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
                replyTicket: 0
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
        // No services and no preferences: nothing is watched, no socket is
        // bound, no file of the user's is read, and the drawing cannot be
        // changed by what they happen to have chosen in Settings. See
        // `MonitorStore.makeShared()` for the same argument at launch.
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
    /// **The row departs; it is not placed there.** The queue is fed from one
    /// funnel — the difference between the list a merge arrives with and the
    /// list before it — so the honest way to put a row under the seam is to
    /// hand the store a list holding it and then a list without it. That is
    /// what a product recording a Thread as read looks like from in here, and
    /// it means the specimen has no path into the queue that the notch itself
    /// does not have.
    ///
    /// Called again on every wrap: the departure ages from its own instant, and
    /// re-staging the rows without re-staging this would leave a seam counting
    /// away from a moment the rest of the drawing had left behind.
    private static func stageDeparture(in store: MonitorStore, at now: Date) {
        store.restageSpecimen(snapshots(at: now, includingDeparted: true))
        store.restageSpecimen(snapshots(at: now))
    }

    /// How long the specimen's clock runs before it starts again.
    ///
    /// The reading is live — the product's own `ElapsedReadout` over the
    /// product's own tick — so a window left open all afternoon would be
    /// teaching from `4:17:33`. Ten minutes is the longest run that still reads
    /// as a turn, and the wrap comes **half a second early**: the reading is
    /// `9:59` from `599.0`, the tick that would draw `10:00` fires at `600.0`,
    /// and landing between them is what makes `9:59` the last figure anybody
    /// sees rather than a race with the tick.
    static let clockPeriod: Duration = .milliseconds(599_500)

    /// Start both specimens' clocks again, for as long as the window is up.
    ///
    /// Driven by the view rather than by a timer of its own, so it stops when
    /// onboarding does: `.task` is cancelled when that view goes away, and
    /// nothing here outlives the window.
    ///
    /// **Each pass measures the clock rather than counting on the last sleep.**
    /// A fixed `sleep(period)` loop drifts past `9:59` the moment anything
    /// takes the sleep and the wall clock out of step, and two ordinary things
    /// do: going `Back` to page one cancels this task and starting it again
    /// re-sleeps a whole period against a store that has been counting the
    /// whole time, and a Mac that sleeps holds the task while the reading —
    /// which is wall-clock — runs on. Re-reading ``staged`` every pass makes
    /// both self-correcting: the wait is only ever the remainder, and a
    /// wake-up that finds the clock already past the period wraps immediately.
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

    /// How much of the period a clock staged at `stagedAt` has left.
    ///
    /// Zero once it is spent, which is what makes a wake-up that finds the
    /// clock already past the period wrap at once rather than sleeping through
    /// another one.
    static func remainingBeforeWrap(stagedAt: Date, now: Date) -> Duration {
        let remaining = clockPeriod - .seconds(now.timeIntervalSince(stagedAt))
        return max(remaining, .zero)
    }

    /// Hand both stores the same rows again, started now — and let the same
    /// row leave again, so the seam is part of the instant rather than a
    /// leftover from the first one.
    private static func restage() {
        let now = Date()
        staged.at = now
        stageDeparture(in: staged.shut, at: now)
        stageDeparture(in: staged.hovered, at: now)
        // The reading page's queue wraps with its other specimens. Open
        // answer rows draw no clock and must not be re-merged or closed.
        recent?.stageSpecimenQueue(departedQueue(at: now))
    }

    /// The body's size, as the product would compose it for this moment.
    static func bodySize(of store: MonitorStore) -> CGSize {
        store.currentPanelSize
    }

    /// The window the overlay would put that body in: one shoulder wider on
    /// each side, which is where `PanelContour` draws the curve back up.
    static func windowSize(of store: MonitorStore) -> CGSize {
        let body = bodySize(of: store)
        return CGSize(
            width: body.width + store.surfaceShoulderRadius * 2,
            height: body.height
        )
    }
}

/// One specimen: the overlay, at the size the overlay would be, drawing
/// nothing but itself.
///
/// Hit testing is off. These are drawings inside a settings window, so a
/// pointer crossing one must not open the panel, hover a row or answer a
/// click; and with hit testing off the store never hears a pointer at all,
/// which is what keeps the shut specimen shut.
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

/// One numbered pin and what it points at.
///
/// Internal rather than private, with the two `pins` arrays below, for the one
/// assertion that cannot be made from outside the drawing: that no two pins on
/// a figure land on the same point. That is not a hypothetical — ③ and ⑤ sat
/// exactly on top of each other on the collapsed figure for as long as its key
/// named parts the bar had stopped drawing, and nothing failed.
struct AnatomyPin: Identifiable {
    enum Leader {
        /// A stem dropping from the pin to the specimen's top edge.
        case down(CGFloat)
        /// A stem rising from the specimen's bottom edge to the pin.
        case up(CGFloat)
        /// A stem reaching sideways, drawn over the specimen itself.
        case left(CGFloat)
        case right(CGFloat)
        /// One pin, two feet: a stem to a spine, and a foot off each end of it,
        /// opening rightwards from the margin.
        ///
        /// For the part that is two lines rather than one. A row's project and
        /// its title are a single reading — the project only says which thing
        /// the title belongs to — and two pins beside two lines `18` pt apart
        /// would have said they were two answers to different questions.
        case forkRight(stem: CGFloat, spread: CGFloat, foot: CGFloat)
    }

    let id: Int
    /// The pin's centre, in the specimen's own coordinates.
    let x: CGFloat
    let y: CGFloat
    let leader: Leader
    /// What the key says about it. Two to four words: the picture is the
    /// explanation, and this only has to name the part.
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

/// The pin itself: a numeral in a ring, in the window's control colours.
///
/// **Every pin stands on the card, never on the drawing.** Pins used to be laid
/// over the panel's black wherever a part had clear ground beside it, which
/// needed a second, lighter ink and put numerals on top of the very thing they
/// were naming. Both figures now keep their pins in the margins — above and
/// below the bar, left and right of the panel — so the specimens are drawn
/// exactly as the product draws them, with nothing of this window on top.
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

/// A hairline from a pin to its part.
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

/// The bracket a forked leader draws: a stem to a spine, and a foot off each
/// end of it, opening rightwards from the pin.
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

/// A specimen with its pins over it and the key underneath.
///
/// The key is three columns, because that is what fits two-to-four words at
/// `11` pt across `504` and still leaves the numerals aligned; six entries
/// therefore take two rows and five take two as well.
private struct PinnedFigure<Specimen: View>: View {
    let pins: [AnatomyPin]
    /// How much clear room the pins need above and below the specimen. Zero
    /// where every pin is drawn over it.
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

/// The collapsed bar, named part by part.
///
/// Every pin's `x` is asked of `PanelMetrics`, not measured off a drawing: the
/// leading group is packed from the leading edge, the middle from the group's
/// own reserved width, and the trailing slot from the trailing edge — so all
/// three can be composed from the same figures the bar itself is composed
/// from, and nothing here is a number somebody read off a screenshot.
///
/// **Redrawn for V2** (`compact-view-v2.md` §8, which parked this). The V1
/// version pinned six labels on a bar that has since stopped drawing four of
/// them: there is no mark per product, no dot column, and no badge in the
/// trailing wing. Two pins survive unchanged — the mark and the reading — and
/// the four that went are replaced by what actually stands there now: the two
/// numerals of the counts column, the Project in the pill's middle, and the
/// dot that says a finished turn is buried under a mark drawing something
/// else. The numbered key names each part without a secondary line.
struct CollapsedBarAnatomy: View {
    private let store = NotchSpecimen.shut

    /// The bar at its own size, which is what the pins are placed against.
    /// Internal for the assertion that they land on it.
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

    /// Where the parts stand, in the specimen's own coordinates. Internal for
    /// the assertion that no two of them land on one point.
    ///
    /// **The counts column is named from both sides.** Its two numerals are
    /// `16.6` pt apart on one x, so a pin apiece in the same margin would have
    /// been two numerals on top of each other — which is what the V1 pins had
    /// become, ③ and ⑤ landing on the same point once the dot column and the
    /// badges left. The column is one part with two rows, so it takes one pin
    /// from above and one from below: the leaders arrive at the numeral each
    /// belongs to, and the pair reads as the stack it is.
    var pins: [AnatomyPin] {
        let size = NotchSpecimen.windowSize(of: store)
        let shoulder = store.surfaceShoulderRadius
        let matrix = PanelMetrics.statusMatrixSize
        let leading = shoulder + PanelMetrics.expandedHorizontalPadding
        let mark = leading + matrix / 2
        // Both numerals are drawn from the column's own leading edge, one gap
        // past the mark; the subagents numeral is the narrower of the two and
        // its centre is under a point from this, so one x serves the stack and
        // keeps the two leaders in line.
        let counts = leading
            + matrix
            + PanelMetrics.aggregateCountsGap
            + PanelMetrics.countsDigitWidth / 2
        // The pill's middle stands past the leading group's *reserved* width —
        // the room the wing holds open at two digits whatever it is drawing —
        // and one notch clearance after it. **The pin goes on the name rather
        // than on the slot**: the name is drawn from the slot's leading edge
        // and faded off its trailing one, so on a short name the slot's own
        // middle is black. A name too long for the slot centres on the slot,
        // which is where it is anyway.
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
        // The slot is exactly what it draws, so both trailing pins are measured
        // from the panel edge inwards: the reading's ground ends one trailing
        // padding in, and the dot and its `8` stand before it.
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

/// The expanded panel, named part by part.
///
/// **Whole, and drawn a little under size.** It used to be cropped to two rows
/// with the rest faded away, because the panel and the bar and the legend were
/// competing for one window's height; splitting the flow in two gave this block
/// a page of its own, and the first thing that room bought back was the quota
/// footer. That footer was then three rate-limit rules and the day's tokens;
/// since `quota-footer-v2.md` §3 it is the day's tokens and the control that
/// opens the rest, so the room the split bought is now spent on drawing the
/// panel at rest rather than on a third of it.
///
/// The scale is for the card rather than for the height: at `700` in a `532`
/// card the panel would meet both edges and its shoulders overhang the
/// card's own padding, which reads as a layout fault instead of a specimen
/// on a page. `0.624` holds the drawing at the same `436.8` pt it was drawn
/// at before the panel widened, so the margin either side is unchanged; the
/// row copy is smaller for it, `~8.1` pt rather than the `11` pt the
/// original `520`-pt baseline and `0.84` gave.
struct ExpandedPanelAnatomy: View {
    private let store = NotchSpecimen.hovered

    static let scale: CGFloat = 0.624

    /// The panel as this page draws it. Internal for the assertion that the
    /// pins land on its edges.
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

    /// Every part named from the margins, in two columns.
    ///
    /// **Nothing is drawn on top of the panel.** Pins used to be laid over its
    /// black wherever a part had clear ground beside it, which worked and still
    /// put this window's furniture on the drawing it was teaching from — and
    /// left the numerals scattered across the specimen in no order the eye
    /// could follow. Outside, they read as a margin note: the left column names
    /// what a row leads with and what the footer says, the right column names
    /// the marks that end a line, and each is level with the thing it points
    /// at. It also settles the ink question — every pin is the card's, so there
    /// is one ring and one hairline rather than two of each.
    ///
    /// Placed in the panel's units and scaled with it, so the drawing and its
    /// pins cannot come apart, and internal for the assertion that no two of
    /// them land on one point. **Every y below is composed rather than
    /// measured**: a row's lines come from the four figures the row itself
    /// stacks, and the seam and the spend line from the one height both bars
    /// share, so a change to any of them arrives here on the same build.
    var pins: [AnatomyPin] {
        let scale = Self.scale
        let size = NotchSpecimen.windowSize(of: store)
        let header = store.compactHeight
        // A row's three lines. The block is centred in the row's `80`, so the
        // inset above it is half of what the lines leave.
        let lines = PanelMetrics.sessionRowCaptionHeight
            + PanelMetrics.sessionRowLineSpacing
            + PanelMetrics.sessionRowTitleHeight
            + PanelMetrics.sessionRowLineSpacing
            + PanelMetrics.sessionRowPreviewHeight
        let inset = (PanelMetrics.sessionRowHeight - lines) / 2
        let firstRow = header
        let secondRow = header + PanelMetrics.sessionRowHeight
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
        // A row's mark is centred on the **row**, not on any of its lines: it
        // is one control standing beside three lines rather than a fourth one.
        let firstMark = firstRow + PanelMetrics.sessionRowHeight / 2
        let secondMark = secondRow + PanelMetrics.sessionRowHeight / 2
        // What the live list is given, and the two closing bars under it. They
        // are the same `32` pt bar drawn twice (`quota-footer-v2.md` §2), so
        // both pins are placed on the middle of one height.
        let list = header + PanelMetrics.sessionViewportHeight(
            liveRowCount: store.sessions.count
        )
        let seam = list + PanelMetrics.recentSeamHeight / 2
        let footer = list + PanelMetrics.recentSectionHeight(
            retiredRowCount: store.recentDepartures.count,
            isRecentExpanded: store.isRecentExpanded
        )
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

        return [
            left(1, header / 2, "Same as above"),
            right(2, header / 2, "Settings"),
            // One pin, two feet: the Project only says which thing the title
            // is on, so they are one reading rather than two.
            AnatomyPin(
                id: 3,
                x: leftMargin * scale,
                y: (caption + title) / 2 * scale,
                leader: .forkRight(
                    stem: gutter - forkFoot,
                    spread: (title - caption) / 2 * scale,
                    foot: forkFoot
                ),
                label: "Product, Project, title"
            ),
            left(4, lastSaid, "The last thing said"),
            // The row's own control, and the one part of either drawing that
            // does something: the mark opens this Thread's request
            // (`answer-in-notch.md` §3).
            right(5, firstMark, "Answer it here"),
            right(6, secondMark, "Subagents"),
            // The seam between what is running and what has been and gone.
            left(7, seam, "Rows that have left"),
            left(8, spend, "Today’s tokens"),
            // The footer's other half, and the only control on it: the
            // rate-limit windows are behind this rather than drawn at rest.
            right(9, spend, "Rate limits")
        ]
    }

    /// How far either column stands off the panel, in the panel's own units.
    private static let margin: CGFloat = 30

    /// The left column, in the card's own margin beside the panel. Negative
    /// because the figure's origin is the specimen's leading edge.
    private var leftMargin: CGFloat { -Self.margin }

    /// The right column, the same distance past the trailing edge.
    private func rightMargin(of size: CGSize) -> CGFloat { size.width + Self.margin }

    /// The clear space a leader crosses, from the pin's own edge to the
    /// panel's.
    ///
    /// **In the drawing's units, and derived rather than written down.** A pin
    /// stands off the panel by a distance in the panel's units, which scales;
    /// its badge is `13` pt whatever the specimen is scaled to, which does not.
    /// A leader written as a third number and then scaled with the first ends
    /// up neither: at every scale this page has used it overshot by about `5`
    /// pt, laying a hairline across the black it is pointing at — on a figure
    /// whose whole rule is that nothing of this window is drawn on the
    /// specimen. Subtracting the badge's own half from the scaled margin is
    /// what makes the line stop exactly on the edge.
    private var gutter: CGFloat {
        Self.margin * Self.scale - AnatomyMetrics.pinSize / 2
    }

    /// How far a forked leader's two feet reach past its spine. In the
    /// drawing's units, like the gutter it is taken out of.
    private var forkFoot: CGFloat { 10 }
}

// MARK: - Opened

/// Shared by the open-request and Recent figures: the panel's own ground
/// with its header and footer cut away, and one scale for each specimen.
///
/// **A plate rather than a whole panel.** Every part page three names is inside
/// the row block, and drawing the header and the footer around each of them
/// three times would have repeated two things page two teaches — and spent the
/// height on them that this page spends on being legible instead. So the ground
/// is the panel's width with the row block inset by the panel's own gutter,
/// which is what the black behind a row actually is; the row and the section
/// drawn on it are the product's own views, unchanged.
private enum OpenedSpecimen {
    /// The panel's own inset around a row block.
    static var gutter: CGFloat { PanelMetrics.sessionRowGutter }

    /// Keep room for the pins within page two's card width. Their centres
    /// bisect each card margin in drawing units; their badges never scale.
    static let drawnWidth: CGFloat = 436.8
    static let margin = (OnboardingLayout.cardWidth - drawnWidth) / 4

    /// The clear space a leader crosses, badge edge to plate edge.
    static var gutterToPlate: CGFloat { margin - AnatomyMetrics.pinSize / 2 }

    /// The plate a figure is drawn on: the panel's width, and the specimen's
    /// own height with the panel's gutter above and below it.
    static func plateSize(store: MonitorStore, height: CGFloat) -> CGSize {
        let scale = scale(plateWidth: store.currentPanelSize.width)
        return CGSize(
            width: store.currentPanelSize.width * scale,
            height: (height + gutter * 2) * scale
        )
    }

    /// Reserve the pin margins before scaling the plate. Including margins
    /// in the denominator scaled space that the pins themselves never scale.
    static func scale(plateWidth: CGFloat) -> CGFloat {
        drawnWidth / plateWidth
    }

    /// Where the answers stand, measured inwards from the row's trailing edge.
    ///
    /// The answer row is the field, then the refusal where the form has one,
    /// then the affirmative — each hugging its own word
    /// (``PanelMetrics/drawnAnswerControlWidth(_:)``), `8` apart. So the
    /// affirmative is placed from the edge and everything else from it.
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

/// An open-request or Recent figure on the panel's ground, with its pins in
/// the left margin and along the bottom.
///
/// **Left and below rather than left and right**, which is page two's pair.
/// The parts these figures name are a body in the middle of a row and three
/// controls side by side at the foot of it, and three pins in one column would
/// land on top of each other — the fault §7.1 records. A row is short enough to
/// have a bottom margin to give, which a `740` pt panel is not.
private struct OpenedFigure<Specimen: View>: View {
    let store: MonitorStore
    let pins: [AnatomyPin]
    /// The specimen's own height, in the panel's units.
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
            // Drawn at the panel's own size and scaled as one object, so the
            // ground and what stands on it cannot come apart.
            .frame(
                width: store.currentPanelSize.width,
                height: height + OpenedSpecimen.gutter * 2,
                alignment: .topLeading
            )
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: plate.width, height: plate.height, alignment: .topLeading)
            // Drawings inside a settings window: a pointer crossing one must
            // not hover a row, arm an answer or take a click.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A permission request, open: what the mark on page two leads to.
///
/// The same row page two draws shut — same title, same request — so the two
/// figures are one row seen in its two states rather than two rows that
/// resemble each other.
struct OpenCommandAnatomy: View {
    private let store = NotchSpecimen.openedSpecimens().command

    /// How tall the open row is, which the store composes from the request's
    /// own layout.
    private var height: CGFloat { store.openRowHeight ?? PanelMetrics.sessionRowHeight }

    /// The plate it is drawn on. Internal, with ``pins``, for the assertion
    /// that they land on its edges and not on each other.
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
        let shape = store.openSession?.request?.answerRow
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

    /// How tall the open row is, which the store composes from the request's
    /// own layout.
    private var height: CGFloat { store.openRowHeight ?? PanelMetrics.sessionRowHeight }

    /// The plate it is drawn on. Internal, with ``pins``, for the assertion
    /// that they land on its edges and not on each other.
    var specimenSize: CGSize {
        OpenedSpecimen.plateSize(store: store, height: height)
    }

    var body: some View {
        OpenedFigure(store: store, pins: pins, height: height) {
            if let session = store.openSession {
                OpenRow(session: session)
            }
        }
        // Each example has its own draft despite sharing a specimen Thread ID.
        // Recreate the native answer field when switching examples.
        .id(lesson)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(lesson.rawValue). \(lesson.explanation) The example has a long description with Show more, an answer field and Send."
        )
    }

    var pins: [AnatomyPin] {
        let scale = OpenedSpecimen.scale(plateWidth: store.currentPanelSize.width)
        let rowWidth = PanelMetrics.sessionViewportWidth(
            panelWidth: store.currentPanelSize.width
        )
        let shape = store.openSession?.request?.answerRow
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

        // One pin over the whole list rather than one per answer: they are one
        // part with as many rows as the product sent, and a numeral beside each
        // would have said they were separate questions. The same bracket, and
        // the same argument, as the caption and title on page two.
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
                    label: lesson == .typedAnswer ? "Choices set aside" : "Select, then Send"
                )
            )
        }

        if let field = centres?.field {
            pins.append(
                below(3, field, lesson == .typedAnswer ? "Your words take priority" : "Or type your answer", scale: scale, body: body)
            )
        }
        if let affirmative = centres?.affirmative {
            pins.append(below(4, affirmative, "Send, or ⏎", scale: scale, body: body))
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

/// Where an open row's parts stand, composed from the same figures the row
/// stacks them with.
///
/// Nothing here is measured off a drawing: the row is `12.5` of air, the
/// caption, the title, the body, whatever is left, and the answer row. Asking
/// the store for the body's own layout is what makes the question's list and
/// the command's single line the same arithmetic.
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

    /// The middle of the whole body, which is what a one-line command wants.
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

    /// The option list's middle, and how far its bracket opens: half the
    /// distance between the first option's centre and the last one's.
    var optionList: (centre: CGFloat, spread: CGFloat)? {
        guard let body = store.openRowBody, !body.options.isEmpty else { return nil }
        let lines = CGFloat(body.lines.count)
            * PanelMetrics.requestLineHeight(for: body.setting)
        let top = bodyTop + lines + PanelMetrics.optionListSpacing
            + PanelMetrics.questionInstructionHeight
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

    /// The plate it is drawn on. Internal, with ``pins``, for the assertion
    /// that they land on its edges and not on each other.
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
    private var height: CGFloat {
        PanelMetrics.recentSectionHeight(
            retiredRowCount: store.recentDepartures.count,
            isRecentExpanded: store.isRecentExpanded
        )
    }

    var pins: [AnatomyPin] {
        let scale = OpenedSpecimen.scale(plateWidth: store.currentPanelSize.width)
        let plate = store.currentPanelSize.width
        let seam = PanelMetrics.recentSeamHeight / 2
        // The first retired row under it, and the trailing end of that row —
        // where a `2m` stands, one row padding in from its own edge.
        let firstRow = PanelMetrics.recentSeamHeight + PanelMetrics.retiredRowHeight / 2
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

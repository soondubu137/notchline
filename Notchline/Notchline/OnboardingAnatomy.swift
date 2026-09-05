// The two drawings the first-run window teaches from, and the pins that name
// their parts. See `figma-design.md` §7.
//
// **The specimens are the product, not pictures of it.** Each one is
// `NotchOverlayView` over a `MonitorStore` built from fixed snapshots, so the
// bar and the panel here are composed by the same views, from the same
// `PanelMetrics`, as the ones on the notch. Nothing is redrawn for onboarding
// and nothing can drift: a change to the mark, to the dot column, to a row's
// shape or to the width formula arrives in this window on the same build it
// arrives on the surface.
//
// The README's figures (`docs/assets/notch-anatomy-readme.png` and its pair)
// are the same teaching at four thousand pixels wide, with a column of prose
// either side. That layout does not survive a `532` pt content area — the
// labels would land near `4` pt — so the columns become numbered pins and a
// key of two-to-four words, and the artwork keeps its real size.
import Combine
import SwiftUI

/// The fixed moment both specimens draw: two products connected, one turn
/// stopped on an approval, one running, one finished.
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
    /// Four Codex rows and one Claude Code row, which between them are the
    /// whole of what the two drawings have to say:
    ///
    /// - The Codex turn is **running with a subagent stopped on a question**.
    ///   That is what makes the bar say `Approval needed`, what lights the blue
    ///   badge, and what puts a white ground under the first row's reading.
    /// - Three more Codex turns are **finished and nobody has looked at them**.
    ///   Four rows is one past ``PanelMetrics/sessionDotCap``, so the dot
    ///   column draws `dot · dot · dash`; and finished turns sitting under a
    ///   mark that is drawing something else is exactly the condition that sets
    ///   that column breathing.
    /// - The Claude Code turn is **finished with a subagent still working**.
    ///   That is the one row drawing a badge where a reading would be, and it
    ///   is also why this product's mark is on radar rather than lull: a thread
    ///   with a subagent in flight is still running (``MonitorAggregation``).
    private static func sessions(at now: Date) -> [AgentKind: [MonitoredSession]] {
        [
            .codex: [
                MonitoredSession(
                    agent: .codex,
                    threadID: "specimen-codex-approval",
                    turnID: "specimen-codex-approval-turn",
                    projectName: "notchline",
                    title: "Wire the quota footer to the fold control",
                    preview: "Reading PanelMetrics to find the trailing slot.",
                    status: .running,
                    // The clock this window teaches from starts here; see
                    // ``clockPeriod``.
                    startedAt: now,
                    runningSubagentCount: 3,
                    subagentsAwaitingApprovalCount: 1
                ),
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
            ],
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

    /// One of the finished Codex turns stacked up under the mark.
    private static func finished(
        id: String,
        title: String,
        preview: String,
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
    private static func snapshots(at now: Date) -> [AgentSnapshot] {
        let rows = sessions(at: now)
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
                remainingPercent: 72,
                resetsAt: now.addingTimeInterval(3 * 86_400 + 12 * 3_600),
                todayTokens: 310_100_000
            ),
            .claudeCode: QuotaSnapshot(
                windows: [
                    QuotaWindow(
                        label: "5 h",
                        remainingPercent: 40,
                        resetsAt: now.addingTimeInterval(2 * 3_600)
                    ),
                    QuotaWindow(
                        label: "7 d",
                        remainingPercent: 87,
                        resetsAt: now.addingTimeInterval(3 * 86_400 + 11 * 3_600)
                    )
                ],
                todayTokens: 208_600_000
            )
        ]
    }

    private static func makeStore(isExpanded: Bool, at now: Date) -> MonitorStore {
        // No services and no preferences: nothing is watched, no socket is
        // bound, no file of the user's is read, and the drawing cannot be
        // changed by what they happen to have chosen in Settings. See
        // `MonitorStore.makeShared()` for the same argument at launch.
        let store = MonitorStore(
            displays: [display],
            services: [],
            initialSnapshots: snapshots(at: now),
            preferences: nil
        )
        store.isExpanded = isExpanded
        return store
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

    /// Hand both stores the same rows again, started now.
    private static func restage() {
        let now = Date()
        let fresh = snapshots(at: now)
        staged.at = now
        staged.shut.restageSpecimen(fresh)
        staged.hovered.restageSpecimen(fresh)
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
private struct AnatomyPin: Identifiable {
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
    /// The one thing a name cannot carry: a part that also *moves*, and what
    /// the movement means. Drawn as a second, dimmer line under the label, and
    /// used once — nothing else on either specimen says anything by moving.
    var note: String?
}

private enum AnatomyMetrics {
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

                    VStack(alignment: .leading, spacing: 1) {
                        Text(pin.label)
                            .font(.system(size: 11))
                            .foregroundStyle(MacOSWindowColor.secondaryText)

                        if let note = pin.note {
                            Text(note)
                                .font(.system(size: 11))
                                .foregroundStyle(MacOSWindowColor.tertiaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
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
/// marks are packed from the leading edge and the reading is packed from the
/// trailing one, so both ends can be composed from the same figures the bar
/// itself is composed from. The one hand-placed offset is inside the status
/// word, which is drawn from a font this file does not own.
struct CollapsedBarAnatomy: View {
    private let store = NotchSpecimen.shut

    var body: some View {
        PinnedFigure(
            pins: pins,
            margin: (top: pinRow, bottom: pinRow),
            specimenSize: NotchSpecimen.windowSize(of: store)
        ) {
            NotchSpecimenView(store: store)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "The collapsed bar: one mark per product, a dot per open session, "
                + "the most urgent state, subagent counts and the longest "
                + "running turn."
        )
    }

    private var pinRow: CGFloat {
        AnatomyMetrics.pinSize + AnatomyMetrics.leaderClearance
    }

    /// Where the parts stand, in the specimen's own coordinates.
    private var pins: [AnatomyPin] {
        let size = NotchSpecimen.windowSize(of: store)
        let shoulder = store.surfaceShoulderRadius
        let matrix = PanelMetrics.statusMatrixSize
        let leading = shoulder + PanelMetrics.expandedHorizontalPadding
        // **The coordinates are V2's; the six labels below are not.** The bar
        // this specimen draws is one aggregate mark and two numerals, so the
        // pins land on what is actually there — the mark, the sessions numeral,
        // the subagents numeral under it, the reading — while four of the
        // labels still name V1 parts that no longer exist. The page is redrawn
        // in a change of its own (`compact-view-v2.md` §8); pinning correct
        // coordinates in the meantime keeps this file honest about the
        // geometry it composes from and lets the retired metrics go.
        let counts = leading
            + matrix
            + PanelMetrics.aggregateCountsGap
            + PanelMetrics.countsDigitWidth / 2
        let codexMatrix = leading + matrix / 2
        let codexDots = counts
        let claudeMatrix = counts
        let trailing = size.width - shoulder - PanelMetrics.expandedHorizontalPadding
        // The slot is exactly what it draws on both forms now, so both
        // trailing pins are measured from the panel edge inwards: the ink ends
        // one trailing padding in, and everything before it is the badges and
        // their `8`.
        var reading: CGFloat = 0
        if let timerText = store.compactTimerText {
            reading = PanelMetrics.drawnCompactReadingWidth(timerText)
        }
        let timer = trailing - reading / 2
        // **This page is knowingly stale** — `compact-view-v2.md` §8. The bar
        // it pins is now one aggregate mark and two numerals, so four of the
        // six labels below name things the collapsed surface no longer draws:
        // there is no mark per product, no dot column, and no badge in this
        // wing. It is redrawn in a change of its own; what is kept here is
        // enough to compile and to leave the two pins that are still true —
        // the mark and the reading — standing where they were.
        let badges = counts
        let top = -AnatomyMetrics.leaderClearance - AnatomyMetrics.pinSize / 2
        let bottom = store.currentPanelSize.height
            + AnatomyMetrics.leaderClearance
            + AnatomyMetrics.pinSize / 2
        let stem = AnatomyMetrics.leaderClearance

        return [
            AnatomyPin(id: 1, x: codexMatrix, y: top, leader: .down(stem), label: "Codex"),
            AnatomyPin(
                id: 2,
                x: claudeMatrix,
                y: top,
                leader: .down(stem),
                label: "Claude Code"
            ),
            AnatomyPin(
                id: 3,
                x: codexDots,
                y: bottom,
                leader: .up(stem),
                label: "One dot per session",
                // Three is the cap and the third becomes a dash past it, which
                // this specimen draws; what the key has to say is the breath,
                // because a still picture cannot.
                note: "Breathing: one finished"
            ),
            AnatomyPin(
                id: 4,
                x: codexMatrix,
                y: bottom,
                leader: .up(stem),
                label: "Most urgent state"
            ),
            AnatomyPin(id: 5, x: badges, y: bottom, leader: .up(stem), label: "Subagents"),
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
/// The scale is for the card rather than for the height: at `520` in a `532`
/// card the panel meets both edges and its shoulders overhang the card's own
/// padding, which reads as a layout fault instead of a specimen on a page.
/// `0.84` leaves a margin either side and keeps the row copy near `11` pt.
struct ExpandedPanelAnatomy: View {
    private let store = NotchSpecimen.hovered

    private static let scale: CGFloat = 0.84

    var body: some View {
        let scale = Self.scale
        let panel = NotchSpecimen.windowSize(of: store)
        let drawn = CGSize(width: panel.width * scale, height: panel.height * scale)

        return PinnedFigure(pins: pins, keyInset: 14, specimenSize: drawn) {
            NotchSpecimenView(store: store)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: drawn.width, height: drawn.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Hovering the notch opens one list of both products, most urgent "
                + "first: each row names its product, project and title, shows "
                + "what the agent is doing now, and ends in a reading that says "
                + "whether it is running or waiting on you — or in a badge, "
                + "where the turn has finished and a subagent has not. Under "
                + "the list, what both have spent today, and a control that "
                + "opens each product's rate-limit windows."
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
    /// pins cannot come apart.
    private var pins: [AnatomyPin] {
        let scale = Self.scale
        let size = NotchSpecimen.windowSize(of: store)
        let shoulder = store.surfaceShoulderRadius
        let header = store.compactHeight
        // A row's three lines, and the rows themselves.
        let firstRow = header
        let secondRow = header + PanelMetrics.sessionRowHeight
        let caption = firstRow + 22
        let title = firstRow + 40
        let progress = firstRow + 59
        // The footer, under the last row it leaves room for, and the one line
        // it draws at rest: today's spend, with the control on its trailing
        // end.
        let footer = header + PanelMetrics.sessionViewportHeight(
            forSessionCount: store.sessions.count
        )
        let spend = footer + PanelMetrics.quotaFoldControlSize / 2

        let placed: [(Int, CGFloat, CGFloat, AnatomyPin.Leader, String)] = [
            (1, leftMargin, header / 2, .right(gutter), "Same as above"),
            // One pin, two feet: the project only says which thing the title
            // is on, so they are one reading rather than two.
            (
                3,
                leftMargin,
                (caption + title) / 2,
                .forkRight(stem: gutter - 16, spread: (title - caption) / 2, foot: 16),
                "Product · project · title"
            ),
            (4, leftMargin, progress, .right(gutter), "Live progress"),
            (7, leftMargin, spend, .right(gutter), "Today’s tokens"),
            (2, rightMargin(of: size), header / 2, .left(gutter), "Settings"),
            (5, rightMargin(of: size), title, .left(gutter), "Waiting on you"),
            (6, rightMargin(of: size), secondRow + 40, .left(gutter), "Subagents"),
            // The footer's other half, and the only control on it: the
            // rate-limit windows are behind this rather than drawn at rest.
            (8, rightMargin(of: size), spend, .left(gutter), "Rate limits")
        ]

        return placed
            .sorted { $0.0 < $1.0 }
            .map { number, x, y, leader, label in
                AnatomyPin(
                    id: number,
                    x: x * scale,
                    y: y * scale,
                    leader: scaled(leader, by: scale),
                    label: label
                )
            }
    }

    /// The left column, in the card's own margin beside the panel. Negative
    /// because the figure's origin is the specimen's leading edge.
    private var leftMargin: CGFloat { -30 }

    /// The right column, the same distance past the trailing edge.
    private func rightMargin(of size: CGSize) -> CGFloat { size.width + 30 }

    /// The clear space a leader crosses between a pin and the panel's edge.
    private var gutter: CGFloat { 28 }

    /// A leader is drawn in the specimen's units too, so it shortens with it.
    private func scaled(_ leader: AnatomyPin.Leader, by scale: CGFloat) -> AnatomyPin.Leader {
        switch leader {
        case let .down(length): return .down(length * scale)
        case let .up(length): return .up(length * scale)
        case let .left(length): return .left(length * scale)
        case let .right(length): return .right(length * scale)
        case let .forkRight(stem, spread, foot):
            return .forkRight(stem: stem * scale, spread: spread * scale, foot: foot * scale)
        }
    }
}

#Preview("Collapsed bar") {
    CollapsedBarAnatomy().padding(24).frame(width: 532)
}

#Preview("Expanded panel") {
    ExpandedPanelAnatomy().padding(24).frame(width: 532)
}

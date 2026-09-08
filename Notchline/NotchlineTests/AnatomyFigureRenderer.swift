// Renders the two README anatomy specimens — the collapsed pill and the
// expanded panel — to PNG, from the product's own views.
//
// **The figures are the product, not pictures of it**, on exactly
// `OnboardingAnatomy.swift`'s terms: each specimen is `NotchOverlayView` over a
// `MonitorStore` built from fixed snapshots, at the size `PanelMetrics`
// composes for that state. Nothing is redrawn for the README, so a change to
// the mark, a row's shape or the footer's arithmetic reaches the figure on the
// build it reaches the notch on.
//
// Opt-in, because it writes files and takes a window: it does nothing unless
// `~/.notchline-anatomy-out` names a directory to write into. Delete that file
// and an ordinary test run is untouched.
//
//   echo -n /path/to/out > ~/.notchline-anatomy-out
//   xcodebuild test -project Notchline/Notchline.xcodeproj -scheme Notchline \
//     -destination 'platform=macOS' \
//     '-only-testing:NotchlineTests/AnatomyFigureRenderer/writesTheReadmeAnatomyFigures()'
//   rm ~/.notchline-anatomy-out
//
// **A file rather than an environment variable, and rather than a `print`.**
// Unit tests here run inside the app, and `TEST_RUNNER_`-prefixed variables do
// not reach it -- nor does anything it writes to stdout. A run gated on one
// passed in `0.000` s having written nothing, which is indistinguishable from a
// run that worked. `sizes.txt` beside the PNGs is the report, for the same
// reason.
//
// **Render it from a clean tree.** The figure is a drawing of `master`; taken
// with somebody else's work in progress in the tree it draws that instead. The
// panel's whole content shifted half a point the first time this was ignored.
import AppKit
import SwiftUI
import Testing

@testable import Notchline

@MainActor
struct AnatomyFigureRenderer {
    /// A display that is not a display: no notch, so both figures draw the
    /// self-contained pill rather than a shape that only reads wrapped around a
    /// cut-out.
    ///
    /// The bar height is the figure's own. `panelBandHeight` on a display with
    /// no cut-out is its menu bar, so it is set by the visible frame and by the
    /// fallback together.
    static func display(bandHeight: CGFloat) -> DisplayOption {
        DisplayOption(
            id: "anatomy-\(Int(bandHeight))",
            displayID: nil,
            ordinal: 1,
            name: "Anatomy",
            frame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900 - bandHeight),
            safeAreaInsets: NSEdgeInsets(),
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil,
            fallbackMenuBarHeight: bandHeight
        )
    }

    /// The pill is drawn on a `32` pt bar. At the `46` pt reference it is `241`
    /// wide and `46` tall, which reads as a slab rather than as something that
    /// hugs a menu bar; the width is composed from the wing and the reading and
    /// does not move with the height, so the whole of the change is proportion.
    static let compactDisplay = display(bandHeight: 32)
    /// The panel keeps the reference bar, which is what its band is measured at
    /// everywhere else in the documents.
    static let panelDisplay = display(bandHeight: PanelMetrics.referenceCompactHeight)

    // MARK: - The staged moment

    /// The approval the leading row is stopped on.
    ///
    /// A ticket is what makes ``AgentRequest/canBeAnswered`` true, and that is
    /// what puts `Approve` where the row's reading would be. Nothing can click
    /// it: the figure is rendered with hit testing off.
    static func approvalRequest() -> AgentRequest {
        AgentRequest(
            id: "anatomy-approval",
            toolName: "Bash",
            form: .command("npm run build -- --profile"),
            replyTicket: 0
        )
    }

    /// The three live rows both figures are staged from, plus the finished one
    /// the collapsed bar's dot speaks for.
    static func sessions(at now: Date, buriedFinish: Bool) -> [MonitoredSession] {
        var rows: [MonitoredSession] = [
            // Stopped on an approval a person could give here.
            MonitoredSession(
                agent: .codex,
                threadID: "anatomy-approval-thread",
                turnID: "anatomy-approval-turn",
                projectName: "notchline",
                title: "Rebuild the checkout bundle",
                preview: "Ready to run the production build.",
                status: .approvalNeeded,
                startedAt: now.addingTimeInterval(-158),
                request: approvalRequest()
            ),
            // Working, and the longest of them — which is what the collapsed
            // reading draws.
            MonitoredSession(
                agent: .claudeCode,
                threadID: "anatomy-running-thread",
                turnID: "anatomy-running-turn",
                projectName: "acme-api",
                title: "Add pagination to the orders endpoint",
                preview: "Writing the cursor tests.",
                status: .running,
                startedAt: now.addingTimeInterval(-74)
            ),
            // Finished, with two subagents still in flight — the one row that
            // draws a badge where a reading would be. A subagent outlives the
            // turn that spawned it, so this thread still counts as running.
            MonitoredSession(
                agent: .claudeCode,
                threadID: "anatomy-subagent-thread",
                turnID: "anatomy-subagent-turn",
                projectName: "design-tokens",
                title: "Migrate the colour tokens",
                preview: "Both palettes now read from one source.",
                status: .completed,
                startedAt: now.addingTimeInterval(-402),
                runningSubagentCount: 2,
                finishedAt: now.addingTimeInterval(-63)
            )
        ]
        if buriedFinish {
            rows.append(
                MonitoredSession(
                    agent: .codex,
                    threadID: "anatomy-finished-thread",
                    turnID: "anatomy-finished-turn",
                    projectName: "acme-web",
                    title: "Tidy the release notes",
                    preview: "Every entry now names its change.",
                    status: .completed,
                    startedAt: now.addingTimeInterval(-330),
                    finishedAt: now.addingTimeInterval(-201)
                )
            )
        }
        return rows
    }

    /// One product's rate-limit windows and what it has spent today: Codex
    /// publishes one window, Claude Code two, and the table draws each
    /// product's own rather than one number standing for both.
    static func quota(at now: Date) -> [AgentKind: QuotaSnapshot] {
        [
            .codex: QuotaSnapshot(
                windows: [
                    QuotaWindow(
                        label: "Weekly limit",
                        remainingPercent: 68,
                        resetsAt: now.addingTimeInterval(3 * 86_400 + 5 * 3_600)
                    )
                ],
                todayTokens: 184_300_000
            ),
            .claudeCode: QuotaSnapshot(
                windows: [
                    QuotaWindow(
                        label: "Current session",
                        remainingPercent: 41,
                        resetsAt: now.addingTimeInterval(2 * 3_600 + 12 * 60)
                    ),
                    QuotaWindow(
                        label: "All models",
                        remainingPercent: 83,
                        resetsAt: now.addingTimeInterval(4 * 86_400 + 6 * 3_600)
                    )
                ],
                todayTokens: 226_500_000
            )
        ]
    }

    static func store(
        isExpanded: Bool,
        buriedFinish: Bool,
        at now: Date,
        on display: DisplayOption
    ) -> MonitorStore {
        let rows = sessions(at: now, buriedFinish: buriedFinish)
        let quotas = quota(at: now)
        // No services and no preferences: nothing is watched, no socket bound,
        // no file of the user's read, and the drawing cannot be changed by
        // whatever they happen to have chosen in Settings.
        let store = MonitorStore(
            displays: [display],
            services: [],
            initialSnapshots: [AgentKind.codex, .claudeCode].map { agent in
                AgentSnapshot(
                    agent: agent,
                    availability: .ready,
                    sessions: rows.filter { $0.agent == agent },
                    quota: quotas[agent] ?? .unavailable,
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

    /// The Recent queue: three rows that left at three different ages, staged
    /// directly because a queue fed through the ordinary arrow would have every
    /// row departing at one instant and reading one age.
    static func departures(at now: Date) -> [RecentDeparture] {
        let left: [(id: String, project: String, title: String, ago: TimeInterval)] = [
            ("cache", "acme-api", "Cache the product catalogue", 3 * 60),
            ("flake", "acme-web", "Fix the flaky upload test", 21 * 60),
            ("docs", "design-tokens", "Document the spacing scale", 74 * 60)
        ]
        return left.map { row in
            RecentDeparture(
                session: MonitoredSession(
                    agent: .codex,
                    threadID: "anatomy-departed-\(row.id)",
                    turnID: "anatomy-departed-\(row.id)-turn",
                    projectName: row.project,
                    title: row.title,
                    preview: nil,
                    status: .completed,
                    startedAt: now.addingTimeInterval(-row.ago - 240),
                    finishedAt: now.addingTimeInterval(-row.ago - 30)
                ),
                departedAt: now.addingTimeInterval(-row.ago),
                reason: .read
            )
        }
    }

    // MARK: - Rendering

    /// The specimen at its own size, drawing nothing but itself.
    struct Specimen: View {
        let store: MonitorStore

        var body: some View {
            let size = CGSize(
                width: store.currentPanelSize.width + store.surfaceShoulderRadius * 2,
                height: store.currentPanelSize.height
            )
            NotchOverlayView()
                .environmentObject(store)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Draws a view into a PNG at the backing scale of the window it is hosted
    /// in.
    ///
    /// **A real window and `cacheDisplay`, not `ImageRenderer`.** The renderer
    /// takes a scale directly and needs no window, and it draws neither of the
    /// two things this figure exists for: a `ScrollView`'s content comes out
    /// empty, so every session row and every retired row was blank, and
    /// `NotchStatusMatrix` came out as SwiftUI's unsupported-view placeholder.
    /// What is left is the product's own AppKit draw of its own view tree.
    @discardableResult
    static func png<Content: View>(
        _ content: Content,
        size: CGSize,
        to url: URL
    ) throws -> CGSize {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.backgroundColor = .clear
        window.isOpaque = false
        // The overlay hangs over the menu bar and is dark whatever the user
        // runs; pinning the appearance keeps a figure from changing with
        // whatever the machine rendering it happens to be set to.
        window.appearance = NSAppearance(named: .darkAqua)
        // **The window is never ordered in.** It exists to give the hosting
        // view an appearance and a backing scale; `cacheDisplay` draws the view
        // tree itself and does not need it on screen -- the figure is byte for
        // byte the same either way. Ordering it front cost 27 failures
        // elsewhere in the suite, on the tests that synthesise events at their
        // own offscreen hosting views: a real window in front of them takes the
        // hit that was meant for theirs.
        host.layoutSubtreeIfNeeded()
        // Turns of the loop, so SwiftUI has committed a layout pass and the
        // lists have filled before anything is cached out of them.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)

        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    /// How tall a view wants to be at a given width.
    static func fittingHeight<Content: View>(_ content: Content, width: CGFloat) throws -> CGFloat {
        let host = NSHostingView(rootView: content.frame(width: width))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    // MARK: - The test

    @Test
    func writesTheReadmeAnatomyFigures() throws {
        // The destination, named by a file rather than by an environment
        // variable: `TEST_RUNNER_`-prefixed variables do not reach a unit test
        // hosted inside this app, and neither does anything it prints -- so a
        // run gated on one passed in 0.000 s and wrote nothing, which is
        // indistinguishable from a run that worked.
        let marker = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".notchline-anatomy-out")
        guard let named = try? String(contentsOf: marker, encoding: .utf8) else { return }
        let directory = named.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !directory.isEmpty else { return }
        let out = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let now = Date()
        var report: [String] = []

        // The collapsed pill: the mark, the counts, the Project, the dot for a
        // finished turn nobody has read, and the longest running turn.
        let compact = Self.store(
            isExpanded: false,
            buriedFinish: true,
            at: now,
            on: Self.compactDisplay
        )
        let compactSize = CGSize(
            width: compact.currentPanelSize.width + compact.surfaceShoulderRadius * 2,
            height: compact.currentPanelSize.height
        )
        let compactPixels = try Self.png(
            Specimen(store: compact),
            size: compactSize,
            to: out.appendingPathComponent("compact.png")
        )
        report.append("compact: \(compactSize.width) x \(compactSize.height) -> \(compactPixels.width) x \(compactPixels.height)")

        // The expanded panel, with both folds open, staged from the same
        // moment the pill is: the counts on the two figures are one reading,
        // and the fourth row -- the finished one the pill's dot speaks for --
        // is the one the rail says is below.
        let panel = Self.store(
            isExpanded: true,
            buriedFinish: true,
            at: now,
            on: Self.panelDisplay
        )
        panel.stageSpecimenQueue(Self.departures(at: now))
        panel.isRecentExpanded = true
        panel.isQuotaExpanded = true
        let panelSize = CGSize(
            width: panel.currentPanelSize.width + panel.surfaceShoulderRadius * 2,
            height: panel.currentPanelSize.height
        )
        let panelPixels = try Self.png(
            Specimen(store: panel),
            size: panelSize,
            to: out.appendingPathComponent("expanded.png")
        )
        report.append("expanded: \(panelSize.width) x \(panelSize.height) -> \(panelPixels.width) x \(panelPixels.height)")

        // And the card the README carries: both figures, named.
        let card = ReadmeAnatomyCard(compact: compact, expanded: panel)
        let cardWidth = ReadmeAnatomyCard.width(compact: compact, expanded: panel)
        let cardHeight = try Self.fittingHeight(card, width: cardWidth)
        let cardPixels = try Self.png(
            card,
            size: CGSize(width: cardWidth, height: cardHeight),
            to: out.appendingPathComponent("anatomy.png")
        )
        report.append("anatomy: \(cardWidth) x \(cardHeight) -> \(cardPixels.width) x \(cardPixels.height)")

        try report.joined(separator: "\n").write(
            to: out.appendingPathComponent("sizes.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}

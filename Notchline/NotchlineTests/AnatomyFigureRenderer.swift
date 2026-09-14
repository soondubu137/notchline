// Renders the README anatomy specimens to PNG from the product's own views: `NotchOverlayView`
// over a `MonitorStore` of fixed snapshots, at `PanelMetrics` sizes.
//
// Opt-in: runs only when `~/.notchline-anatomy-out` names an output directory, and deletes that
// file on start. Run it alone (it holds the main actor for seconds; ~27 answering tests time
// out beside it) and from a clean tree:
//
//   echo -n /path/to/out > ~/.notchline-anatomy-out
//   xcodebuild test -project Notchline/Notchline.xcodeproj -scheme Notchline \
//     -destination 'platform=macOS' \
//     '-only-testing:NotchlineTests/AnatomyFigureRenderer/writesTheReadmeAnatomyFigures()'
//
// `sizes.txt` beside the PNGs is the report (stdout does not reach tests hosted in the app).
import AppKit
import SwiftUI
import Testing

@testable import Notchline

@MainActor
struct AnatomyFigureRenderer {
    /// No notch, so both figures draw the self-contained pill.
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

    /// The pill is drawn on a `32` pt bar; at the `46` pt reference it reads as a slab.
    static let compactDisplay = display(bandHeight: 32)
    static let panelDisplay = display(bandHeight: PanelMetrics.referenceCompactHeight)

    // MARK: - The staged moment

    /// Never `nil`: `hasCompletedOnboarding` would read `false` and the first-run window would
    /// hold key status, failing `27` answering tests. A throwaway suite carries only that key.
    static let preferences: UserDefaults = {
        let defaults = UserDefaults(suiteName: "notchline.anatomy.figure")!
        defaults.set(true, forKey: "hasCompletedOnboarding")
        return defaults
    }()


    /// A ticket makes ``AgentRequest/canBeAnswered`` true, which draws `Approve`.
    static func approvalRequest() -> AgentRequest {
        AgentRequest(
            id: "anatomy-approval",
            toolName: "Bash",
            form: .command("npm run build -- --profile"),
            answerHandle: AnswerHandle(ticket: 0)
        )
    }

    static func sessions(at now: Date, buriedFinish: Bool) -> [MonitoredSession] {
        var rows: [MonitoredSession] = [
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
            // Working, and the longest — the collapsed reading. Codex's so that, grouped by product, the
            // approval, timer and subagent badge rows are all drawn: `32 + 80 + 80 + 32 + 80` fills the
            // grouped viewport exactly.
            MonitoredSession(
                agent: .codex,
                threadID: "anatomy-running-thread",
                turnID: "anatomy-running-turn",
                projectName: "acme-api",
                title: "Add pagination to the orders endpoint",
                preview: "Writing the cursor tests.",
                status: .running,
                startedAt: now.addingTimeInterval(-74)
            ),
            // Finished with two subagents in flight, so the thread still counts as running.
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
                // The row the rail reports and the collapsed dot speaks for; the one thing below the fold.
                MonitoredSession(
                    agent: .claudeCode,
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
        // No services and no preferences: nothing watched, no socket, no user file or Settings read.
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
            preferences: Self.preferences
        )
        store.isExpanded = isExpanded
        return store
    }

    /// Staged directly: the ordinary path would give every row one departure instant.
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

    /// Not `ImageRenderer`: it draws `ScrollView` content empty and `NotchStatusMatrix` as a
    /// placeholder.
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
        // Pinned dark so the figure does not follow the rendering machine's appearance.
        window.appearance = NSAppearance(named: .darkAqua)
        // Never ordered in: `cacheDisplay` does not need it, and a front window stole hits from other
        // tests' offscreen hosting views (27 failures).
        host.layoutSubtreeIfNeeded()
        // Let SwiftUI commit a layout pass and fill the lists before caching.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)

        // Hosted views go first (an open row carries an `NSTextView`). Not `close()`:
        // `isReleasedWhenClosed` over-releases a locally held window and crashes the test host.
        window.contentView = nil

        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    static func fittingHeight<Content: View>(_ content: Content, width: CGFloat) throws -> CGFloat {
        let host = NSHostingView(rootView: content.frame(width: width))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    // MARK: - The test

    @Test
    func writesTheReadmeAnatomyFigures() throws {
        // A file, not an env var: `TEST_RUNNER_` variables and stdout do not reach tests hosted in the
        // app, so a gated run passed in 0.000 s having written nothing.
        let marker = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".notchline-anatomy-out")
        guard let named = try? String(contentsOf: marker, encoding: .utf8) else { return }
        // Spent as read: the switch costs the answering tests their timing while set.
        try? FileManager.default.removeItem(at: marker)
        let directory = named.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !directory.isEmpty else { return }
        let out = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let now = Date()
        var report: [String] = []

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

        // Staged from the same moment as the pill, so both figures show one reading.
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

        let card = ReadmeAnatomyCard(compact: compact, expanded: panel)
        let cardWidth = ReadmeAnatomyCard.width(compact: compact, expanded: panel)
        let cardHeight = try Self.fittingHeight(card, width: cardWidth)
        let cardPixels = try Self.png(
            card,
            size: CGSize(width: cardWidth, height: cardHeight),
            to: out.appendingPathComponent("anatomy.png")
        )
        report.append("anatomy: \(cardWidth) x \(cardHeight) -> \(cardPixels.width) x \(cardPixels.height)")

        let answering = ApprovalSpecimens.staged(at: now)
        let answeringCard = ReadmeAnsweringCard(staged: answering)
        let answeringWidth = ReadmeAnsweringCard.width(answering)
        let answeringHeight = try Self.fittingHeight(answeringCard, width: answeringWidth)
        let answeringPixels = try Self.png(
            answeringCard,
            size: CGSize(width: answeringWidth, height: answeringHeight),
            to: out.appendingPathComponent("anatomy-answering.png")
        )
        report.append(
            "anatomy-answering: \(answeringWidth) x \(answeringHeight) -> "
                + "\(answeringPixels.width) x \(answeringPixels.height)"
        )

        try report.joined(separator: "\n").write(
            to: out.appendingPathComponent("sizes.txt"),
            atomically: true,
            encoding: .utf8
        )
    }
}

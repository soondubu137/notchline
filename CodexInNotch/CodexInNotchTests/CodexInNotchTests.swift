import AppKit
import Combine
import Darwin
import Testing
@testable import CodexInNotch

struct CodexInNotchTests {
    /// A no-notch panel is one width, always. It used to measure itself, so it
    /// resized whenever the status changed or a turn started or finished —
    /// which on a menu bar reads as flicker rather than information.
    @Test @MainActor
    func noNotchCompactIsOneFixedWidthPerConfiguredAgentSet() {
        for configured in [Set([AgentKind.codex]), Set(AgentKind.allCases)] {
            var widths: Set<CGFloat> = []
            var heights: Set<CGFloat> = []
            for status in MonitorStatus.allCases {
                for agent in configured {
                    for timerText in [nil, "0:07", "1:23", "1:02:03"] as [String?] {
                        for barHeight in [CGFloat(46), 38, 24] {
                            let size = PanelMetrics.size(
                                geometry: .noNotch,
                                isExpanded: false,
                                statusReadoutText: status.compactDisplayName(for: agent),
                                timerText: timerText,
                                centerOcclusionWidth: 0,
                                compactHeight: barHeight,
                                configuredAgents: configured
                            )
                            widths.insert(size.width)
                            heights.insert(size.height)
                        }
                    }
                }
            }

            #expect(widths == [PanelMetrics.fixedCompactWidth(for: configured)])
            // Height still follows the menu bar; only width came loose.
            #expect(heights == [46, 38, 24])
        }
    }

    /// The fixed width is a reservation, so it has to actually fit every state —
    /// and not be so generous that it is reserving space nothing can use.
    @Test @MainActor
    func fixedCompactWidthFitsEveryStatusForEveryConfiguredAgent() {
        for configured in [Set([AgentKind.codex]), Set(AgentKind.allCases)] {
            var widest: CGFloat = 0
            for status in MonitorStatus.allCases {
                for agent in configured {
                    let needed = PanelMetrics.compactChromeWidth
                        + PanelMetrics.compactContentWidth(for: status, agent: agent)
                    #expect(needed <= PanelMetrics.fixedCompactWidth(for: configured))
                    widest = max(widest, needed)
                }
            }
            // Only the rounding up should separate them.
            #expect(PanelMetrics.fixedCompactWidth(for: configured) - widest < 1)
        }
    }

    /// Today's panel, for today's user, to the point.
    ///
    /// This is the anti-regression for the whole two-product refactor. A Codex
    /// user's surface has to be exactly what it was, and the way that quietly
    /// stops being true is geometry: every width is derived by folding over
    /// `MonitorStatus.allCases`, so anything that adds a case, renames a label,
    /// or lets a second product into the fold moves a panel nobody asked to
    /// move.
    @Test @MainActor
    func aCodexOnlyConfigurationHasTodaysExactPanelGeometry() {
        let codexOnly = PanelMetrics.fixedCompactWidth(for: [.codex])
        let both = PanelMetrics.fixedCompactWidth(for: Set(AgentKind.allCases))

        // Configuring a second product must not reach back into the first
        // product's panel.
        #expect(PanelMetrics.fixedCompactWidth(for: [.codex]) == codexOnly)
        #expect(both >= codexOnly)

        for occlusion in [CGFloat(0), 200, 320] {
            let codexExpanded = PanelMetrics.expandedWidth(
                centerOcclusionWidth: occlusion,
                configuredAgents: [.codex]
            )
            #expect(
                PanelMetrics.expandedWidth(
                    centerOcclusionWidth: occlusion,
                    configuredAgents: [.codex]
                ) == codexExpanded
            )
        }

        // The four sentences a Codex user reads are unchanged word for word.
        #expect(MonitorStatus.connecting.displayName(for: .codex) == "Connecting to Codex")
        #expect(MonitorStatus.updateAgent.displayName(for: .codex) == "Update Codex")
        #expect(
            MonitorStatus.unsupportedVersion.displayName(for: .codex)
                == "Codex version unsupported"
        )
        #expect(MonitorStatus.disconnected.displayName(for: .codex) == "Codex disconnected")
        #expect(MonitorStatus.updateAgent.compactDisplayName(for: .codex) == "Update Codex")
        #expect(
            MonitorAvailability.disconnected.emptyListMessage(for: .codex)
                == "Codex disconnected"
        )
    }

    /// Which status sets the compact width, named rather than measured.
    ///
    /// Pinning the *identity* of the widest status rather than a golden float
    /// keeps the assertion true across system font changes while still failing
    /// the moment the maximiser moves.
    ///
    /// It does move, and that is worth having written down. For Codex the
    /// widest state is `Approval`, which wins by reserving the timer slot as
    /// well as its label — no untimed state can overtake it. Adding Claude Code
    /// hands the title to an *untimed* state: "Update Claude Code" is a longer
    /// run of text than "Approval" plus a timer, so the widest compact label
    /// stops being a state that can even be counting. Measured on this machine:
    /// Approval + timer 112.3, "Update Claude Code" 124.8, so the no-notch pill
    /// goes 189 → 202 for a user who configures both.
    ///
    /// That is a real product question for the two-product surface rather than
    /// a bug — the compact label names the most urgent state across both
    /// products, so it cannot silently drop the product name the way the other
    /// compact labels do — but it must not be discovered by someone wondering
    /// why a measured width disagrees with the one in Figma.
    @Test @MainActor
    func theWidestCompactStatusIsTimedForCodexAndUntimedOnceClaudeCodeIsConfigured() {
        func widest(for agent: AgentKind) -> MonitorStatus? {
            MonitorStatus.allCases.max {
                PanelMetrics.compactContentWidth(for: $0, agent: agent)
                    < PanelMetrics.compactContentWidth(for: $1, agent: agent)
            }
        }

        #expect(widest(for: .codex) == .approvalNeeded)
        #expect(widest(for: .codex)?.canShowElapsed == true)

        let widestUntimedForCodex = MonitorStatus.allCases
            .filter { !$0.canShowElapsed }
            .map { PanelMetrics.compactContentWidth(for: $0, agent: .codex) }
            .max() ?? 0
        #expect(
            widestUntimedForCodex
                < PanelMetrics.compactContentWidth(for: .approvalNeeded, agent: .codex)
        )

        #expect(widest(for: .claudeCode) == .updateAgent)
        #expect(widest(for: .claudeCode)?.canShowElapsed == false)
        #expect(
            PanelMetrics.fixedCompactWidth(for: Set(AgentKind.allCases))
                > PanelMetrics.fixedCompactWidth(for: [.codex])
        )
    }

    /// The notch's label is shorter than the panel's because the matrix beside
    /// it already says a turn wants the user.
    @Test @MainActor
    func compactLabelsAreShorterThanTheirFullForm() {
        #expect(MonitorStatus.inputNeeded.compactDisplayName(for: .codex) == "Input")
        #expect(MonitorStatus.approvalNeeded.compactDisplayName(for: .codex) == "Approval")
        #expect(MonitorStatus.inputNeeded.displayName(for: .codex) == "Input needed")
        #expect(MonitorStatus.approvalNeeded.displayName(for: .codex) == "Approval needed")

        for status in MonitorStatus.allCases {
            for agent in AgentKind.allCases {
                #expect(
                    status.compactDisplayName(for: agent).count
                        <= status.displayName(for: agent).count
                )
                #expect(!status.compactDisplayName(for: agent).isEmpty)
            }
        }
    }

    @Test @MainActor
    func notchedCompactDropsItsTrailingWingUntilATurnIsTimed() {
        let occlusion: CGFloat = 200
        func size(timerText: String?) -> CGSize {
            PanelMetrics.size(
                geometry: .notched,
                isExpanded: false,
                statusReadoutText: "Running",
                timerText: timerText,
                centerOcclusionWidth: occlusion,
                compactHeight: 46
            )
        }

        // Idle: leading wing + the cut-out, and nothing to its right — an empty
        // trailing wing would render as a second, fake notch.
        let idle = size(timerText: nil)
        let leading = PanelMetrics.compactLeadingWidth(
            statusReadoutText: "Running",
            showsStatusText: false
        ) + PanelMetrics.expandedNotchClearance
        #expect(abs(idle.width - (leading + occlusion)) <= 1)

        #expect(size(timerText: "1:23").width > idle.width)
    }

    @Test @MainActor
    func notchedCompactPanelStaysPinnedToTheCutOut() {
        func offset(timerText: String?) -> CGFloat {
            PanelMetrics.compactHorizontalOffset(
                geometry: .notched,
                isExpanded: false,
                statusReadoutText: "Running",
                timerText: timerText,
                centerOcclusionWidth: 200
            )
        }

        // With no trailing wing the panel hangs left of the cut-out, so it has
        // to be displaced left of the display centre to stay aligned.
        #expect(offset(timerText: nil) < 0)
        // A trailing wing pulls it back toward centre.
        #expect(offset(timerText: "1:23") > offset(timerText: nil))
        // Nothing to pin to when there is no notch.
        #expect(
            PanelMetrics.compactHorizontalOffset(
                geometry: .noNotch,
                isExpanded: false,
                statusReadoutText: "Running",
                timerText: "1:23",
                centerOcclusionWidth: 0
            ) == 0
        )
    }

    /// The compact panel measures itself from rendered text, so only the widths
    /// that are pure constants are pinned. The rest are asserted as the
    /// relationships that actually matter: an exact pixel copied from a font
    /// metric goes red on the next system update without anything being wrong.
    @Test @MainActor
    func compactGeometryComposesTheNotchWings() {
        func width(
            geometry: DisplayGeometry,
            timerText: String?,
            compactHeight: CGFloat
        ) -> CGFloat {
            PanelMetrics.size(
                geometry: geometry,
                isExpanded: false,
                statusReadoutText: "Running",
                timerText: timerText,
                centerOcclusionWidth: geometry == .notched ? 200 : 0,
                compactHeight: compactHeight
            ).width
        }

        // Leading wing plus the cut-out and nothing else. No text is measured on
        // a notched compact panel, so this width is exact -- and it is the one
        // number a Figma variant can be checked against directly.
        let notchedIdle = width(geometry: .notched, timerText: nil, compactHeight: 46)
        #expect(notchedIdle == 249)

        // Timing a turn adds the trailing wing, and nothing but the trailing wing.
        let notchedTimed = width(geometry: .notched, timerText: "1:23", compactHeight: 46)
        let trailingWing = PanelMetrics.compactTrailingWidth(timerText: "1:23")
            + PanelMetrics.expandedNotchClearance
        #expect(abs((notchedTimed - notchedIdle) - trailingWing) <= 1)

        // Only the notched panel composes its width from content. A no-notch
        // one is fixed, so the same two cases must not move it at all.
        #expect(
            width(geometry: .noNotch, timerText: nil, compactHeight: 24)
                == width(geometry: .noNotch, timerText: "1:23", compactHeight: 24)
        )
    }

    /// The indicator is a fixed size derived from the label, not a share of the
    /// menu bar. It scaled with the bar while the 13pt label did not, so the two
    /// drifted apart between a 46pt and a 24pt bar.
    @Test @MainActor
    func statusMatrixIsAFixedSizeDerivedFromTheLabel() {
        // 92:72 indicator-to-text at loaders.wtf, applied to the 13pt label.
        #expect(abs(PanelMetrics.statusMatrixSize - 13 * (92.0 / 72.0)) < 0.02)
    }

    @Test
    func noNotchCornerRadiusScalesBelowNativeNotchHeight() {
        #expect(
            PanelMetrics.surfaceCornerRadius(
                geometry: .noNotch,
                menuBarHeight: 46
            ) == 10
        )
        #expect(
            PanelMetrics.surfaceCornerRadius(
                geometry: .noNotch,
                menuBarHeight: 38
            ) == 10
        )
        #expect(
            PanelMetrics.surfaceCornerRadius(
                geometry: .noNotch,
                menuBarHeight: 19
            ) == 5
        )

        let standardExternalDisplayRadius = PanelMetrics.surfaceCornerRadius(
            geometry: .noNotch,
            menuBarHeight: 24
        )
        #expect(abs(standardExternalDisplayRadius - 6.316) < 0.001)
    }

    @Test
    func notchedSurfaceKeepsCurrentCornerRadius() {
        #expect(
            PanelMetrics.surfaceCornerRadius(
                geometry: .notched,
                menuBarHeight: 24
            ) == 10
        )
    }

    @Test @MainActor
    func expandedSizeUsesWiderBaselineAndKeepsCompactHeaderHeight() {
        let noNotchSize = PanelMetrics.size(
            geometry: .noNotch,
            isExpanded: true,
            statusReadoutText: "Running",
            timerText: nil,
            centerOcclusionWidth: 0,
            compactHeight: 24
        )
        let notchedSize = PanelMetrics.size(
            geometry: .notched,
            isExpanded: true,
            statusReadoutText: "Running",
            timerText: nil,
            centerOcclusionWidth: 200,
            compactHeight: 38
        )

        #expect(noNotchSize.width == 520)
        #expect(notchedSize.width > noNotchSize.width)
        #expect(noNotchSize.height == 24 + PanelMetrics.expandedContentHeight)
        #expect(notchedSize.height == 38 + PanelMetrics.expandedContentHeight)
    }

    @Test
    func expandedWidthKeepsEveryStatusNameClearOfWideNotchForEveryConfiguredAgent() {
        let centerOcclusionWidth: CGFloat = 220
        for configured in [Set([AgentKind.codex]), Set(AgentKind.allCases)] {
            let width = PanelMetrics.expandedWidth(
                centerOcclusionWidth: centerOcclusionWidth,
                configuredAgents: configured
            )
            let availableSideWidth = (width - centerOcclusionWidth) / 2

            // Only the status readout flanks the notch now; usage moved to the
            // footer.
            for status in MonitorStatus.allCases {
                for agent in configured {
                    let requiredWidth = PanelMetrics.expandedHorizontalPadding
                        + PanelMetrics.expandedStatusReadoutWidth(
                            status: status,
                            agent: agent
                        )
                        + PanelMetrics.expandedNotchClearance
                    #expect(requiredWidth <= availableSideWidth)
                }
            }
        }
    }

    @Test
    func todayTokenUsageUsesStandardCompactNumberFormatting() {
        #expect(UsageSummaryFormatter.compactTokenCount(13_400) == "13.4K")
        #expect(UsageSummaryFormatter.compactTokenCount(323_000) == "323K")
        #expect(UsageSummaryFormatter.compactTokenCount(2_800_000) == "2.8M")
        #expect(UsageSummaryFormatter.compactTokenCount(1_030_000_000) == "1.03B")
        #expect(UsageSummaryFormatter.compactTokenCount(999) == "999")
    }

    /// The reset window now reads as a remaining *duration* rather than a count
    /// of calendar days: "Resets today" was equally true at 00:30 and 23:30.
    @Test
    func resetTextReadsRemainingDaysAndHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 13,
            hour: 10
        )))
        func text(afterHours hours: Int) throws -> String {
            let resetsAt = try #require(
                calendar.date(byAdding: .hour, value: hours, to: now)
            )
            return UsageSummaryFormatter.resetText(
                resetsAt: resetsAt,
                now: now,
                calendar: calendar
            )
        }

        #expect(try text(afterHours: 8) == "Resets in 8 hours")
        #expect(try text(afterHours: 1) == "Resets in 1 hour")
        #expect(try text(afterHours: 24) == "Resets in 1 day")
        #expect(try text(afterHours: 24 * 3) == "Resets in 3 days")
        #expect(try text(afterHours: 24 * 3 + 4) == "Resets in 3 days 4 hours")
        #expect(try text(afterHours: 25) == "Resets in 1 day 1 hour")
        #expect(
            UsageSummaryFormatter.resetText(resetsAt: now, now: now) == "Resets now"
        )
        #expect(
            UsageSummaryFormatter.resetText(resetsAt: nil, now: now)
                == "Reset unavailable"
        )
    }

    @Test
    func elapsedFormatterRollsOverIntoHours() throws {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        func elapsed(_ seconds: TimeInterval) -> String? {
            SessionElapsedFormatter.elapsed(
                since: start,
                now: start.addingTimeInterval(seconds)
            )
        }

        #expect(elapsed(0) == "0:00")
        #expect(elapsed(7) == "0:07")
        #expect(elapsed(83) == "1:23")
        #expect(elapsed(3599) == "59:59")
        #expect(elapsed(3600) == "1:00:00")
        #expect(elapsed(3723) == "1:02:03")
        // No start time, and clock skew, both read as "not timed".
        #expect(SessionElapsedFormatter.elapsed(since: nil, now: start) == nil)
        #expect(elapsed(-5) == nil)
    }

    /// VoiceOver reads the drawn `1:23` as twenty-three past one, so the spoken
    /// form is a separate string rather than the same one handed to the label.
    @Test
    func spokenElapsedReadsAsADurationRatherThanAClockTime() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        func spoken(_ seconds: TimeInterval) -> String? {
            SessionElapsedFormatter.spokenElapsed(
                since: start,
                now: start.addingTimeInterval(seconds)
            )
        }

        #expect(spoken(0) == "0 秒")
        #expect(spoken(7) == "7 秒")
        #expect(spoken(83) == "1 分 23 秒")
        // Empty units are dropped, never spoken as "0 分".
        #expect(spoken(120) == "2 分")
        #expect(spoken(3600) == "1 小时")
        #expect(spoken(3723) == "1 小时 2 分 3 秒")
        #expect(SessionElapsedFormatter.spokenElapsed(since: nil, now: start) == nil)
        #expect(spoken(-5) == nil)
    }

    /// The wait *is* the part worth timing: a turn parked on an approval is the
    /// one the user needs a number for, so the clock does not pause for it.
    @Test @MainActor
    func timerKeepsCountingWhileATurnWaitsForApproval() async throws {
        let clock = TestClock()
        let store = makeIdleStore(clock: clock)
        let startedAt = clock.now()

        store.applyForTesting(
            makeSessionSnapshot([
                makeSession(status: .running, startedAt: startedAt)
            ]),
            observedAt: clock.now()
        )
        // Let the ticking task park on the clock before moving it, or the
        // advance happens before there is a sleeper to wake.
        await clock.settle()
        await clock.advance(by: 30)
        #expect(store.compactTimerText == "0:30")

        // Same turn, now blocked on a human. Nothing about the count changes.
        store.applyForTesting(
            makeSessionSnapshot([
                makeSession(status: .approvalNeeded, startedAt: startedAt)
            ]),
            observedAt: clock.now()
        )
        await clock.settle()
        await clock.advance(by: 90)

        #expect(store.compactTimerText == "2:00")
        #expect(store.elapsedText(for: try #require(store.sessions.first)) == "2:00")
    }

    @Test @MainActor
    func notchTimesTheLongestRunningUnfinishedTurn() async {
        let clock = TestClock()
        let store = makeIdleStore(clock: clock)
        let now = clock.now()

        store.applyForTesting(
            makeSessionSnapshot([
                // Oldest of all, but finished — a stopped clock cannot be the
                // longest-running one.
                makeSession(
                    threadID: "done",
                    status: .completed,
                    startedAt: now.addingTimeInterval(-600)
                ),
                makeSession(
                    threadID: "waiting",
                    status: .approvalNeeded,
                    startedAt: now.addingTimeInterval(-300)
                ),
                makeSession(
                    threadID: "running",
                    status: .running,
                    startedAt: now.addingTimeInterval(-60)
                )
            ]),
            observedAt: now
        )
        await clock.settle()

        #expect(store.compactTimerText == "5:00")
        #expect(store.spokenLongestElapsedText == "5 分")
    }

    @Test @MainActor
    func completedTurnStopsItsTimerAndReleasesTheNotch() async throws {
        let clock = TestClock()
        let store = makeIdleStore(clock: clock)
        let startedAt = clock.now().addingTimeInterval(-125)

        store.applyForTesting(
            makeSessionSnapshot([
                makeSession(status: .completed, startedAt: startedAt)
            ]),
            observedAt: clock.now()
        )
        await clock.settle()

        // The start time is still known; the contract is that it stops being
        // counted, not that the row forgets when it began.
        let session = try #require(store.sessions.first)
        #expect(session.startedAt == startedAt)
        #expect(store.elapsedText(for: session) == nil)
        #expect(store.spokenElapsedText(for: session) == nil)
        #expect(store.compactTimerText == nil)
    }

    /// A monitor with nothing to count must not wake once a second to find that
    /// out -- the resource cost of a per-second timer is the whole reason the
    /// product deferred one.
    @Test @MainActor
    func elapsedTickingRunsOnlyWhileATurnIsTimed() async {
        let clock = TestClock()
        let store = makeIdleStore(clock: clock)
        await clock.settle()

        #expect(clock.sleeperCount == 0)

        let startedAt = clock.now()
        store.applyForTesting(
            makeSessionSnapshot([
                makeSession(status: .running, startedAt: startedAt)
            ]),
            observedAt: clock.now()
        )
        await clock.settle()
        #expect(clock.sleeperCount == 1)

        await clock.advance(by: 5)
        #expect(store.compactTimerText == "0:05")
        #expect(clock.sleeperCount == 1)

        store.applyForTesting(
            makeSessionSnapshot([
                makeSession(status: .completed, startedAt: startedAt)
            ]),
            observedAt: clock.now()
        )
        await clock.settle()

        #expect(clock.sleeperCount == 0)
    }

    /// The readout the ticking task publishes goes stale while it is stopped, so
    /// the next turn has to reset it -- otherwise its first second is measured
    /// against an instant from before it began and renders blank.
    @Test @MainActor
    func turnStartingAfterAnIdleStretchTimesFromItsOwnStart() async {
        let clock = TestClock()
        let store = makeIdleStore(clock: clock)
        await clock.advance(by: 600)

        let startedAt = clock.now()
        store.applyForTesting(
            makeSessionSnapshot([
                makeSession(status: .running, startedAt: startedAt)
            ]),
            observedAt: startedAt
        )

        // Correct before the first tick, not merely once ticking catches up.
        #expect(store.compactTimerText == "0:00")

        await clock.settle()
        await clock.advance(by: 1)
        #expect(store.compactTimerText == "0:01")
    }

    @Test @MainActor
    func runningUsesItsStatusNameAndKeepsQuotaVisible() {
        let display = makeDisplay(
            id: "notched",
            ordinal: 1,
            menuBarHeight: 38,
            hasNotch: true
        )
        let store = MonitorStore(displays: [display])
        store.applyForTesting(
            AgentSnapshot(
                availability: .ready,
                sessions: [
                    MonitoredSession(
                        threadID: "running",
                        turnID: "turn-running",
                        projectName: "Chats",
                        title: "Running task",
                        preview: nil,
                        status: .running,
                        startedAt: Date().addingTimeInterval(-384)
                    )
                ],
                quota: QuotaSnapshot(remainingPercent: 72, resetsAt: nil),
                diagnostic: nil
            )
        )

        #expect(store.sessions.count == 1)
        #expect(store.compactStatusReadoutText == "Running")
        #expect(store.tokenRemainingPercent == 72)

        store.applyForTesting(
            AgentSnapshot(
                availability: .ready,
                sessions: [
                    MonitoredSession(
                        threadID: "input",
                        turnID: "turn",
                        projectName: "Chats",
                        title: "Question",
                        preview: nil,
                        status: .inputNeeded,
                        startedAt: Date().addingTimeInterval(-10)
                    )
                ],
                quota: QuotaSnapshot(remainingPercent: 72, resetsAt: nil),
                diagnostic: nil
            )
        )

        #expect(store.sessions.count == 1)
        // The notch shows the short form; the panel still says "Input needed".
        #expect(store.compactStatusReadoutText == "Input")
        #expect(store.statusDisplayName == "Input needed")
        #expect(store.tokenRemainingPercent == 72)
    }

    @Test @MainActor
    func clearingSessionListHidesCurrentTurnsButAllowsNewTurns() async {
        let currentTurn = MonitoredSession(
            threadID: "thread",
            turnID: "turn-1",
            projectName: "Chats",
            title: "Current turn",
            preview: nil,
            status: .completed,
            startedAt: Date()
        )
        let store = MonitorStore(
            initialSnapshot: AgentSnapshot(
                availability: .ready,
                sessions: [currentTurn],
                quota: .unavailable,
                diagnostic: nil
            )
        )

        let didClear = await store.clearSessionsAndWait()

        #expect(didClear)
        #expect(store.sessions.isEmpty)
        #expect(store.status == .idle)
        #expect(store.lastIntegrationMessage.contains("Codex 会话未被删除"))

        store.applyForTesting(
            AgentSnapshot(
                availability: .ready,
                sessions: [currentTurn],
                quota: .unavailable,
                diagnostic: nil
            )
        )
        #expect(store.sessions.isEmpty)

        let nextTurn = MonitoredSession(
            threadID: "thread",
            turnID: "turn-2",
            projectName: "Chats",
            title: "Next turn",
            preview: nil,
            status: .running,
            startedAt: Date()
        )
        store.applyForTesting(
            AgentSnapshot(
                availability: .ready,
                sessions: [currentTurn, nextTurn],
                quota: .unavailable,
                diagnostic: nil
            )
        )

        #expect(store.sessions == [nextTurn])
        #expect(store.status == .running)
    }

    /// Recheck must report what is true now, not what was true before.
    ///
    /// It used to call a refresh that returned immediately whenever an
    /// automatic one happened to be in flight, so the button finished at once
    /// and handed back the status it already had (CR-008).
    @Test @MainActor
    func recheckWaitsForASnapshotThatAccountsForItOwnRequest() async throws {
        let service = GatedMonitoringStub()
        await service.setHoldsSnapshots(true)
        await service.setStatus(.reviewRequired)

        let store = MonitorStore(
            service: service,
            initialSnapshot: AgentSnapshot(
                availability: .connecting,
                sessions: [],
                quota: .unavailable,
                diagnostic: nil,
                setupStatus: .notInstalled
            )
        )

        // Wait until the automatic refresh is genuinely in flight and stuck.
        for _ in 0 ..< 200 where await service.snapshotCount() < 1 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(await service.snapshotCount() == 1)

        // The world changes while that refresh is parked.
        await service.setStatus(.active)

        // The user presses Recheck now.
        let recheck = Task { await store.recheckIntegrationAndWait() }
        try await Task.sleep(nanoseconds: 50_000_000)

        await service.setHoldsSnapshots(false)
        await service.releaseHeldSnapshots()

        let reported = await recheck.value
        #expect(
            reported == .active,
            "Recheck reported \(reported); it returned before a fresh read"
        )
        #expect(await service.snapshotCount() >= 2)
        store.stopMonitoring()
    }

    /// A watcher signal arriving mid-refresh must still produce a refresh.
    @Test @MainActor
    func aChangeSignalDuringARefreshIsServedRatherThanDropped() async throws {
        let service = GatedMonitoringStub()
        await service.setHoldsSnapshots(true)

        let store = MonitorStore(
            service: service,
            initialSnapshot: AgentSnapshot(
                availability: .connecting,
                sessions: [],
                quota: .unavailable,
                diagnostic: nil,
                setupStatus: .notInstalled
            )
        )
        for _ in 0 ..< 200 where await service.snapshotCount() < 1 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        // Three signals land while the first read is stuck. They collapse into
        // one follow-up -- coalesced, but not lost.
        store.refreshNow()
        store.refreshNow()
        store.refreshNow()

        await service.setHoldsSnapshots(false)
        await service.releaseHeldSnapshots()

        for _ in 0 ..< 200 where await service.snapshotCount() < 2 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(
            await service.snapshotCount() >= 2,
            "a signal that arrived during a refresh was dropped"
        )
        store.stopMonitoring()
    }

    /// Flipping the switch faster than the work completes must still end where
    /// the user left it, and must not run two changes at once.
    @Test @MainActor
    func rapidIntegrationTogglesConvergeOnTheLastRequestedState() async throws {
        let service = GatedMonitoringStub()
        await service.setStatus(.notInstalled)
        let store = MonitorStore(
            service: service,
            initialSnapshot: AgentSnapshot(
                availability: .setupRequired,
                sessions: [],
                quota: .unavailable,
                diagnostic: nil,
                setupStatus: .notInstalled
            )
        )

        store.setIntegrationEnabled(true)
        store.setIntegrationEnabled(false)
        let settled = await store.setIntegrationEnabledAndWait(true)

        #expect(settled)
        #expect(store.integrationSwitchIsOn, "the last flip must decide")
        #expect(store.hookSetupStatus.isIntegrationEnabled)
        #expect(await service.installCount() >= 1)
        #expect(
            await service.observedOverlappingIntegrationChange == false,
            "install and remove overlapped"
        )
        store.stopMonitoring()
    }

    /// And the same in the other direction, ending off.
    @Test @MainActor
    func rapidIntegrationTogglesConvergeWhenTheLastRequestIsOff() async throws {
        let service = GatedMonitoringStub()
        await service.setStatus(.notInstalled)
        let store = MonitorStore(
            service: service,
            initialSnapshot: AgentSnapshot(
                availability: .setupRequired,
                sessions: [],
                quota: .unavailable,
                diagnostic: nil,
                setupStatus: .notInstalled
            )
        )

        store.setIntegrationEnabled(true)
        let settled = await store.setIntegrationEnabledAndWait(false)

        #expect(settled)
        #expect(!store.integrationSwitchIsOn)
        #expect(!store.hookSetupStatus.isIntegrationEnabled)
        #expect(
            await service.observedOverlappingIntegrationChange == false,
            "install and remove overlapped"
        )
        store.stopMonitoring()
    }

    @Test @MainActor
    func integrationMasterSwitchInstallsAndRemovesTheManagedSet() async {
        let service = IntegrationMonitoringStub()
        let store = MonitorStore(
            service: service,
            initialSnapshot: AgentSnapshot(
                availability: .setupRequired,
                sessions: [],
                quota: .unavailable,
                diagnostic: nil
            )
        )

        let installed = await store.installIntegrationHooksAndWait()

        #expect(installed)
        #expect(store.integrationSwitchIsOn)
        #expect(store.hookSetupStatus == .reviewRequired)
        #expect(await service.installCount() == 1)

        let removed = await store.removeIntegrationAndWait()

        #expect(removed)
        #expect(!store.integrationSwitchIsOn)
        #expect(store.hookSetupStatus == .notInstalled)
        #expect(store.availability == .setupRequired)
        #expect(await service.removeCount() == 1)
    }

    @Test
    func statusDomainsSeparateSystemAndSessionStates() {
        // The session states are the contract; the system states are not
        // counted here, because a raw count only says a number changed and
        // never which half of the domain it changed in.
        #expect(SessionStatus.allCases == [
            .running,
            .inputNeeded,
            .approvalNeeded,
            .completed
        ])
        // No system state may leak into the session vocabulary, and vice versa.
        let sessionStatuses = Set(SessionStatus.allCases.map(\.monitorStatus))
        #expect(
            sessionStatuses == [.running, .inputNeeded, .approvalNeeded, .completed]
        )
        #expect(
            Set(MonitorStatus.allCases).subtracting(sessionStatuses)
                == [
                    .idle,
                    .setupRequired,
                    .connecting,
                    .updateAgent,
                    .unsupportedVersion,
                    .disconnected
                ]
        )

        // A system state that names a product is told which one; the shared
        // ones never take a name at all.
        #expect(MonitorStatus.setupRequired.displayName(for: .codex) == "Set up integration")
        #expect(MonitorStatus.inputNeeded.displayName(for: .codex) == "Input needed")
        #expect(MonitorStatus.approvalNeeded.displayName(for: .codex) == "Approval needed")
        #expect(MonitorStatus.inputNeeded.displayName(for: .claudeCode) == "Input needed")
        #expect(MonitorStatus.connecting.displayName(for: .codex) == "Connecting to Codex")
        #expect(
            MonitorStatus.connecting.displayName(for: .claudeCode)
                == "Connecting to Claude Code"
        )
        #expect(
            MonitorStatus.unsupportedVersion.displayName(for: .codex)
                == "Codex version unsupported"
        )
        #expect(MonitorStatus.disconnected.displayName(for: .codex) == "Codex disconnected")
        // Nobody's problem in particular: two unhealthy products must not be
        // reported as one of them.
        #expect(MonitorStatus.disconnected.displayName(for: nil) == "Disconnected")
    }

    @Test
    func sessionStatusMachineAllowsOnlyTheFourDesignedTransitions() {
        #expect(SessionStatus.running.transitioned(on: .inputNeeded) == .inputNeeded)
        #expect(SessionStatus.inputNeeded.transitioned(on: .inputNeeded) == .inputNeeded)
        #expect(SessionStatus.inputNeeded.transitioned(on: .approvalNeeded) == .inputNeeded)
        #expect(SessionStatus.inputNeeded.transitioned(on: .running) == .running)
        #expect(SessionStatus.running.transitioned(on: .approvalNeeded) == .approvalNeeded)
        #expect(SessionStatus.approvalNeeded.transitioned(on: .inputNeeded) == .approvalNeeded)
        #expect(SessionStatus.approvalNeeded.transitioned(on: .running) == .running)

        for status in SessionStatus.allCases {
            #expect(status.transitioned(on: .completed) == .completed)
        }
        #expect(SessionStatus.completed.transitioned(on: .running) == .completed)
        #expect(SessionStatus.completed.transitioned(on: .inputNeeded) == .completed)
        #expect(SessionStatus.completed.transitioned(on: .approvalNeeded) == .completed)
    }

    @Test
    func onlyCompleteHookStatusesTurnTheIntegrationSwitchOn() {
        #expect(!HookSetupStatus.notInstalled.isIntegrationEnabled)
        #expect(!HookSetupStatus.repairRequired.isIntegrationEnabled)
        #expect(HookSetupStatus.reviewRequired.isIntegrationEnabled)
        #expect(HookSetupStatus.active.isIntegrationEnabled)
    }

    @Test @MainActor
    func selectingDisplayAdaptsGeometryAndMenuBarHeight() {
        let notchedDisplay = makeDisplay(
            id: "notched",
            ordinal: 1,
            menuBarHeight: 38,
            hasNotch: true
        )
        let externalDisplay = makeDisplay(
            id: "external",
            ordinal: 2,
            menuBarHeight: 24,
            hasNotch: false
        )
        let store = MonitorStore(displays: [notchedDisplay, externalDisplay])

        #expect(store.selectedDisplayID == notchedDisplay.id)
        #expect(store.geometry == .notched)
        #expect(notchedDisplay.centerOcclusionWidth == 200)
        #expect(store.currentPanelSize.height == 38)

        store.selectDisplay(id: externalDisplay.id)

        #expect(store.selectedDisplayID == externalDisplay.id)
        #expect(store.geometry == .noNotch)
        #expect(store.currentPanelSize.height == 24)
    }

    @Test @MainActor
    func removedDisplayFallsBackThenRestoresPreferredDisplay() {
        let primaryDisplay = makeDisplay(
            id: "primary",
            ordinal: 1,
            menuBarHeight: 38,
            hasNotch: true
        )
        let externalDisplay = makeDisplay(
            id: "external",
            ordinal: 2,
            menuBarHeight: 24,
            hasNotch: false
        )
        let store = MonitorStore(displays: [primaryDisplay, externalDisplay])
        store.selectDisplay(id: externalDisplay.id)
        store.isExpanded = true

        store.refreshDisplays([primaryDisplay])

        #expect(store.selectedDisplayID == primaryDisplay.id)
        #expect(store.geometry == .notched)
        #expect(!store.isExpanded)

        store.refreshDisplays([primaryDisplay, externalDisplay])

        #expect(store.selectedDisplayID == externalDisplay.id)
        #expect(store.geometry == .noNotch)
    }

    @Test @MainActor
    func selectedDisplayPreferencePersistsAcrossStoreInstances() throws {
        let suiteName = "CodexInNotchTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let primaryDisplay = makeDisplay(
            id: "primary",
            ordinal: 1,
            menuBarHeight: 38,
            hasNotch: true
        )
        let externalDisplay = makeDisplay(
            id: "external",
            ordinal: 2,
            menuBarHeight: 24,
            hasNotch: false
        )
        let firstStore = MonitorStore(
            displays: [primaryDisplay, externalDisplay],
            displayPreferences: defaults
        )

        firstStore.selectDisplay(id: externalDisplay.id)

        let restoredStore = MonitorStore(
            displays: [primaryDisplay, externalDisplay],
            displayPreferences: defaults
        )
        #expect(restoredStore.selectedDisplayID == externalDisplay.id)
        #expect(restoredStore.geometry == .noNotch)
    }

    @Test @MainActor
    func unavailableMenuBarMeasurementUsesSystemFallback() {
        let display = makeDisplay(
            id: "auto-hidden-menu-bar",
            ordinal: 1,
            menuBarHeight: 0,
            hasNotch: false
        )
        let store = MonitorStore(displays: [display])

        #expect(store.geometry == .noNotch)
        #expect(store.compactHeight == 22)
    }

    @Test
    func panelFramesStayTopAttachedAndCentered() {
        let screenFrame = NSRect(x: 1_440.5, y: -120, width: 1_919, height: 1_080)
        let compactSize = CGSize(width: 348, height: 46)
        let expandedSize = CGSize(
            width: 520,
            height: PanelMetrics.expandedHeight(compactHeight: 46)
        )

        for step in 0 ... 20 {
            let progress = CGFloat(step) / 20
            let size = CGSize(
                width: compactSize.width
                    + (expandedSize.width - compactSize.width) * progress,
                height: compactSize.height
                    + (expandedSize.height - compactSize.height) * progress
            )
            let frame = OverlayPanelLayout.frame(
                on: screenFrame,
                panelSize: size
            )

            #expect(frame.midX == screenFrame.midX)
            #expect(frame.maxY == screenFrame.maxY)
        }
    }

    @Test @MainActor
    func hoverExpandsAndCollapsesBothGeometries() async throws {
        let displays = [
            makeDisplay(
                id: "notched",
                ordinal: 1,
                menuBarHeight: 38,
                hasNotch: true
            ),
            makeDisplay(
                id: "external",
                ordinal: 2,
                menuBarHeight: 24,
                hasNotch: false
            )
        ]

        for display in displays {
            let clock = TestClock()
            let store = MonitorStore(displays: [display], clock: clock)

            store.pointerEnteredPanel()
            // The dwell must actually be observed: expanding before the delay
            // elapses would make the panel twitch on a passing pointer.
            await clock.advance(by: MonitorTiming.standard.hoverExpandDelay / 2)
            #expect(!store.isExpanded)
            await clock.advance(by: MonitorTiming.standard.hoverExpandDelay)
            #expect(store.isExpanded)

            store.pointerExitedPanel()
            await clock.advance(by: MonitorTiming.standard.hoverCollapseDelay / 2)
            #expect(store.isExpanded)
            await clock.advance(by: MonitorTiming.standard.hoverCollapseDelay)
            #expect(!store.isExpanded)
        }
    }

    @Test @MainActor
    func aDisconnectedAgentClearsOnlyItsOwnRowsAndReachesTheAggregateOnlyWhenNoAgentHasSessions() {
        let session = MonitoredSession(
            threadID: "thread",
            turnID: "turn",
            projectName: "Chats",
            title: "Stale task",
            preview: nil,
            status: .running,
            startedAt: Date()
        )

        // The unhealthy product's own rows go with it, and with nothing left
        // to show, its availability is what the surface says.
        #expect(
            AgentSnapshotMerge.merge([
                makeAgentSnapshot(.codex, availability: .disconnected)
            ]).status == .disconnected
        )

        // But it only reaches the summary when no product has anything to
        // show. A live turn somewhere else outranks it: the user is being told
        // something wants them, which is true, rather than being told the
        // surface is broken, which is not.
        #expect(
            AgentSnapshotMerge.merge([
                makeAgentSnapshot(.codex, availability: .disconnected),
                makeAgentSnapshot(.claudeCode, sessions: [session])
            ]).status == .running
        )

        // And a product that is merely unhealthy never speaks over one that is
        // being watched properly and simply has nothing to report.
        #expect(
            AgentSnapshotMerge.merge([
                makeAgentSnapshot(.codex, availability: .disconnected),
                makeAgentSnapshot(.claudeCode, availability: .ready)
            ]).status == .idle
        )
    }

    /// Two products may mint the same thread and turn ids without colliding.
    ///
    /// This id keys the dismissed set, the terminal-unread gate and SwiftUI's
    /// row identity, and thread and turn ids are each product's own invention —
    /// nothing stops Claude Code from using a string a Codex thread already
    /// uses. A collision would silently make one row dismiss, hide or
    /// re-render the other. The literal format this replaces was only ever a
    /// proxy for that.
    @Test @MainActor
    func sessionIDsFromTwoAgentsWithTheSameThreadAndTurnDoNotCollide() {
        func session(agent: AgentKind) -> MonitoredSession {
            MonitoredSession(
                agent: agent,
                threadID: "thread",
                turnID: "turn",
                projectName: "Chats",
                title: "Task",
                preview: nil,
                status: .running,
                startedAt: nil
            )
        }

        let ids = Set(AgentKind.allCases.map { session(agent: $0).id })
        #expect(ids.count == AgentKind.allCases.count)

        // Hiding content must not silently re-home a row to another product.
        let hidden = session(agent: .claudeCode).hidingContent()
        #expect(hidden.agent == .claudeCode)
        #expect(hidden.id == session(agent: .claudeCode).id)
    }

    /// Codex leads, always — the order is a product rule, not a sort result.
    @Test @MainActor
    func agentOrderIsFixedWithCodexLeading() {
        #expect(AgentKind.allCases == [.codex, .claudeCode])
        #expect(AgentKind.codex < AgentKind.claudeCode)
        #expect(AgentKind.allCases.shuffled().sorted() == [.codex, .claudeCode])
    }

    /// Availability only speaks for the aggregate while it is not ready.
    ///
    /// Naming this makes the early return a contract instead of an
    /// implementation detail, so a later change to it reads as the deliberate
    /// product decision it would be.
    @Test @MainActor
    func availabilitySpeaksForTheAggregateOnlyWhenNoProductHasRows() {
        let running = MonitoredSession(
            threadID: "thread",
            turnID: "turn",
            projectName: "Chats",
            title: "Running task",
            preview: nil,
            status: .running,
            startedAt: Date()
        )

        let unready: [MonitorAvailability] = [
            .setupRequired,
            .connecting,
            .updateAgent,
            .unsupportedVersion,
            .disconnected
        ]
        // With one product, availability speaks whenever it has no rows —
        // unchanged from the single-source surface, including the onboarding
        // path where nothing is installed yet.
        for availability in unready {
            #expect(
                AgentSnapshotMerge.merge([
                    makeAgentSnapshot(.codex, availability: availability)
                ]).status == availability.status
            )
        }

        #expect(
            AgentSnapshotMerge.merge([
                makeAgentSnapshot(.codex, sessions: [running])
            ]).status == .running
        )
        #expect(AgentSnapshotMerge.merge([makeAgentSnapshot(.codex)]).status == .idle)

        // A second product the user has only just discovered reports
        // setupRequired. It must not take over the notch from a product that is
        // running a turn, and it must not take over from one that is simply
        // idle either.
        #expect(
            AgentSnapshotMerge.merge([
                makeAgentSnapshot(.codex, sessions: [running]),
                makeAgentSnapshot(.claudeCode, availability: .setupRequired)
            ]).status == .running
        )
        #expect(
            AgentSnapshotMerge.merge([
                makeAgentSnapshot(.codex),
                makeAgentSnapshot(.claudeCode, availability: .setupRequired)
            ]).status == .idle
        )
        // With no product ready, the most actionable one speaks: something to
        // do outranks something to wait for.
        #expect(
            AgentSnapshotMerge.merge([
                makeAgentSnapshot(.codex, availability: .connecting),
                makeAgentSnapshot(.claudeCode, availability: .setupRequired)
            ]).status == .setupRequired
        )
    }

    /// The row comparator has to be a total order, or the list reshuffles.
    ///
    /// Two rows sharing a status and a start time compare equal in both
    /// directions, and `sorted(by:)` is not stable — so the same snapshot can
    /// render in a different order on the next refresh. One source makes that
    /// tie rare. A second one, reporting whole-millisecond start times and
    /// discovering a batch of sessions at once, makes it routine. A list that
    /// reorders while it is being read is exactly the flicker the fixed compact
    /// width exists to prevent.
    @Test @MainActor
    func theMergedOrderIsTotalSoEqualKeysNeverSwapBetweenRefreshes() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let sessions = (0 ..< 6).map { index in
            MonitoredSession(
                threadID: "thread-\(index)",
                turnID: "turn",
                projectName: "Chats",
                title: "Task \(index)",
                preview: nil,
                status: index.isMultiple(of: 2) ? .running : .completed,
                startedAt: startedAt
            )
        }

        let forward = sessions.sorted(by: MonitorAggregation.rowOrder)
        let backward = sessions.reversed().sorted(by: MonitorAggregation.rowOrder)
        #expect(forward.map(\.id) == backward.map(\.id))

        // Same again across products, where the tie is not hypothetical: two
        // providers discovering sessions at the same moment report the same
        // whole-millisecond start time.
        let mixed = AgentKind.allCases.map { agent in
            MonitoredSession(
                agent: agent,
                threadID: "same-thread",
                turnID: "same-turn",
                projectName: "codex-in-notch",
                title: "Task",
                preview: nil,
                status: .running,
                startedAt: startedAt
            )
        }
        #expect(
            mixed.reversed().sorted(by: MonitorAggregation.rowOrder).map(\.agent)
                == [.codex, .claudeCode]
        )
    }

    /// A merge is not a replacement: one product going quiet or unhealthy must
    /// leave the other product's rows exactly where they were.
    @Test @MainActor
    func oneAgentsFailureDoesNotClearTheOthersSessions() {
        let session = MonitoredSession(
            agent: .claudeCode,
            threadID: "cc",
            turnID: "turn",
            projectName: "codex-in-notch",
            title: "Still running",
            preview: nil,
            status: .running,
            startedAt: Date(timeIntervalSince1970: 2_000)
        )

        let merged = AgentSnapshotMerge.merge([
            makeAgentSnapshot(.codex, availability: .disconnected),
            makeAgentSnapshot(.claudeCode, sessions: [session])
        ])

        #expect(merged.sessions == [session])
        #expect(merged.status == .running)
        #expect(merged.agent(.codex)?.availability == .disconnected)
        #expect(merged.agent(.claudeCode)?.availability == .ready)
    }

    /// Once there are two products, a diagnostic has to say whose it is.
    ///
    /// "Disconnected" unattributed reads as a statement about the whole
    /// surface, which is the one thing it must not say while the other product
    /// is working.
    @Test @MainActor
    func aDiagnosticNamesItsProductOnlyWhenThereIsMoreThanOne() {
        let alone = AgentSnapshotMerge.merge([
            makeAgentSnapshot(.codex, diagnostic: "App Server 无响应")
        ])
        #expect(alone.diagnostic == "App Server 无响应")

        let together = AgentSnapshotMerge.merge([
            makeAgentSnapshot(.codex, diagnostic: "App Server 无响应"),
            makeAgentSnapshot(.claudeCode)
        ])
        #expect(together.diagnostic == "Codex：App Server 无响应")
    }

    @Test @MainActor
    func transientDisconnectDoesNotReplaceTheLastReadySnapshot() {
        let baseDate = Date(timeIntervalSince1970: 1_000)
        let session = MonitoredSession(
            threadID: "thread",
            turnID: "turn",
            projectName: "Chats",
            title: "Running task",
            preview: nil,
            status: .running,
            startedAt: baseDate
        )
        let ready = AgentSnapshot(
            availability: .ready,
            sessions: [session],
            quota: QuotaSnapshot(remainingPercent: 70, resetsAt: nil),
            diagnostic: nil
        )
        let disconnected = AgentSnapshot(
            availability: .disconnected,
            sessions: [],
            quota: .unavailable,
            diagnostic: "thread/list timed out"
        )
        let store = MonitorStore(initialSnapshot: ready)

        store.applyForTesting(disconnected, observedAt: baseDate)

        #expect(store.availability == .ready)
        #expect(store.sessions == [session])
        #expect(store.lastIntegrationMessage.contains("正在重试"))

        store.applyForTesting(
            ready,
            observedAt: baseDate.addingTimeInterval(1)
        )
        #expect(store.availability == .ready)
        #expect(store.sessions == [session])
    }

    @Test @MainActor
    func sustainedDisconnectPublishesAfterTheGracePeriod() {
        let baseDate = Date(timeIntervalSince1970: 2_000)
        let ready = AgentSnapshot(
            availability: .ready,
            sessions: [],
            quota: .unavailable,
            diagnostic: nil
        )
        let disconnected = AgentSnapshot(
            availability: .disconnected,
            sessions: [],
            quota: .unavailable,
            diagnostic: "transport unavailable"
        )
        let store = MonitorStore(initialSnapshot: ready)

        store.applyForTesting(disconnected, observedAt: baseDate)
        store.applyForTesting(
            disconnected,
            observedAt: baseDate.addingTimeInterval(2.9)
        )
        #expect(store.availability == .ready)

        store.applyForTesting(
            disconnected,
            observedAt: baseDate.addingTimeInterval(3)
        )
        #expect(store.availability == .disconnected)
        #expect(store.status == .disconnected)
    }

    @Test @MainActor
    func startupDisconnectDoesNotWaitForTheReadyStateGracePeriod() {
        let store = MonitorStore(initialSnapshot: .connecting)
        let disconnected = AgentSnapshot(
            availability: .disconnected,
            sessions: [],
            quota: .unavailable,
            diagnostic: "initialize timeout"
        )

        store.applyForTesting(disconnected)

        #expect(store.availability == .disconnected)
        #expect(store.status == .disconnected)
    }

    @Test
    func onlyTransportFailuresRequireAnAppServerReset() {
        #expect(CodexAppServerError.disconnected.requiresConnectionReset)
        #expect(
            CodexAppServerError.launchFailed("failed").requiresConnectionReset
        )
        #expect(
            !CodexAppServerError.timeout(method: "thread/list")
                .requiresConnectionReset
        )
        #expect(
            !CodexAppServerError.remote(code: -1, message: "busy")
                .requiresConnectionReset
        )
        #expect(
            CodexAppServerError.timeout(method: "thread/list")
                .isTransientRequestFailure
        )
        #expect(
            CodexAppServerError.protocolViolation("bad response")
                .isTransientRequestFailure
        )
        #expect(
            CodexAppServerError.remote(code: -1, message: "busy")
                .isTransientRequestFailure
        )
        #expect(
            !CodexAppServerError.remote(code: -32601, message: "missing")
                .isTransientRequestFailure
        )
    }

    @Test @MainActor
    func inputNeededWinsAggregatePriority() {
        let now = Date()
        let running = MonitoredSession(
            threadID: "running",
            turnID: "turn-running",
            projectName: "Chats",
            title: "Running",
            preview: nil,
            status: .running,
            startedAt: now
        )
        let input = MonitoredSession(
            threadID: "input",
            turnID: "turn-input",
            projectName: "Project",
            title: "Input",
            preview: nil,
            status: .inputNeeded,
            startedAt: now
        )

        #expect(
            AgentSnapshotMerge.merge([
                makeAgentSnapshot(.codex, sessions: [running, input])
            ]).status == .inputNeeded
        )

        // Priority is a property of the merged list, not of either product's.
        // A Codex turn that is merely running must not outrank a Claude Code
        // turn that is waiting on the user just because Codex leads the order.
        let claudeInput = MonitoredSession(
            agent: .claudeCode,
            threadID: "cc",
            turnID: "turn",
            projectName: "codex-in-notch",
            title: "Input",
            preview: nil,
            status: .inputNeeded,
            startedAt: input.startedAt
        )
        #expect(
            AgentSnapshotMerge.merge([
                makeAgentSnapshot(.codex, sessions: [running]),
                makeAgentSnapshot(.claudeCode, sessions: [claudeInput])
            ]).status == .inputNeeded
        )
    }

    @Test @MainActor
    func rateLimitParserConvertsUsedToRemaining() {
        let response = JSONValue.object([
            "rateLimits": .object([
                "primary": .object([
                    "usedPercent": .number(36),
                    "resetsAt": .number(2_000)
                ])
            ])
        ])

        let quota = CodexSnapshotParser.quota(from: response)

        #expect(quota.remainingPercent == 64)
        #expect(quota.resetsAt == Date(timeIntervalSince1970: 2_000))
    }

    @Test
    func accountUsageParserSelectsTheLocalTodayBucket() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 13,
            hour: 12
        )))
        let response = JSONValue.object([
            "dailyUsageBuckets": .array([
                .object([
                    "startDate": .string("2026-08-12"),
                    "tokens": .number(9_999)
                ]),
                .object([
                    "startDate": .string("2026-08-13"),
                    "tokens": .number(13_400)
                ])
            ])
        ])

        #expect(
            CodexSnapshotParser.todayTokenCount(
                from: response,
                now: now,
                calendar: calendar
            ) == 13_400
        )
        #expect(
            CodexSnapshotParser.todayTokenCount(
                from: .object(["dailyUsageBuckets": .array([])]),
                now: now,
                calendar: calendar
            ) == 0
        )
        #expect(
            CodexSnapshotParser.todayTokenCount(
                from: .object([:]),
                now: now,
                calendar: calendar
            ) == nil
        )
    }

    @Test @MainActor
    func threadPayloadAloneCannotProduceASession() {
        // Sessions may only originate from a post-launch Hook. A Thread payload
        // — however complete, and even when it claims an active in-progress turn
        // — is decoration for a session the reducer already knows about.
        let thread = JSONValue.object([
            "id": .string("thread-1"),
            "ephemeral": .bool(false),
            "parentThreadId": .null,
            "threadSource": .string("user"),
            "name": .string("Implement monitor"),
            "preview": .string("Original prompt"),
            "status": .object([
                "type": .string("active"),
                "activeFlags": .array([.string("waitingOnUserInput")])
            ]),
            "turns": .array([
                .object([
                    "id": .string("turn-1"),
                    "status": .string("inProgress"),
                    "startedAt": .number(1_000),
                    "items": .array([
                        .object([
                            "type": .string("agentMessage"),
                            "text": .string("Please choose a value")
                        ])
                    ])
                ])
            ])
        ])

        // The only remaining builder requires Hook-derived Turn identity.
        let state = HookTurnState(
            threadID: "thread-1",
            turnID: "turn-1",
            sessionStatus: .running,
            pendingInputToolUseID: nil,
            pendingApproval: nil,
            startedAt: Date(timeIntervalSince1970: 1_000),
            lastEventAt: Date(timeIntervalSince1970: 1_000),
            retiredTurnIDs: [],
            promptPreview: nil,
            assistantPreview: nil
        )
        let session = CodexSnapshotParser.session(
            from: state,
            thread: thread,
            projectName: "Codex in Notch"
        )

        #expect(session?.threadID == "thread-1")
        #expect(session?.turnID == "turn-1")
        #expect(session?.title == "Implement monitor")
    }

    @Test @MainActor
    func desktopProjectMetadataResolvesKnownKindsAndRejectsUnsupportedKinds() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let stateFile = root.appendingPathComponent(".codex-global-state.json")
        let data = try JSONSerialization.data(withJSONObject: [
            "local-projects": [
                "local-1": ["name": "codex-in-notch"]
            ],
            "remote-projects": [
                ["id": "remote-1", "label": "Remote workspace"]
            ],
            "thread-project-assignments": [
                "thread-local": [
                    "projectKind": "local",
                    "projectId": "local-1"
                ],
                "thread-remote": [
                    "projectKind": "remote",
                    "projectId": "remote-1"
                ]
            ],
            "projectless-thread-ids": ["thread-chat"]
        ])
        try data.write(to: stateFile, options: .atomic)

        let repository = CodexDesktopProjectMetadataRepository(
            stateFileURL: stateFile
        )
        let snapshot = await repository.snapshot()

        #expect(snapshot.source == .current)
        #expect(
            snapshot.resolution(for: "thread-local")
                == .project("codex-in-notch")
        )
        #expect(
            snapshot.resolution(for: "thread-remote")
                == .project("Remote workspace")
        )
        #expect(snapshot.resolution(for: "thread-chat") == .chats)
        #expect(snapshot.resolution(for: "thread-missing") == .unavailable)
    }

    @Test @MainActor
    func desktopProjectMetadataUsesBackupThenRetainsLastKnownGood() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let stateFile = root.appendingPathComponent(".codex-global-state.json")
        let backupFile = URL(fileURLWithPath: stateFile.path + ".bak")
        try Data("not-json".utf8).write(to: stateFile)
        let validBackup = try JSONSerialization.data(withJSONObject: [
            "local-projects": ["project-1": ["name": "Project"]],
            "thread-project-assignments": [
                "thread-1": [
                    "projectKind": "local",
                    "projectId": "project-1"
                ]
            ],
            "projectless-thread-ids": []
        ])
        try validBackup.write(to: backupFile, options: .atomic)

        let repository = CodexDesktopProjectMetadataRepository(
            stateFileURL: stateFile
        )
        let backup = await repository.snapshot()
        #expect(backup.source == .backup)
        #expect(backup.resolution(for: "thread-1") == .project("Project"))

        try Data("also-not-json".utf8).write(to: backupFile)
        let retained = await repository.snapshot()
        #expect(retained.source == .lastKnownGood)
        #expect(retained.resolution(for: "thread-1") == .project("Project"))
        #expect(retained.diagnostic?.contains("最近一次有效映射") == true)
    }

    @Test @MainActor
    func desktopProjectMetadataNeverTreatsMissingAssignmentAsChats() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let stateFile = root.appendingPathComponent(".codex-global-state.json")
        let data = try JSONSerialization.data(withJSONObject: [
            "thread-project-assignments": [:],
            "projectless-thread-ids": ["explicit-chat"]
        ])
        try data.write(to: stateFile, options: .atomic)

        let repository = CodexDesktopProjectMetadataRepository(
            stateFileURL: stateFile
        )
        let snapshot = await repository.snapshot()

        #expect(snapshot.resolution(for: "explicit-chat").displayName == "Chats")
        #expect(
            snapshot.resolution(for: "missing").displayName
                == DesktopProjectMetadataSnapshot.unavailableProjectName
        )
    }

    @Test @MainActor
    func desktopUnreadStateReadsOnlyTheLocalHostMembership() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let stateFile = root.appendingPathComponent(".codex-global-state.json")
        let data = try JSONSerialization.data(withJSONObject: [
            "electron-persisted-atom-state": [
                "unread-thread-ids-by-host-v1": [
                    "local": ["thread-local-1", "thread-local-2"],
                    "remote-host": ["thread-remote"]
                ]
            ]
        ])
        try data.write(to: stateFile, options: .atomic)

        let repository = CodexDesktopUnreadStateRepository(
            stateFileURL: stateFile
        )
        let snapshot = await repository.snapshot()

        #expect(snapshot.source == .current)
        #expect(
            snapshot.unreadThreadIDs
                == Set(["thread-local-1", "thread-local-2"])
        )
        #expect(!snapshot.unreadThreadIDs.contains("thread-remote"))
    }

    @Test @MainActor
    func desktopUnreadStateUsesBackupThenRetainsLastKnownGood() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let stateFile = root.appendingPathComponent(".codex-global-state.json")
        let backupFile = URL(fileURLWithPath: stateFile.path + ".bak")
        try Data("not-json".utf8).write(to: stateFile)
        let validBackup = try JSONSerialization.data(withJSONObject: [
            "electron-persisted-atom-state": [
                "unread-thread-ids-by-host-v1": [
                    "local": ["thread-1"]
                ]
            ]
        ])
        try validBackup.write(to: backupFile, options: .atomic)

        let repository = CodexDesktopUnreadStateRepository(
            stateFileURL: stateFile
        )
        let backup = await repository.snapshot()
        #expect(backup.source == .backup)
        #expect(backup.unreadThreadIDs == ["thread-1"])

        try Data("also-not-json".utf8).write(to: backupFile)
        let retained = await repository.snapshot()
        #expect(retained.source == .lastKnownGood)
        #expect(retained.unreadThreadIDs == ["thread-1"])
        #expect(retained.diagnostic?.contains("最近一次有效数据") == true)
    }

    @Test @MainActor
    func desktopUnreadStateTreatsMissingPrivateSchemaAsUnavailable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let stateFile = root.appendingPathComponent(".codex-global-state.json")
        let incompatible = try JSONSerialization.data(withJSONObject: [
            "electron-persisted-atom-state": [:]
        ])
        try incompatible.write(to: stateFile, options: .atomic)

        let repository = CodexDesktopUnreadStateRepository(
            stateFileURL: stateFile
        )
        let snapshot = await repository.snapshot()

        #expect(snapshot.source == .unavailable)
        #expect(snapshot.unreadThreadIDs.isEmpty)
        #expect(snapshot.diagnostic?.contains("schema 不兼容") == true)
        #expect(snapshot.diagnostic?.contains("保守保留终态会话") == true)
    }

    @Test @MainActor
    func desktopUnreadStateMissingAndCorruptFilesFailClosed() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let stateFile = root.appendingPathComponent(".codex-global-state.json")
        let missingRepository = CodexDesktopUnreadStateRepository(
            stateFileURL: stateFile
        )

        let missing = await missingRepository.snapshot()
        #expect(missing.source == .unavailable)
        #expect(missing.unreadThreadIDs.isEmpty)
        #expect(missing.diagnostic?.contains("保守保留终态会话") == true)

        try Data("not-json".utf8).write(to: stateFile)
        let corruptRepository = CodexDesktopUnreadStateRepository(
            stateFileURL: stateFile
        )
        let corrupt = await corruptRepository.snapshot()
        #expect(corrupt.source == .unavailable)
        #expect(corrupt.unreadThreadIDs.isEmpty)
        #expect(corrupt.diagnostic?.contains("保守保留终态会话") == true)
    }

    @Test @MainActor
    func desktopUnreadStateDirectoryWatcherObservesAtomicReplacement() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let stateFile = root.appendingPathComponent(".codex-global-state.json")
        let initial = try JSONSerialization.data(withJSONObject: [
            "electron-persisted-atom-state": [
                "unread-thread-ids-by-host-v1": ["local": ["thread-1"]]
            ]
        ])
        try initial.write(to: stateFile, options: .atomic)
        let repository = CodexDesktopUnreadStateRepository(
            stateFileURL: stateFile,
            changeDebounceInterval: 0.01
        )
        let events = repository.changeEvents()
        let eventTask = Task {
            for await _ in events {
                return true
            }
            return false
        }

        let updated = try JSONSerialization.data(withJSONObject: [
            "electron-persisted-atom-state": [
                "unread-thread-ids-by-host-v1": ["local": ["thread-2"]]
            ]
        ])
        try updated.write(to: stateFile, options: .atomic)
        let observed = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await eventTask.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            eventTask.cancel()
            return result
        }
        let snapshot = await repository.snapshot()

        #expect(observed)
        #expect(snapshot.source == .current)
        #expect(snapshot.unreadThreadIDs == ["thread-2"])
    }

    @Test @MainActor
    func terminalUnreadMembershipHidesOnlyAfterAuthoritativeReadEvidence() {
        let boundary = Date(timeIntervalSince1970: 1_000)
        let unread = DesktopUnreadStateSnapshot(
            unreadThreadIDs: ["thread-1"],
            source: .current
        )
        let read = DesktopUnreadStateSnapshot(
            unreadThreadIDs: [],
            source: .current
        )
        let unavailable = DesktopUnreadStateSnapshot.unavailable("invalid")
        var gate = TerminalUnreadMembershipGate(settlingInterval: 2)

        let unreadTerminalIsVisible = gate.shouldDisplay(
            sessionID: "thread-1:turn-1",
            threadID: "thread-1",
            status: .completed,
            terminalBoundaryAt: boundary,
            unreadState: unread,
            now: boundary
        )
        #expect(unreadTerminalIsVisible)
        let readTerminalIsHidden = !gate.shouldDisplay(
            sessionID: "thread-1:turn-1",
            threadID: "thread-1",
            status: .completed,
            terminalBoundaryAt: boundary,
            unreadState: read,
            now: boundary.addingTimeInterval(0.1)
        )
        #expect(readTerminalIsHidden)
        let invalidStateDoesNotRestoreHiddenTerminal = !gate.shouldDisplay(
            sessionID: "thread-1:turn-1",
            threadID: "thread-1",
            status: .completed,
            terminalBoundaryAt: boundary,
            unreadState: unavailable,
            now: boundary.addingTimeInterval(0.2)
        )
        #expect(invalidStateDoesNotRestoreHiddenTerminal)

        let newTerminalWaitsForDesktopPersistence = gate.shouldDisplay(
            sessionID: "thread-2:turn-2",
            threadID: "thread-2",
            status: .completed,
            terminalBoundaryAt: boundary,
            unreadState: read,
            now: boundary.addingTimeInterval(1.9)
        )
        #expect(newTerminalWaitsForDesktopPersistence)
        let settledReadTerminalIsHidden = !gate.shouldDisplay(
            sessionID: "thread-2:turn-2",
            threadID: "thread-2",
            status: .completed,
            terminalBoundaryAt: boundary,
            unreadState: read,
            now: boundary.addingTimeInterval(2)
        )
        #expect(settledReadTerminalIsHidden)

        let activeSessionIsAlwaysVisible = gate.shouldDisplay(
            sessionID: "thread-active:turn-active",
            threadID: "thread-active",
            status: .running,
            terminalBoundaryAt: boundary,
            unreadState: read,
            now: boundary.addingTimeInterval(20)
        )
        #expect(activeSessionIsAlwaysVisible)
    }

    @Test @MainActor
    func hookIdentityIsRequiredBeforeAThreadCanBecomeASession() {
        // An eligible root thread that even claims an active status still
        // cannot become a session on its own: the reducer owns Turn identity
        // and status, and a Thread payload contributes presentation only.
        let thread = JSONValue.object([
            "id": .string("thread-without-turn"),
            "threadSource": .string("user"),
            "name": .string("Eligible but unowned"),
            "status": .object([
                "type": .string("active"),
                "activeFlags": .array([.string("waitingOnApproval")])
            ])
        ])

        #expect(CodexSnapshotParser.isEligibleRootThread(thread))

        // With Hook identity the row exists, and its status is the reducer's
        // Running -- not the thread's "waitingOnApproval" claim.
        let state = HookTurnState(
            threadID: "thread-without-turn",
            turnID: "turn-1",
            sessionStatus: .running,
            pendingInputToolUseID: nil,
            pendingApproval: nil,
            startedAt: Date(timeIntervalSince1970: 1_000),
            lastEventAt: Date(timeIntervalSince1970: 1_000),
            retiredTurnIDs: [],
            promptPreview: nil,
            assistantPreview: nil
        )
        let session = CodexSnapshotParser.session(
            from: state,
            thread: thread,
            projectName: "Chats"
        )
        #expect(session?.status == .running)
        #expect(session?.title == "Eligible but unowned")
    }

    @Test @MainActor
    func privacyModeNeverFallsBackToPromptOrKeepsPreviewText() {
        let thread = JSONValue.object([
            "id": .string("thread-private"),
            "ephemeral": .bool(false),
            "parentThreadId": .null,
            "threadSource": .string("user"),
            "preview": .string("private prompt fallback"),
            "section": .object(["name": .string("Chats")]),
            "status": .object([
                "type": .string("active"),
                "activeFlags": .array([])
            ]),
            "turns": .array([
                .object([
                    "id": .string("turn-private"),
                    "status": .string("inProgress"),
                    "items": .array([
                        .object([
                            "type": .string("agentMessage"),
                            "text": .string("private progress")
                        ])
                    ])
                ])
            ])
        ])

        let state = HookTurnState(
            threadID: "thread-private",
            turnID: "turn-private",
            sessionStatus: .running,
            pendingInputToolUseID: nil,
            pendingApproval: nil,
            startedAt: Date(timeIntervalSince1970: 1_000),
            lastEventAt: Date(timeIntervalSince1970: 1_000),
            retiredTurnIDs: [],
            promptPreview: "private prompt fallback",
            assistantPreview: nil
        )
        let session = CodexSnapshotParser.session(
            from: state,
            thread: thread,
            projectName: "Chats",
            showsContentPreviews: false
        )

        #expect(session?.title == "Untitled")
        #expect(session?.privacySafeTitle == "Untitled")
        #expect(session?.preview == nil)

        let redacted = MonitoredSession(
            threadID: "thread",
            turnID: "turn",
            projectName: "Chats",
            title: "private prompt fallback",
            privacySafeTitle: "Untitled",
            preview: "private progress",
            status: .running,
            startedAt: nil
        ).hidingContent()
        #expect(redacted.title == "Untitled")
        #expect(redacted.preview == nil)
    }

    @Test @MainActor
    func emptyExpandedMonitorUsesThinStateHeight() {
        let display = makeDisplay(
            id: "notched",
            ordinal: 1,
            menuBarHeight: 38,
            hasNotch: true
        )
        let store = MonitorStore(
            displays: [display],
            initialSnapshot: AgentSnapshot(
                availability: .ready,
                sessions: [],
                quota: .unavailable,
                diagnostic: nil
            )
        )
        store.isExpanded = true

        #expect(
            store.currentPanelSize.height
                == 38 + PanelMetrics.thinExpandedContentHeight
        )
        #expect(store.emptyListMessage == "No active turns")
    }

    @Test @MainActor
    func expandedMonitorHeightFitsUpToThreeVisibleSessions() {
        let display = makeDisplay(
            id: "notched",
            ordinal: 1,
            menuBarHeight: 38,
            hasNotch: true
        )
        let store = MonitorStore(displays: [display])
        store.isExpanded = true

        for sessionCount in 1 ... 4 {
            let sessions = (0..<sessionCount).map { index in
                MonitoredSession(
                    threadID: "thread-\(index)",
                    turnID: "turn-\(index)",
                    projectName: "Project",
                    title: "Session \(index)",
                    preview: nil,
                    status: .completed,
                    startedAt: nil
                )
            }
            store.applyForTesting(
                AgentSnapshot(
                    availability: .ready,
                    sessions: sessions,
                    quota: .unavailable,
                    diagnostic: nil
                )
            )

            let visibleSessionCount = min(
                sessionCount,
                PanelMetrics.maximumVisibleSessionCount
            )
            let expectedContentHeight = CGFloat(visibleSessionCount)
                * PanelMetrics.sessionRowHeight
                + PanelMetrics.expandedFooterHeight
            #expect(store.expandedContentHeight == expectedContentHeight)
            #expect(
                store.currentPanelSize.height
                    == display.menuBarHeight + expectedContentHeight
            )
        }
    }

    @Test
    func threadDeepLinkEncodesTheIdentifierAsOnePathComponent() throws {
        let url = try CodexDeepLink.threadURL(
            threadID: "thread/with spaces?#%"
        )

        #expect(
            url.absoluteString
                == "codex://threads/thread%2Fwith%20spaces%3F%23%25"
        )
    }

    @Test @MainActor
    func navigatorPreflightsAndTargetsCodexDesktop() async throws {
        let checker = NavigationTargetCheckerStub(isNavigable: true)
        let workspace = CodexWorkspaceStub(
            applicationURL: URL(fileURLWithPath: "/Applications/ChatGPT.app")
        )
        let navigator = CodexDesktopNavigator(
            targetChecker: checker,
            workspace: workspace
        )

        let outcome = try await navigator.open(
            makeSession(agent: .codex, threadID: "thread-123")
        )

        #expect(outcome == .openedThread(host: "Codex Desktop"))
        #expect(await checker.requestedThreadIDs() == ["thread-123"])
        #expect(
            workspace.requestedBundleIdentifiers
                == [CodexDesktopNavigator.desktopBundleIdentifier]
        )
        #expect(workspace.openedURL?.absoluteString == "codex://threads/thread-123")
        #expect(
            workspace.openedApplicationURL
                == URL(fileURLWithPath: "/Applications/ChatGPT.app")
        )
    }

    @Test @MainActor
    func navigatorDoesNotLaunchWhenThreadIsNoLongerNavigable() async {
        let checker = NavigationTargetCheckerStub(isNavigable: false)
        let workspace = CodexWorkspaceStub(
            applicationURL: URL(fileURLWithPath: "/Applications/ChatGPT.app")
        )
        let navigator = CodexDesktopNavigator(
            targetChecker: checker,
            workspace: workspace
        )

        do {
            try await navigator.open(
                makeSession(agent: .codex, threadID: "deleted-thread")
            )
            Issue.record("Expected navigation to reject a missing thread")
        } catch {
            #expect(error as? CodexNavigationError == .targetUnavailable)
        }

        #expect(workspace.requestedBundleIdentifiers.isEmpty)
        #expect(workspace.openedURL == nil)
    }

    @Test @MainActor
    func monitorStoreCollapsesOnlyAfterNavigationSucceeds() async {
        let session = MonitoredSession(
            threadID: "thread-123",
            turnID: "turn-123",
            projectName: "Chats",
            title: "Open this chat",
            preview: nil,
            status: .completed,
            startedAt: nil
        )
        let successNavigator = AgentNavigatorStub()
        let successStore = MonitorStore(navigator: successNavigator)
        successStore.isExpanded = true

        let didOpen = await successStore.openAndWait(session)

        #expect(didOpen)
        #expect(!successStore.isExpanded)
        #expect(successNavigator.requestedThreadIDs == ["thread-123"])

        let failureNavigator = AgentNavigatorStub(
            error: CodexNavigationError.openRejected
        )
        let failureStore = MonitorStore(navigator: failureNavigator)
        failureStore.isExpanded = true

        let didOpenMissingTarget = await failureStore.openAndWait(session)

        #expect(!didOpenMissingTarget)
        #expect(failureStore.isExpanded)
        #expect(failureStore.lastIntegrationMessage.contains("未能接受"))
    }

    @Test @MainActor
    func startupWithHistoricalHookTrustBecomesIdleAfterSnapshot() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()

        // Recreate an installation from an older build: a different helper
        // script this app installed itself, still executable and registered.
        try legacyManagedHookScript.write(
            to: paths.script,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: paths.script.path
        )
        // An install from before the marker existed: its provenance is the
        // settings file, which is what the upgrade path still has to accept.
        try? FileManager.default.removeItem(at: paths.installMarker)
        try JSONSerialization.data(
            withJSONObject: ["showsContentPreviews": false],
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: paths.legacySettings, options: .atomic)

        // The scan is cached, so these external edits are only visible after
        // revalidation -- which the app does on its own within the window, and
        // immediately whenever the user asks for a recheck.
        await installer.invalidateInstallationCache()
        #expect(await installer.status(hasObservedEvent: true) == .active)

        // Persist trust without creating a live Turn, then simulate a fresh app
        // launch while Codex Desktop is still running.
        let terminalEvent = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "SessionEnd",
            "session_id": "thread-finished"
        ])
        try terminalEvent.write(
            to: paths.eventsDirectory.appendingPathComponent("trusted.json")
        )
        let seedRepository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )
        let seededState = await seedRepository.consumeEvents()
        #expect(seededState.hasObservedEvent)
        #expect(seededState.hasObservedLiveEvent)
        #expect(seededState.turns.isEmpty)

        let client = CodexAppServerStub(
            listedThreads: [],
            loadedListResults: []
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(paths: paths),
            hookInstaller: installer,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        let snapshot = await service.fetchSnapshot(showsContentPreviews: false)
        try await waitForThreadListRequests(
            client,
            atLeast: 1,
            completed: true
        )
        let methods = await client.requestedMethods()
        let upgradedScript = try String(
            contentsOf: paths.script,
            encoding: .utf8
        )
        let markerData = try Data(contentsOf: paths.installMarker)
        let marker = try #require(
            JSONSerialization.jsonObject(with: markerData) as? [String: Any]
        )
        let retiredLegacySettings = !FileManager.default.fileExists(
            atPath: paths.legacySettings.path
        )
        await service.disconnect()

        #expect(snapshot.availability == .ready)
        #expect(snapshot.sessions.isEmpty)
        #expect(AgentSnapshotMerge.merge([snapshot]).status == .idle)
        #expect(upgradedScript.contains(#"payload.get("tool_use_id")"#))
        // The upgrade recognised a pre-marker install by its legacy settings
        // file, replaced it with the marker, and carried no privacy state
        // across -- there is no longer any setting a helper could read.
        #expect(marker["managedBy"] as? String == "codex-in-notch")
        #expect(marker["showsContentPreviews"] == nil)
        #expect(retiredLegacySettings)
        // Provenance is the marker's existence, so no hash or version is kept.
        #expect(marker["managedHookSHA256"] == nil)
        #expect(marker["managedHookVersion"] == nil)
        #expect(methods.contains("thread/list"))
        #expect(!methods.contains("thread/loaded/list"))
        #expect(!methods.contains("thread/read"))
    }

    @Test @MainActor
    func startupNeverReconstructsPreLaunchSessions() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()

        let projectStateFile = paths.supportDirectory
            .appendingPathComponent(".codex-global-state.json")
        let projectState = try JSONSerialization.data(withJSONObject: [
            "local-projects": [
                "project-1": ["name": "Codex in Notch"]
            ],
            "thread-project-assignments": [
                "thread-1": [
                    "projectKind": "local",
                    "projectId": "project-1"
                ]
            ],
            "projectless-thread-ids": []
        ])
        try projectState.write(to: projectStateFile, options: .atomic)

        let listedThread = JSONValue.object([
            "id": .string("thread-1"),
            "ephemeral": .bool(false),
            "parentThreadId": .null,
            "threadSource": .string("user"),
            "name": .string("Fast startup"),
            "section": .object(["name": .string("Pinned")]),
            "status": .object([
                "type": .string("active"),
                "activeFlags": .array([])
            ]),
            "turns": .array([
                .object([
                    "id": .string("turn-1"),
                    "status": .string("inProgress")
                ])
            ])
        ])
        let client = CodexAppServerStub(
            listedThreads: [listedThread],
            loadedListResults: []
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(
                paths: paths,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer,
            projectMetadata: CodexDesktopProjectMetadataRepository(
                stateFileURL: projectStateFile
            )
        )

        let ready = await service.fetchSnapshot(showsContentPreviews: true)
        let requestedMethods = await client.requestedMethods()

        // The listed thread advertises an active status and an in-progress turn,
        // i.e. exactly the pre-launch session the product used to reconstruct.
        // It must now be ignored: only a post-launch Hook can create a session.
        #expect(ready.availability == .ready)
        #expect(ready.sessions.isEmpty)
        #expect(AgentSnapshotMerge.merge([ready]).status == .idle)
        // Startup still proves the App Server answers a real read, which is what
        // separates Ready from Disconnected.
        #expect(requestedMethods.contains("thread/list"))
        #expect(!requestedMethods.contains("thread/loaded/list"))
        #expect(!requestedMethods.contains("thread/read"))
        #expect(await client.disconnectCount() == 0)

        await service.disconnect()
    }

    @Test @MainActor
    func trustedHookMarkerDoesNotRestoreTurnIntoConfirmedSnapshot() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        let event = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-1",
            "turn_id": "turn-1"
        ])
        try event.write(
            to: paths.eventsDirectory.appendingPathComponent("trusted.json")
        )

        let listedThread = JSONValue.object([
            "id": .string("thread-1"),
            "ephemeral": .bool(false),
            "threadSource": .string("user"),
            "name": .string("Trusted turn"),
            "updatedAt": .number(Date().timeIntervalSince1970),
            "status": .object(["type": .string("active")])
        ])
        let firstClient = CodexAppServerStub(
            listedThreads: [listedThread],
            loadedListResults: []
        )
        let firstService = LiveCodexMonitorService(
            client: firstClient,
            hookEvents: HookEventRepository(
                paths: paths,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        let initial = await firstService.fetchSnapshot(
            showsContentPreviews: false
        )
        await firstService.disconnect()

        #expect(initial.availability == .ready)
        #expect(initial.sessions.first?.status == .running)

        let restoredClient = CodexAppServerStub(
            listedThreads: [listedThread],
            loadedListResults: []
        )
        let restoredService = LiveCodexMonitorService(
            client: restoredClient,
            hookEvents: HookEventRepository(paths: paths),
            hookInstaller: installer,
            desktopProcessIdentifierProvider: { 4_242 }
        )
        let restored = await restoredService.fetchSnapshot(
            showsContentPreviews: false
        )
        try await waitForThreadListRequests(
            restoredClient,
            atLeast: 1,
            completed: true
        )
        let methods = await restoredClient.requestedMethods()
        await restoredService.disconnect()

        #expect(restored.availability == .ready)
        #expect(restored.sessions.isEmpty)
        #expect(methods.contains("thread/list"))
        #expect(!methods.contains("thread/loaded/list"))
        #expect(!methods.contains("thread/read"))
    }

    @Test @MainActor
    func startupWithoutAnAppServerResponseIsDisconnected() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        let event = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "SessionEnd",
            "session_id": "thread-finished"
        ])
        try event.write(
            to: paths.eventsDirectory.appendingPathComponent("trusted.json")
        )

        let client = CodexAppServerStub(
            listedThreads: [],
            loadedListResults: [],
            connectResult: .failure(.timeout(method: "initialize"))
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(
                paths: paths,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        let snapshot = await service.fetchSnapshot(showsContentPreviews: false)

        #expect(snapshot.availability == .disconnected)
        #expect(snapshot.sessions.isEmpty)
        #expect(snapshot.diagnostic?.contains("未响应") == true)
        #expect(await client.disconnectCount() == 1)
    }

    @Test @MainActor
    func startupWithAppServerResponseButNoSnapshotYetIsConnecting() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        let client = CodexAppServerStub(
            listedThreads: [],
            loadedListResults: [],
            threadListError: .timeout(method: "thread/list")
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(paths: paths),
            hookInstaller: installer,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        let snapshot = await service.fetchSnapshot(showsContentPreviews: false)

        #expect(snapshot.availability == .connecting)
        #expect(snapshot.sessions.isEmpty)
        #expect(snapshot.diagnostic?.contains("保留最近状态") == true)
        #expect(await client.requestCount(method: "thread/list") == 1)
        #expect(await client.disconnectCount() == 0)
    }

    @Test @MainActor
    func idleToRunningDoesNotWaitForSlowThreadList() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        let trusted = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "SessionEnd",
            "session_id": "thread-finished"
        ])
        try trusted.write(
            to: paths.eventsDirectory.appendingPathComponent("0.json")
        )

        let client = CodexAppServerStub(
            listedThreads: [],
            loadedListResults: [],
            threadListDelayNanoseconds: 2_000_000_000
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(
                paths: paths,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        let idle = await service.fetchSnapshot(showsContentPreviews: false)
        try await waitForThreadListRequests(client, atLeast: 1)
        #expect(idle.availability == .ready)
        #expect(idle.sessions.isEmpty)

        let prompt = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-1",
            "turn_id": "turn-1"
        ])
        try prompt.write(
            to: paths.eventsDirectory.appendingPathComponent("1.json")
        )

        let startedAt = Date()
        let running = await service.fetchSnapshot(showsContentPreviews: false)
        let elapsed = Date().timeIntervalSince(startedAt)
        let threadListRequests = await client.requestCount(method: "thread/list")
        await service.disconnect()

        #expect(running.sessions.first?.status == .running)
        #expect(elapsed < 1.5)
        #expect(threadListRequests == 1)
    }

    @Test
    func closesWithoutOpensReportTheUntrustedPreToolUseHook() async throws {
        // Codex trusts hook definitions by content hash. Rewriting one stops it
        // executing until the user re-trusts, and nothing else notices because
        // the remaining definitions keep firing. Replays that exact stream.
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )
        var clock = 3_000.0
        func emit(_ index: Int, _ event: [String: Any]) throws {
            clock += 1
            var payload = event
            payload["received_at"] = clock
            payload["session_id"] = "thread-untrusted"
            payload["turn_id"] = "turn-untrusted"
            try JSONSerialization.data(withJSONObject: payload).write(
                to: paths.eventsDirectory.appendingPathComponent("\(index).json")
            )
        }

        try emit(0, ["hook_event_name": "UserPromptSubmit"])
        for index in 1 ... 2 {
            try emit(index, [
                "hook_event_name": "PostToolUse",
                "tool_name": "Bash",
                "tool_use_id": "exec-\(index)"
            ])
        }
        // Two closes is still short of the threshold.
        #expect(await repository.consumeEvents().diagnostic == nil)

        try emit(3, [
            "hook_event_name": "PostToolUse",
            "tool_name": "Bash",
            "tool_use_id": "exec-3"
        ])
        let warned = await repository.consumeEvents().diagnostic
        #expect(warned?.contains("/hooks") == true)
        #expect(warned?.contains("PreToolUse") == true)
    }

    @Test
    func deliveredPreToolUseNeverReportsAnUntrustedHook() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )
        var clock = 4_000.0
        func emit(_ index: Int, _ event: [String: Any]) throws {
            clock += 1
            var payload = event
            payload["received_at"] = clock
            payload["session_id"] = "thread-ok"
            payload["turn_id"] = "turn-ok"
            try JSONSerialization.data(withJSONObject: payload).write(
                to: paths.eventsDirectory.appendingPathComponent("\(index).json")
            )
        }

        try emit(0, ["hook_event_name": "UserPromptSubmit"])
        // A PreToolUse for any tool proves the definition runs, so plenty of
        // closes afterwards must never raise the warning.
        try emit(1, [
            "hook_event_name": "PreToolUse",
            "tool_name": "Bash",
            "tool_use_id": "exec-open"
        ])
        for index in 2 ... 6 {
            try emit(index, [
                "hook_event_name": "PostToolUse",
                "tool_name": "Bash",
                "tool_use_id": "exec-\(index)"
            ])
        }
        #expect(await repository.consumeEvents().diagnostic == nil)
    }

    @Test
    func approvalPromptPublishesApprovalNeededUntilItIsAnswered() async throws {
        // Replays the hook sequence captured from a real Desktop approval:
        // Codex never emits PermissionRequest for it. The prompt is a
        // `request_permissions` tool call that stays open across the human wait.
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )
        var clock = 1_000.0
        func emit(_ index: Int, _ event: [String: Any]) throws {
            clock += 1
            var payload = event
            payload["received_at"] = clock
            payload["session_id"] = "thread-approval"
            payload["turn_id"] = "turn-approval"
            try JSONSerialization.data(withJSONObject: payload).write(
                to: paths.eventsDirectory.appendingPathComponent("\(index).json")
            )
        }

        try emit(0, ["hook_event_name": "UserPromptSubmit"])
        #expect(await repository.consumeEvents().turns.first?.status == .running)

        // The approval tool call opens; the human has not answered yet.
        try emit(1, [
            "hook_event_name": "PreToolUse",
            "tool_name": "request_permissions",
            "tool_use_id": "exec-approval-1"
        ])
        #expect(await repository.consumeEvents().turns.first?.status == .approvalNeeded)

        // An unrelated tool finishing must not clear the pending approval.
        try emit(2, [
            "hook_event_name": "PostToolUse",
            "tool_name": "Bash",
            "tool_use_id": "exec-unrelated"
        ])
        #expect(await repository.consumeEvents().turns.first?.status == .approvalNeeded)

        // Answering it closes the matching tool call and resumes Running.
        try emit(3, [
            "hook_event_name": "PostToolUse",
            "tool_name": "request_permissions",
            "tool_use_id": "exec-approval-1"
        ])
        #expect(await repository.consumeEvents().turns.first?.status == .running)

        try emit(4, ["hook_event_name": "Stop"])
        #expect(await repository.consumeEvents().turns.first?.status == .completed)
    }

    @Test @MainActor
    func permissionRequestAloneDoesNotPublishApprovalNeeded() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        let timestamp = Date().timeIntervalSince1970
        let prompt = try JSONSerialization.data(withJSONObject: [
            "received_at": timestamp,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-1",
            "turn_id": "turn-1"
        ])
        try prompt.write(
            to: paths.eventsDirectory.appendingPathComponent("0.json")
        )

        let listedThread = JSONValue.object([
            "id": .string("thread-1"),
            "ephemeral": .bool(false),
            "threadSource": .string("user"),
            "status": .object([
                "type": .string("active"),
                "activeFlags": .array([])
            ])
        ])
        let client = CodexAppServerStub(
            listedThreads: [listedThread],
            loadedListResults: []
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(
                paths: paths,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        let initial = await service.fetchSnapshot(showsContentPreviews: false)
        #expect(initial.sessions.first?.status == .running)
        try await waitForThreadListRequests(
            client,
            atLeast: 1,
            completed: true
        )
        // Neither background App Server read may sit on the Hook -> UI path.
        await client.setThreadListDelayNanoseconds(2_000_000_000)
        await client.setThreadReadDelayNanoseconds(2_000_000_000)

        let approval = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "PermissionRequest",
            "session_id": "thread-1",
            "turn_id": "turn-1"
        ])
        try approval.write(
            to: paths.eventsDirectory.appendingPathComponent("1.json")
        )
        let startedAt = Date()
        let approvalSnapshot = await service.fetchSnapshot(
            showsContentPreviews: false
        )
        let elapsed = Date().timeIntervalSince(startedAt)

        let input = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "PreToolUse",
            "session_id": "thread-1",
            "turn_id": "turn-1",
            "tool_name": "request_user_input",
            "tool_use_id": "tool-1"
        ])
        try input.write(
            to: paths.eventsDirectory.appendingPathComponent("2.json")
        )
        let inputSnapshot = await service.fetchSnapshot(
            showsContentPreviews: false
        )
        let threadListRequests = await client.requestCount(method: "thread/list")
        await service.disconnect()

        #expect(approvalSnapshot.sessions.first?.status == .running)
        #expect(inputSnapshot.sessions.first?.status == .inputNeeded)
        #expect(elapsed < 1.5)
        // Hook activity on an already-listed thread no longer re-paginates the
        // whole unarchived set; only the cheap per-thread read follows it.
        #expect(threadListRequests == 1)
    }

    @Test @MainActor
    func liveStopCompletesWithoutAThreadDetailRead() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        let event = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "Stop",
            "session_id": "thread-stop",
            "turn_id": "turn-stop"
        ])
        try event.write(
            to: paths.eventsDirectory.appendingPathComponent("stop.json")
        )

        let client = CodexAppServerStub(
            listedThreads: [.object([
                "id": .string("thread-stop"),
                "ephemeral": .bool(false),
                "threadSource": .string("user"),
                "name": .string("Completed turn"),
                "updatedAt": .number(Date().timeIntervalSince1970)
            ])],
            loadedListResults: []
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(
                paths: paths,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        let first = await service.fetchSnapshot(showsContentPreviews: false)
        try await waitForThreadListRequests(
            client,
            atLeast: 1,
            completed: true
        )
        let second = await service.fetchSnapshot(showsContentPreviews: false)
        let third = await service.fetchSnapshot(showsContentPreviews: false)
        let methods = await client.requestedMethods()
        await service.disconnect()

        #expect(first.availability == .ready)
        #expect(first.sessions.first?.status == .completed)
        #expect(second.availability == .ready)
        #expect(second.sessions.first?.status == .completed)
        #expect(third.availability == .ready)
        #expect(third.sessions.first?.status == .completed)
        // The real rule is not "never call thread/read" — it is "never read Turn
        // detail". Metadata reads are allowed; rollout history is not.
        #expect(!methods.contains("thread/items/list"))
        #expect(!methods.contains("thread/turns/list"))
        for params in await client.recordedThreadReadParams() {
            #expect(params["includeTurns"]?.boolValue == false)
        }
    }

    @Test @MainActor
    func liveStopTransitionsDirectlyFromRunningToCompleted() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        let prompt = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-terminal",
            "turn_id": "turn-terminal"
        ])
        try prompt.write(
            to: paths.eventsDirectory.appendingPathComponent("0.json")
        )

        let listedThread = JSONValue.object([
            "id": .string("thread-terminal"),
            "ephemeral": .bool(false),
            "threadSource": .string("user"),
            "updatedAt": .number(Date().timeIntervalSince1970),
            "status": .object([
                "type": .string("active"),
                "activeFlags": .array([])
            ]),
            "turns": .array([
                .object([
                    "id": .string("turn-terminal"),
                    "status": .string("inProgress")
                ])
            ])
        ])
        let client = CodexAppServerStub(
            listedThreads: [listedThread],
            loadedListResults: []
        )
        let unreadState = DesktopUnreadStateStub(
            DesktopUnreadStateSnapshot(
                unreadThreadIDs: ["thread-terminal"],
                source: .current
            )
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(
                paths: paths,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer,
            unreadState: unreadState,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        let initial = await service.fetchSnapshot(showsContentPreviews: false)
        #expect(initial.sessions.first?.status == .running)
        try await waitForThreadListRequests(
            client,
            atLeast: 1,
            completed: true
        )

        let stop = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "Stop",
            "session_id": "thread-terminal",
            "turn_id": "turn-terminal"
        ])
        try stop.write(
            to: paths.eventsDirectory.appendingPathComponent("1.json")
        )

        var observedStatuses: [SessionStatus] = []
        for _ in 0..<100 {
            let snapshot = await service.fetchSnapshot(
                showsContentPreviews: false
            )
            if let status = snapshot.sessions.first?.status {
                observedStatuses.append(status)
            }
            if observedStatuses.last == .completed {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await unreadState.setSnapshot(
            DesktopUnreadStateSnapshot(
                unreadThreadIDs: [],
                source: .current
            )
        )
        let afterRead = await service.fetchSnapshot(showsContentPreviews: false)
        await service.disconnect()

        #expect(observedStatuses.first == .completed)
        #expect(observedStatuses.last == .completed)
        #expect(afterRead.sessions.isEmpty)
        // Terminal status comes from the Hook reducer alone; no Turn detail is
        // fetched to classify it.
        #expect(await client.requestCount(method: "thread/items/list") == 0)
        for params in await client.recordedThreadReadParams() {
            #expect(params["includeTurns"]?.boolValue == false)
        }
    }

    @Test @MainActor
    func liveCodexAppServerReturnsRealQuotaWhenOptedIn() async throws {
        guard ProcessInfo.processInfo.environment[
            "CODEX_IN_NOTCH_RUN_LIVE_TEST"
        ] == "1" else {
            return
        }

        let client = CodexAppServerClient()
        try await client.connect()
        let response = try await client.request(
            method: "account/rateLimits/read",
            params: .object([:])
        )
        let quota = CodexSnapshotParser.quota(from: response)
        await client.disconnect()

        #expect(quota.remainingPercent != nil)
        #expect((0 ... 100).contains(quota.remainingPercent ?? -1))
    }

    @Test @MainActor
    func liveStartupAvoidsThreadReadsWhenOptedIn() async throws {
        guard ProcessInfo.processInfo.environment[
            "CODEX_IN_NOTCH_RUN_LIVE_TEST"
        ] == "1" else {
            return
        }

        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        let event = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "live-probe-thread",
            "turn_id": "live-probe-turn"
        ])
        try event.write(
            to: paths.eventsDirectory.appendingPathComponent("live-probe.json")
        )
        let client = RecordingAppServerClient(base: CodexAppServerClient())
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(
                paths: paths,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer
        )

        let startedAt = Date()
        let snapshot = await service.fetchSnapshot(showsContentPreviews: false)
        let elapsed = Date().timeIntervalSince(startedAt)
        for _ in 0..<200 {
            if await client.requestCount(method: "thread/list") > 0 {
                break
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let requestedMethods = await client.requestedMethods()
        await service.disconnect()

        #expect(snapshot.availability == .ready)
        #expect(requestedMethods.contains("thread/list"))
        #expect(!requestedMethods.contains("thread/loaded/list"))
        #expect(!requestedMethods.contains("thread/read"))
        #expect(elapsed < 10)
    }

    @Test
    func hookEventQueueSignalsWithoutWaitingForThePoll() async throws {
        // The queue directory is the only place a Hook lands, so watching it is
        // what turns a lifecycle event into an immediate refresh instead of one
        // that waits out the poll interval.
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        var timing = MonitorTiming.standard
        timing.hookEventDebounceInterval = 0.01
        let repository = HookEventRepository(
            paths: paths,
            timing: timing,
            liveEventCutoff: .distantPast
        )
        let events = repository.changeEvents()
        let observer = Task {
            for await _ in events {
                return true
            }
            return false
        }

        try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-watch",
            "turn_id": "turn-watch"
        ]).write(to: paths.eventsDirectory.appendingPathComponent("0.json"))

        let observed = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await observer.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
        observer.cancel()
        #expect(observed)
    }

    @Test @MainActor
    func readingSetupStatusNeverConsumesTheHookQueue() async throws {
        // hookSetupStatus used to consume events, so a refresh drained the queue
        // twice and whatever the second call swallowed surfaced a cycle late.
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-intact",
            "turn_id": "turn-intact"
        ]).write(to: paths.eventsDirectory.appendingPathComponent("0.json"))

        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )
        let service = LiveCodexMonitorService(
            client: CodexAppServerStub(listedThreads: [], loadedListResults: []),
            hookEvents: repository,
            hookInstaller: installer,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        // Querying health repeatedly must leave the queued event untouched.
        for _ in 0 ..< 3 {
            _ = await service.hookSetupStatus()
        }
        #expect(
            FileManager.default.fileExists(
                atPath: paths.eventsDirectory
                    .appendingPathComponent("0.json").path
            )
        )

        // The snapshot path is the single consumer, and it still sees the Turn.
        let snapshot = await service.fetchSnapshot(showsContentPreviews: false)
        #expect(snapshot.sessions.first?.threadID == "thread-intact")
        #expect(snapshot.setupStatus == .active)
        await service.disconnect()
    }

    @Test @MainActor
    func installationHealthIsScannedOnDemandRatherThanOnACadence() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        let clock = TestClock()
        let timing = MonitorTiming.standard
        let installer = CodexHookInstaller(
            paths: paths,
            clock: clock,
            timing: timing
        )
        try await installer.install()
        #expect(await installer.status(hasObservedEvent: true) == .active)

        // Something outside this app removes a managed definition.
        var configuration = try #require(
            JSONSerialization.jsonObject(
                with: try Data(contentsOf: paths.hooksConfiguration)
            ) as? [String: Any]
        )
        var hooks = try #require(configuration["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "Stop")
        configuration["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: configuration)
            .write(to: paths.hooksConfiguration)

        // Within the window the cached answer stands: this app did not make the
        // change, so nothing invalidated it.
        await clock.advance(by: timing.installationRevalidationInterval - 1)
        #expect(await installer.status(hasObservedEvent: true) == .active)

        // Past it, one scan picks the damage up without any polling in between.
        await clock.advance(by: 2)
        #expect(await installer.status(hasObservedEvent: true) == .repairRequired)
    }

    @Test @MainActor
    func backgroundQuotaReadPublishesWithoutWaitingForADeadline() async throws {
        // Quota is read in the background, so it lands after the snapshot that
        // started it was already published. Nothing else was due for ten
        // seconds, so without its own trigger the ring stayed blank that long.
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()

        let clock = TestClock()
        let timing = MonitorTiming.standard
        let client = CodexAppServerStub(
            listedThreads: [.object([
                "id": .string("thread-quota"),
                "ephemeral": .bool(false),
                "threadSource": .string("user")
            ])],
            loadedListResults: []
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(
                paths: paths,
                clock: clock,
                timing: timing,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer,
            clock: clock,
            timing: timing
        )

        let triggers = service.stateChangeEvents
        let observer = Task {
            for await _ in triggers {
                return true
            }
            return false
        }

        let first = await service.fetchSnapshot(showsContentPreviews: false)
        #expect(first.quota.remainingPercent == nil)

        // The store would otherwise be asleep until the metadata window, which
        // is an order of magnitude further out than the read itself takes.
        let deadline = try #require(await service.nextRefreshDeadline())
        #expect(deadline.timeIntervalSince(clock.now()) >= 5)

        let signalled = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await observer.value }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
        observer.cancel()
        #expect(signalled)

        let second = await service.fetchSnapshot(showsContentPreviews: false)
        #expect(second.quota.remainingPercent == 70)
        await service.disconnect()
    }

    @Test @MainActor
    func refreshSleepsUntilTheNextDeadlineRatherThanACadence() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-deadline",
            "turn_id": "turn-deadline"
        ]).write(to: paths.eventsDirectory.appendingPathComponent("0.json"))

        let clock = TestClock()
        let timing = MonitorTiming.standard
        let client = CodexAppServerStub(
            listedThreads: [.object([
                "id": .string("thread-deadline"),
                "ephemeral": .bool(false),
                "threadSource": .string("user"),
                "name": .string("Deadline")
            ])],
            loadedListResults: []
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(
                paths: paths,
                clock: clock,
                timing: timing,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer,
            clock: clock,
            timing: timing,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        // Nothing has been read yet, so nothing is scheduled: a quiet monitor
        // falls through to the heartbeat instead of sampling.
        #expect(await service.nextRefreshDeadline() == nil)

        _ = await service.fetchSnapshot(showsContentPreviews: false)
        try await waitForThreadReads(client, atLeast: 1)

        // Once metadata is cached the next wake-up is its staleness boundary --
        // sooner than the membership window, and far sooner than the heartbeat.
        let deadline = try #require(await service.nextRefreshDeadline())
        let untilDeadline = deadline.timeIntervalSince(clock.now())
        #expect(untilDeadline <= timing.threadMetadataRefreshInterval)
        #expect(untilDeadline < timing.heartbeatInterval)
        await service.disconnect()
    }

    @Test @MainActor
    func notchLabelDrawsGlyphsAndSweepsThroughCoreAnimation() throws {
        // The notch label is layer-backed so its sweep costs no per-frame view
        // work. That trade is only worth anything if it still draws text: the
        // failure modes are a blank label, or an unmasked band painting a solid
        // bar across the notch. Neither is visible from a unit test directly,
        // but both are visible in the rasterised glyphs and the mask.
        let font = NSFont.systemFont(ofSize: 13, weight: .light)
        let text = "Approval needed"
        let view = SweepingLabelView()
        view.apply(text: text, font: font, isSweeping: true)

        // The same metrics PanelMetrics reserves compact width with, so the
        // label cannot be wider than the panel drawn for it.
        let measured = (text as NSString).size(withAttributes: [.font: font])
        #expect(view.intrinsicContentSize.width == ceil(measured.width))

        view.frame = NSRect(origin: .zero, size: view.intrinsicContentSize)
        view.layout()

        let sublayers = try #require(view.layer?.sublayers)
        #expect(sublayers.count == 2)
        let glyphs = try #require(sublayers.first)
        let highlight = try #require(sublayers.last)

        let contents = try #require(glyphs.contents)
        let image = unsafeDowncast(contents as AnyObject, to: CGImage.self)
        #expect(image.width >= Int(measured.width))

        // Text, not a filled rectangle: a solid band would have no transparent
        // pixels, and a label that failed to draw would have no opaque ones.
        let alphas = try Self.alphaExtremes(of: image)
        #expect(alphas.minimum == 0)
        #expect(alphas.maximum > 0.5)

        // The highlight rides a mask that Core Animation drives.
        #expect(!highlight.isHidden)
        let mask = try #require(highlight.mask)
        #expect(mask.animation(forKey: "notch.searchlight") != nil)

        view.apply(text: text, font: font, isSweeping: false)
        #expect(highlight.isHidden)
        #expect(mask.animation(forKey: "notch.searchlight") == nil)
    }

    private static func alphaExtremes(
        of image: CGImage
    ) throws -> (minimum: Double, maximum: Double) {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        try #require(drew)

        let alphas = stride(from: 3, to: pixels.count, by: 4).map {
            Double(pixels[$0]) / 255
        }
        return (alphas.min() ?? 1, alphas.max() ?? 0)
    }

    @Test @MainActor
    func sessionRowTextFadesItsOverflowAndSweepsThroughCoreAnimation() throws {
        // This row owns two masks that used to be SwiftUI's: the trailing fade
        // its caller applied, and the sweep over the bright copy. Getting either
        // wrong is silent -- a row that clips hard instead of fading, or a bar
        // painted across the panel -- so both are asserted on the layer.
        let font = NSFont.systemFont(ofSize: 13, weight: .light)
        let text = "A preview long enough to run past the row it is drawn in"
        let view = SessionRowTextView()
        view.apply(
            text: text,
            font: font,
            color: NotchPalette.labelDrawingColor,
            sweeps: true
        )

        // Narrower than the glyphs, which is the case the fade exists for.
        let glyphWidth = view.intrinsicContentSize.width
        let rowWidth = glyphWidth / 2
        view.frame = NSRect(x: 0, y: 0, width: rowWidth, height: 18)
        view.layout()

        let root = try #require(view.layer)
        let sublayers = try #require(root.sublayers)
        #expect(sublayers.count == 2)

        // Only what the row can show is drawn. The remainder sits behind the
        // fade, so drawing it would upload a texture per update for pixels that
        // are never composited -- and body text is replaced as a turn runs.
        let glyphs = try #require(sublayers.first)
        #expect(glyphs.frame.width == rowWidth)
        #expect(glyphs.frame.width < glyphWidth)
        let contents = try #require(glyphs.contents)
        let image = unsafeDowncast(contents as AnyObject, to: CGImage.self)
        let alphas = try Self.alphaExtremes(of: image)
        #expect(alphas.minimum == 0)
        #expect(alphas.maximum > 0.5)

        // The fade covers the row and turns transparent over its last stretch.
        let fade = try #require(root.mask as? CAGradientLayer)
        #expect(fade.frame.width == rowWidth)
        let locations = try #require(fade.locations)
        #expect(locations.count == 3)
        let fadeStart = try #require(locations.dropFirst().first).doubleValue
        #expect(fadeStart > 0)
        #expect(fadeStart < 1)

        // The bright copy sweeps across the glyphs, driven by Core Animation.
        let highlight = try #require(sublayers.last)
        #expect(!highlight.isHidden)
        let sweep = try #require(highlight.mask)
        #expect(sweep.animation(forKey: NotchTextRaster.sweepAnimationKey) != nil)

        view.apply(
            text: text,
            font: font,
            color: NotchPalette.labelDrawingColor,
            sweeps: false
        )
        #expect(highlight.isHidden)
        #expect(sweep.animation(forKey: NotchTextRaster.sweepAnimationKey) == nil)
    }

    @Test @MainActor
    func elapsedTicksDoNotRepublishTheStore() async throws {
        // Every publish on the store re-evaluates the whole overlay, profiled at
        // roughly 20ms. A readout advancing a second must not cost that: it used
        // to, and a turn sitting on an approval burned ~4% of a core doing
        // nothing but redrawing four characters. The readouts now take the tick
        // directly, so a second passing must be silent here.
        let clock = TestClock()
        let store = makeIdleStore(clock: clock)
        let startedAt = clock.now()
        store.applyForTesting(
            makeSessionSnapshot([
                makeSession(status: .approvalNeeded, startedAt: startedAt)
            ]),
            observedAt: clock.now()
        )
        await clock.settle()

        var publishes = 0
        let subscription = store.objectWillChange.sink { _ in publishes += 1 }
        defer { subscription.cancel() }

        // Nine seconds, every one of them a new reading, none of them a new
        // width: 0:01 through 0:09 are all four characters.
        await clock.advance(by: 9)
        #expect(store.compactTimerText == "0:09")
        #expect(
            publishes == 0,
            "a tick republished the store \(publishes) time(s)"
        )

        // Crossing into 10:00 does change the reserved width, and the panel has
        // to re-measure for that -- so exactly here a publish is expected.
        await clock.advance(by: 591)
        #expect(store.compactTimerText == "10:00")
        #expect(publishes > 0, "a width change must reach the panel")
    }

    @Test @MainActor
    func sweepPhaseSurvivesTheTextBeingReplaced() throws {
        // A running turn's body text is its live progress, so it is replaced
        // every few seconds -- and every replacement re-rasterises the glyphs
        // and re-installs the sweep. If the sweep's phase came from the moment
        // it was installed, each update would restart it.
        //
        // That is not a cosmetic stutter. The band is four times the width of
        // what it crosses and its bright peak sits at the centre, so the peak
        // does not reach the glyphs until 40% into the loop. Restarting more
        // often than that means the highlight is never drawn at all.
        let font = NSFont.systemFont(ofSize: 13, weight: .light)
        let view = SessionRowTextView()
        view.apply(
            text: "Reading LiveCodexMonitorService.swift",
            font: font,
            color: NotchPalette.labelDrawingColor,
            sweeps: true
        )
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 18)
        view.layout()

        let highlight = try #require(view.layer?.sublayers?.last)
        let mask = try #require(highlight.mask)
        let before = try #require(
            mask.animation(forKey: NotchTextRaster.sweepAnimationKey)
        )

        view.apply(
            text: "Now editing NotchStatusMatrix.swift instead",
            font: font,
            color: NotchPalette.labelDrawingColor,
            sweeps: true
        )
        let after = try #require(
            mask.animation(forKey: NotchTextRaster.sweepAnimationKey)
        )

        // Phase is anchored to a global grid of whole periods, so it is a
        // function of the clock rather than of when the text last changed.
        // A left-at-default `beginTime` of 0 is exactly the broken case: Core
        // Animation then starts the loop at whatever moment it was added.
        for (label, animation) in [("before", before), ("after", after)] {
            #expect(
                animation.beginTime > 0,
                "\(label) sweep starts when it was installed, not on the clock"
            )
            let offset = animation.beginTime.truncatingRemainder(
                dividingBy: SessionRowTextView.sweepPeriod
            )
            #expect(
                abs(offset) < 0.001,
                "\(label) sweep is not aligned to a whole-period boundary"
            )
        }
    }

    @Test @MainActor
    func refreshLoopNeverSpinsOnAnOverdueDeadline() async throws {
        // The store cannot verify a service's deadlines, so it must stay bounded
        // when one is wrong. Without a floor an overdue deadline sleeps zero and
        // the loop runs full snapshots continuously -- measured at 63% of a core
        // with the main thread inside a synchronous LaunchServices round trip.
        let clock = TestClock()
        let timing = MonitorTiming.standard
        let service = StuckDeadlineMonitoringStub(
            deadline: clock.now().addingTimeInterval(-5)
        )
        let store = MonitorStore(
            displays: [
                makeDisplay(
                    id: "display-1",
                    ordinal: 1,
                    menuBarHeight: 38,
                    hasNotch: true
                )
            ],
            service: service,
            initialSnapshot: .connecting,
            clock: clock,
            timing: timing
        )

        for _ in 0 ..< 8 {
            await clock.advance(by: timing.minimumRefreshInterval)
        }

        let requested = clock.requestedSleepIntervals
        #expect(!requested.isEmpty)
        #expect(requested.allSatisfy { $0 >= timing.minimumRefreshInterval })
        // Bounded work, not "no work": the loop still converges on the deadline.
        #expect(await service.snapshotCount() <= 10)
        store.stopMonitoring()
    }

    @Test @MainActor
    func refreshDeadlineNeverFallsIntoThePast() async throws {
        // The store sleeps `max(0, deadline - now)`, so a deadline the service
        // can never advance is not a late wake-up -- it is a zero-length sleep
        // in an unconditional loop, i.e. a busy loop running full snapshots.
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-hooked",
            "turn_id": "turn-hooked"
        ]).write(to: paths.eventsDirectory.appendingPathComponent("0.json"))

        let clock = TestClock()
        let timing = MonitorTiming.standard
        // Only `thread-hooked` is driven by a Hook. `thread-idle` is an ordinary
        // unarchived thread -- the state of every real account.
        let client = CodexAppServerStub(
            listedThreads: [
                .object([
                    "id": .string("thread-hooked"),
                    "ephemeral": .bool(false),
                    "threadSource": .string("user"),
                    "name": .string("Hooked")
                ]),
                .object([
                    "id": .string("thread-idle"),
                    "ephemeral": .bool(false),
                    "threadSource": .string("user"),
                    "name": .string("Idle")
                ])
            ],
            loadedListResults: []
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(
                paths: paths,
                clock: clock,
                timing: timing,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer,
            clock: clock,
            timing: timing,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        _ = await service.fetchSnapshot(showsContentPreviews: false)
        try await waitForThreadListRequests(client, atLeast: 1, completed: true)
        try await waitForThreadReads(client, atLeast: 1)

        // Past the per-thread metadata window, still inside the membership one.
        await clock.advance(by: timing.threadMetadataRefreshInterval + 1)
        _ = await service.fetchSnapshot(showsContentPreviews: false)
        try await waitForThreadReads(client, atLeast: 2)

        let deadline = try #require(await service.nextRefreshDeadline())
        #expect(deadline >= clock.now())
        await service.disconnect()
    }

    @Test @MainActor
    func backgroundReadsHonourTheirOwnFreshnessWindows() async throws {
        // These windows previously had no coverage at all: every one of them was
        // a bare Date() comparison, so nothing could state when a background
        // read actually repeats. With an injected clock they are exact.
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()

        let clock = TestClock()
        let timing = MonitorTiming.standard
        var eventIndex = 0
        func emitHookActivity() throws {
            eventIndex += 1
            let event: [String: Any] = [
                "received_at": clock.now().timeIntervalSince1970,
                "hook_event_name": eventIndex == 1 ? "UserPromptSubmit" : "PostToolUse",
                "session_id": "thread-window",
                "turn_id": "turn-window",
                "tool_name": "Bash",
                "tool_use_id": "exec-\(eventIndex)"
            ]
            try JSONSerialization.data(withJSONObject: event).write(
                to: paths.eventsDirectory.appendingPathComponent("\(eventIndex).json")
            )
        }

        let client = CodexAppServerStub(
            listedThreads: [.object([
                "id": .string("thread-window"),
                "ephemeral": .bool(false),
                "threadSource": .string("user"),
                "name": .string("Windowed")
            ])],
            loadedListResults: []
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(
                paths: paths,
                clock: clock,
                timing: timing,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer,
            clock: clock,
            timing: timing,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        try emitHookActivity()
        _ = await service.fetchSnapshot(showsContentPreviews: false)
        try await waitForThreadListRequests(client, atLeast: 1, completed: true)
        try await waitForThreadReads(client, atLeast: 1)
        #expect(await client.requestCount(method: "thread/list") == 1)
        #expect(await client.requestCount(method: "thread/read") == 1)

        // Just short of each window: plenty of Hook activity, no repeat reads.
        await clock.advance(by: timing.threadMetadataRefreshInterval - 1)
        try emitHookActivity()
        _ = await service.fetchSnapshot(showsContentPreviews: false)
        await clock.settle()
        #expect(await client.requestCount(method: "thread/read") == 1)
        #expect(await client.requestCount(method: "thread/list") == 1)

        // Past the metadata window only: the cheap read repeats, the expensive
        // membership pagination still does not.
        await clock.advance(by: 2)
        try emitHookActivity()
        _ = await service.fetchSnapshot(showsContentPreviews: false)
        try await waitForThreadReads(client, atLeast: 2)
        #expect(await client.requestCount(method: "thread/list") == 1)

        // Past the membership window: the full list repeats exactly once.
        await clock.advance(by: timing.threadListRefreshInterval)
        try emitHookActivity()
        _ = await service.fetchSnapshot(showsContentPreviews: false)
        try await waitForThreadListRequests(client, atLeast: 2, completed: true)
        #expect(await client.requestCount(method: "thread/list") == 2)

        await service.disconnect()
    }

    @Test @MainActor
    func hookActivityReadsOnlyItsOwnThreadsInsteadOfTheWholeList() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        let prompt = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-active",
            "turn_id": "turn-active"
        ])
        try prompt.write(
            to: paths.eventsDirectory.appendingPathComponent("0.json")
        )

        // One thread is in the Hook reducer; the rest are only history.
        let listedThreads = (0 ..< 40).map { index -> JSONValue in
            .object([
                "id": .string(index == 0 ? "thread-active" : "thread-\(index)"),
                "ephemeral": .bool(false),
                "threadSource": .string("user"),
                "name": .string(index == 0 ? "Active work" : "History \(index)"),
                "status": .object([
                    "type": .string("active"),
                    "activeFlags": .array([])
                ])
            ])
        }
        let client = CodexAppServerStub(
            listedThreads: listedThreads,
            loadedListResults: []
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(
                paths: paths,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        _ = await service.fetchSnapshot(showsContentPreviews: false)
        try await waitForThreadListRequests(client, atLeast: 1, completed: true)

        // Drive many more Hook-consuming rounds. Membership was just
        // reconciled, so none of them may re-paginate the full list.
        for index in 1 ... 6 {
            let event = try JSONSerialization.data(withJSONObject: [
                "received_at": Date().timeIntervalSince1970,
                "hook_event_name": "PostToolUse",
                "session_id": "thread-active",
                "turn_id": "turn-active",
                "tool_name": "shell",
                "tool_use_id": "tool-\(index)"
            ])
            try event.write(
                to: paths.eventsDirectory.appendingPathComponent("\(index).json")
            )
            _ = await service.fetchSnapshot(showsContentPreviews: false)
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let snapshot = await service.fetchSnapshot(showsContentPreviews: false)
        let threadListCount = await client.requestCount(method: "thread/list")
        let readParams = await client.recordedThreadReadParams()
        await service.disconnect()

        #expect(threadListCount == 1)
        #expect(!readParams.isEmpty)
        // Only the reducer's own thread is read, and never with Turn history.
        for params in readParams {
            #expect(params["threadId"]?.stringValue == "thread-active")
            #expect(params["includeTurns"]?.boolValue == false)
        }
        #expect(snapshot.sessions.first?.title == "Active work")
    }

    @Test @MainActor
    func metadataReadFallsBackToTheFullListWhenUnsupported() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        let prompt = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-active",
            "turn_id": "turn-active"
        ])
        try prompt.write(
            to: paths.eventsDirectory.appendingPathComponent("0.json")
        )

        let client = CodexAppServerStub(
            listedThreads: [.object([
                "id": .string("thread-active"),
                "ephemeral": .bool(false),
                "threadSource": .string("user"),
                "name": .string("Legacy build"),
                "status": .object([
                    "type": .string("active"),
                    "activeFlags": .array([])
                ])
            ])],
            loadedListResults: [],
            supportsThreadRead: false
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(
                paths: paths,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        _ = await service.fetchSnapshot(showsContentPreviews: false)
        try await waitForThreadListRequests(client, atLeast: 1, completed: true)

        let event = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "PostToolUse",
            "session_id": "thread-active",
            "turn_id": "turn-active",
            "tool_name": "shell",
            "tool_use_id": "tool-1"
        ])
        try event.write(
            to: paths.eventsDirectory.appendingPathComponent("1.json")
        )
        _ = await service.fetchSnapshot(showsContentPreviews: false)
        // A server without thread/read must keep getting whole-list metadata
        // rather than silently losing titles.
        try await waitForThreadListRequests(client, atLeast: 2)

        let snapshot = await service.fetchSnapshot(showsContentPreviews: false)
        let readAttempts = await client.requestCount(method: "thread/read")
        await service.disconnect()

        // The unsupported method is probed once, then never retried.
        #expect(readAttempts == 1)
        #expect(snapshot.sessions.first?.title == "Legacy build")
    }

    @Test
    func appServerMessageBufferFramesArbitrarilyChunkedMessages() throws {
        var buffer = NewlineDelimitedMessageBuffer()

        #expect(buffer.append(Data(#"{"id":1,"res"#.utf8)).isEmpty)

        let middleMessages = buffer.append(
            Data("ult\":{}}\n{\"id\":2}\n\n{\"id".utf8)
        )
        #expect(middleMessages.count == 3)
        #expect(String(data: middleMessages[0], encoding: .utf8) == #"{"id":1,"result":{}}"#)
        #expect(String(data: middleMessages[1], encoding: .utf8) == #"{"id":2}"#)
        #expect(middleMessages[2].isEmpty)

        let finalMessages = buffer.append(Data("\":3}\n".utf8))
        #expect(finalMessages.count == 1)
        #expect(String(data: finalMessages[0], encoding: .utf8) == #"{"id":3}"#)
        #expect(buffer.bufferedByteCount == 0)
    }

    @Test
    func appServerMessageBufferScansLargeChunkedMessageOnlyOnce() throws {
        var buffer = NewlineDelimitedMessageBuffer()
        let messageSize = 4 * 1_024 * 1_024
        let message = Data(repeating: 0x78, count: messageSize)
        let chunkSize = 1_024

        for offset in stride(from: 0, to: message.count, by: chunkSize) {
            let end = min(offset + chunkSize, message.count)
            let emitted = buffer.append(Data(message[offset..<end]))
            #expect(emitted.isEmpty)
        }

        let emitted = buffer.append(Data([0x0A]))
        let framedMessage = try #require(emitted.first)
        #expect(emitted.count == 1)
        #expect(framedMessage.count == messageSize)
        #expect(framedMessage.first == 0x78)
        #expect(framedMessage.last == 0x78)
        #expect(buffer.scannedByteCount == messageSize + 1)
        #expect(buffer.bufferedByteCount == 0)
    }

    @Test
    func appServerStreamPumpPreservesFrameOrderAcrossPipeSizedChunks() async throws {
        let (events, continuation) = AsyncStream.makeStream(
            of: AppServerStreamEvent.self,
            bufferingPolicy: .unbounded
        )
        let pump = AppServerStreamPump(
            maximumFrameByteCount: 4 * 1_024 * 1_024,
            continuation: continuation
        )

        // Each message is far larger than one pipe read, so the pump only frames
        // them correctly if it observes every chunk in the order it was written.
        let payload = String(repeating: "x", count: 200_000)
        let messages = (1 ... 5).map { #"{"id":\#($0),"result":"\#(payload)"}"# }
        let stream = Data(messages.joined(separator: "\n").utf8) + Data([0x0A])

        let chunkSize = 4_096
        for offset in stride(from: 0, to: stream.count, by: chunkSize) {
            let end = min(offset + chunkSize, stream.count)
            pump.ingest(Data(stream[offset ..< end]))
        }
        pump.ingest(Data())

        var frames: [String] = []
        var didEnd = false
        for await event in events {
            switch event {
            case let .frame(frame):
                frames.append(String(decoding: frame, as: UTF8.self))
            case .streamEnded:
                didEnd = true
            case .framingOverflow:
                Issue.record("Unexpected framing overflow")
            }
        }

        #expect(didEnd)
        #expect(frames == messages)
    }

    @Test
    func appServerStreamPumpFailsClosedOnOversizedFrame() async throws {
        let (events, continuation) = AsyncStream.makeStream(
            of: AppServerStreamEvent.self,
            bufferingPolicy: .unbounded
        )
        let pump = AppServerStreamPump(
            maximumFrameByteCount: 4_096,
            continuation: continuation
        )

        pump.ingest(Data(#"{"id":1,"result":{}}"#.utf8) + Data([0x0A]))
        // No newline ever arrives for the next frame.
        for _ in 0 ..< 3 {
            pump.ingest(Data(repeating: 0x78, count: 2_048))
        }
        // Anything after fail-closed must be ignored rather than reframed.
        pump.ingest(Data("\n".utf8))

        var frames: [String] = []
        var overflowByteCount: Int?
        for await event in events {
            switch event {
            case let .frame(frame):
                frames.append(String(decoding: frame, as: UTF8.self))
            case let .framingOverflow(bufferedByteCount):
                overflowByteCount = bufferedByteCount
            case .streamEnded:
                Issue.record("Unexpected stream end")
            }
        }

        #expect(frames == [#"{"id":1,"result":{}}"#])
        #expect(overflowByteCount == 6_144)
    }

    @Test @MainActor
    func largeResponseDoesNotSwallowTheFollowingResponse() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexInNotchFramingTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        let executable = root.appendingPathComponent("fake_app_server.py")
        let source = #"""
#!/usr/bin/python3
import json
import sys

PAYLOAD = "x" * 1000000

for line in sys.stdin:
    try:
        request = json.loads(line)
        if "id" not in request:
            continue
        if request.get("method") == "big/read":
            result = {"payload": PAYLOAD}
        else:
            result = {}
        print(json.dumps({"id": request["id"], "result": result}), flush=True)
    except Exception:
        pass
"""#
        try source.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )

        let client = CodexAppServerClient(
            executableURL: executable,
            requestTimeoutNanoseconds: 10_000_000_000
        )
        try await client.connect()

        // A multi-chunk response used to corrupt the frame boundary and take the
        // next response down with it, so both requests here must resolve.
        for _ in 0 ..< 12 {
            async let big = client.request(method: "big/read", params: nil)
            async let small = client.request(method: "small/read", params: nil)
            let (bigResponse, smallResponse) = try await (big, small)
            #expect(bigResponse["payload"]?.stringValue?.count == 1_000_000)
            #expect(smallResponse.objectValue?.isEmpty == true)
        }
        await client.disconnect()
    }

    @Test @MainActor
    func concurrentConnectsShareOneAppServerProcess() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexInNotchAppServerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let executable = root.appendingPathComponent("fake_app_server.py")
        let countFile = executable.appendingPathExtension("count")
        let source = #"""
#!/usr/bin/python3
import json
import os
import sys

count_path = os.path.abspath(__file__) + ".count"
try:
    with open(count_path, "r", encoding="utf-8") as handle:
        count = int(handle.read())
except Exception:
    count = 0
with open(count_path, "w", encoding="utf-8") as handle:
    handle.write(str(count + 1))

for line in sys.stdin:
    try:
        request = json.loads(line)
        if "id" in request:
            print(json.dumps({"id": request["id"], "result": {}}), flush=True)
    except Exception:
        pass
"""#
        try source.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )

        let client = CodexAppServerClient(
            executableURL: executable,
            requestTimeoutNanoseconds: 2_000_000_000
        )
        async let first: Void = client.connect()
        async let second: Void = client.connect()
        _ = try await (first, second)

        let launchCount = try String(contentsOf: countFile, encoding: .utf8)
        await client.disconnect()

        #expect(launchCount == "1")
    }

    @Test @MainActor
    func failedLivenessProbeResetsUnresponsiveAppServer() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexInNotchTimeoutTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        let executable = root.appendingPathComponent("fake_app_server.py")
        let countFile = executable.appendingPathExtension("count")
        let source = #"""
#!/usr/bin/python3
import json
import os
import sys

count_path = os.path.abspath(__file__) + ".count"
try:
    with open(count_path, "r", encoding="utf-8") as handle:
        launch = int(handle.read()) + 1
except Exception:
    launch = 1
with open(count_path, "w", encoding="utf-8") as handle:
    handle.write(str(launch))

for line in sys.stdin:
    try:
        request = json.loads(line)
        if "id" not in request:
            continue
        if request.get("method") == "initialize" or launch > 1:
            print(json.dumps({"id": request["id"], "result": {}}), flush=True)
    except Exception:
        pass
"""#
        try source.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )

        let client = CodexAppServerClient(
            executableURL: executable,
            requestTimeoutNanoseconds: 2_000_000_000,
            livenessProbeGraceNanoseconds: 50_000_000,
            livenessProbeTimeoutNanoseconds: 100_000_000
        )
        try await client.connect()

        do {
            _ = try await client.request(
                method: "business/read",
                params: nil,
                timeoutNanoseconds: 100_000_000
            )
            Issue.record("Expected business/read to time out")
        } catch let error as CodexAppServerError {
            #expect(error == .timeout(method: "business/read"))
        }

        try await Task.sleep(nanoseconds: 300_000_000)
        try await client.connect()
        _ = try await client.request(method: "recovered/probe", params: nil)
        let launchCount = try String(contentsOf: countFile, encoding: .utf8)
        await client.disconnect()

        #expect(launchCount == "2")
    }

    @Test @MainActor
    func concurrentBusinessTimeoutsDoNotBypassSuccessfulLivenessProbe() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexInNotchProbeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        let executable = root.appendingPathComponent("fake_app_server.py")
        let countFile = executable.appendingPathExtension("count")
        let probeFile = executable.appendingPathExtension("probe")
        let source = #"""
#!/usr/bin/python3
import json
import os
import sys

count_path = os.path.abspath(__file__) + ".count"
probe_path = os.path.abspath(__file__) + ".probe"
try:
    with open(count_path, "r", encoding="utf-8") as handle:
        launch = int(handle.read()) + 1
except Exception:
    launch = 1
with open(count_path, "w", encoding="utf-8") as handle:
    handle.write(str(launch))

for line in sys.stdin:
    try:
        request = json.loads(line)
        if "id" not in request:
            continue
        method = request.get("method")
        if method == "thread/loaded/list":
            with open(probe_path, "w", encoding="utf-8") as handle:
                handle.write("ok")
            result = {"data": []}
        elif method in ("initialize", "after/probe"):
            result = {}
        else:
            continue
        print(json.dumps({"id": request["id"], "result": result}), flush=True)
    except Exception:
        pass
"""#
        try source.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )

        let client = CodexAppServerClient(
            executableURL: executable,
            requestTimeoutNanoseconds: 2_000_000_000,
            livenessProbeGraceNanoseconds: 300_000_000,
            livenessProbeTimeoutNanoseconds: 100_000_000
        )
        try await client.connect()

        let timeoutErrors = await withTaskGroup(
            of: CodexAppServerError?.self,
            returning: [CodexAppServerError].self
        ) { group in
            for method in ["first/read", "second/read"] {
                group.addTask {
                    do {
                        _ = try await client.request(
                            method: method,
                            params: nil,
                            timeoutNanoseconds: 100_000_000
                        )
                        Issue.record("Expected \(method) to time out")
                        return nil
                    } catch let error as CodexAppServerError {
                        return error
                    } catch {
                        Issue.record("Unexpected error for \(method): \(error)")
                        return nil
                    }
                }
            }

            var errors: [CodexAppServerError] = []
            for await error in group {
                if let error {
                    errors.append(error)
                }
            }
            return errors
        }
        #expect(timeoutErrors.count == 2)
        #expect(timeoutErrors.contains(.timeout(method: "first/read")))
        #expect(timeoutErrors.contains(.timeout(method: "second/read")))

        try await Task.sleep(nanoseconds: 450_000_000)
        _ = try await client.request(method: "after/probe", params: nil)
        let launchCount = try String(contentsOf: countFile, encoding: .utf8)
        await client.disconnect()

        #expect(FileManager.default.fileExists(atPath: probeFile.path))
        #expect(launchCount == "1")
    }

    @Test @MainActor
    func lateResponseDuringGracePeriodPreventsLivenessProbe() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexInNotchLateResponseTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        let executable = root.appendingPathComponent("fake_app_server.py")
        let countFile = executable.appendingPathExtension("count")
        let probeFile = executable.appendingPathExtension("probe")
        let source = #"""
#!/usr/bin/python3
import json
import os
import sys
import time

count_path = os.path.abspath(__file__) + ".count"
probe_path = os.path.abspath(__file__) + ".probe"
with open(count_path, "w", encoding="utf-8") as handle:
    handle.write("1")

for line in sys.stdin:
    try:
        request = json.loads(line)
        if "id" not in request:
            continue
        method = request.get("method")
        if method == "slow/read":
            time.sleep(0.15)
        if method == "thread/loaded/list":
            with open(probe_path, "w", encoding="utf-8") as handle:
                handle.write("unexpected")
            result = {"data": []}
        else:
            result = {}
        print(json.dumps({"id": request["id"], "result": result}), flush=True)
    except Exception:
        pass
"""#
        try source.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )

        let client = CodexAppServerClient(
            executableURL: executable,
            requestTimeoutNanoseconds: 2_000_000_000,
            livenessProbeGraceNanoseconds: 300_000_000,
            livenessProbeTimeoutNanoseconds: 100_000_000
        )
        try await client.connect()

        do {
            _ = try await client.request(
                method: "slow/read",
                params: nil,
                timeoutNanoseconds: 100_000_000
            )
            Issue.record("Expected slow/read to time out")
        } catch let error as CodexAppServerError {
            #expect(error == .timeout(method: "slow/read"))
        }

        try await Task.sleep(nanoseconds: 400_000_000)
        _ = try await client.request(method: "after/late-response", params: nil)
        let launchCount = try String(contentsOf: countFile, encoding: .utf8)
        await client.disconnect()

        #expect(!FileManager.default.fileExists(atPath: probeFile.path))
        #expect(launchCount == "1")
    }

    /// The mechanism the three fixes share, on its own.
    ///
    /// Mutating calls are hoisted out of `#expect`, which cannot invoke them on
    /// the value it captures.
    @Test
    func singleFlightGateNeverLosesARequestMadeDuringARun() {
        var gate = SingleFlightGate()
        #expect(!gate.isPending)

        let first = gate.request()
        #expect(gate.isPending)
        let claimed = gate.beginRun()
        #expect(claimed)

        // A second caller cannot start a parallel run.
        let claimedAgain = gate.beginRun()
        #expect(!claimedAgain)

        // Nothing else asked, so one run settles it.
        let repeatsAfterQuietRun = gate.endRun()
        #expect(!repeatsAfterQuietRun)
        #expect(gate.hasCovered(first))
        #expect(!gate.isPending)

        // A request landing mid-run is covered by a follow-up, and the claim
        // passes straight from one run to the next so nothing can slip between.
        let second = gate.request()
        let claimedSecond = gate.beginRun()
        #expect(claimedSecond)
        let third = gate.request()
        let repeatsAfterBusyRun = gate.endRun()
        #expect(repeatsAfterBusyRun)
        // The claim was handed straight over, so nobody can start a third run.
        let blockedMidHandover = gate.beginRun()
        #expect(!blockedMidHandover)
        #expect(gate.hasCovered(second))
        #expect(!gate.hasCovered(third))

        let repeatsAfterCatchUp = gate.endRun()
        #expect(!repeatsAfterCatchUp)
        #expect(gate.hasCovered(third))
    }

    /// A failed run keeps its request, and must not retry itself.
    ///
    /// Continuing on failure looks like the helpful thing to do and is an
    /// unbounded retry loop with no backoff in it: the request is still
    /// outstanding, so the gate hands the claim straight back and the caller
    /// runs again, forever. Measured before this was fixed: 1000 iterations
    /// with no sign of stopping. The guard against it originally lived in the
    /// call site, where the cancellation path walked straight past it.
    @Test
    func singleFlightGateKeepsAFailedRequestButDoesNotRetryItself() {
        var gate = SingleFlightGate()
        let revision = gate.request()
        let claimed = gate.beginRun()
        #expect(claimed)

        var continuations = 0
        var shouldContinue = gate.endRun(covered: false)
        while shouldContinue, continuations < 1_000 {
            continuations += 1
            shouldContinue = gate.endRun(covered: false)
        }
        #expect(continuations == 0, "a failed run retried itself \(continuations) times")

        #expect(gate.isPending, "a failed read must leave its request outstanding")
        #expect(!gate.hasCovered(revision))

        // Once the cool-off expires the same request is still there to serve.
        let retried = gate.beginRun()
        #expect(retried)
        let repeats = gate.endRun(covered: true)
        #expect(!repeats)
        #expect(gate.hasCovered(revision))
        #expect(!gate.isPending)
    }

    /// Cancelling a run must not wedge the gate closed forever.
    @Test
    func singleFlightGateResetReleasesAClaimHeldByACancelledRun() {
        var gate = SingleFlightGate()
        gate.request()
        let claimed = gate.beginRun()
        #expect(claimed)
        let blockedWhileRunning = gate.beginRun()
        #expect(!blockedWhileRunning)

        gate.reset()
        #expect(!gate.isPending)

        gate.request()
        let claimedAfterReset = gate.beginRun()
        #expect(claimedAfterReset, "a reset gate must be able to run again")
    }

    /// A watcher built before its directory exists must still come to life.
    ///
    /// This is the CR-025 shape exactly: the Hook event directory is created by
    /// the installer, minutes after the watcher is constructed at launch. The
    /// old code opened once in `init` and treated failure as permanent, so on a
    /// first run the low-latency path was dead for the whole process.
    @Test
    func watcherAttachesAfterItsDirectoryAppearsAndDeliversToExistingSubscribers() async throws {
        let root = makeTemporaryWatchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("events")

        let watcher = DirectoryChangeWatcher(
            directoryURL: directory,
            debounceInterval: 0.05
        )
        #expect(!watcher.isAttached)

        // Subscribing while detached must yield a live stream, not a finished
        // one -- the old `events()` refused and could never recover.
        let stream = watcher.events()

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        #expect(watcher.attachIfNeeded())
        #expect(watcher.isAttached)

        try Data("{}".utf8).write(to: directory.appendingPathComponent("a.json"))
        #expect(await receivesChange(stream))
    }

    /// Deleting and recreating the directory is the uninstall/reinstall path.
    @Test
    func watcherReattachesAfterItsDirectoryIsDeletedAndRecreated() async throws {
        let root = makeTemporaryWatchRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("events")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let watcher = DirectoryChangeWatcher(
            directoryURL: directory,
            debounceInterval: 0.05
        )
        #expect(watcher.isAttached)
        let stream = watcher.events()
        try Data("{}".utf8).write(to: directory.appendingPathComponent("a.json"))
        #expect(await receivesChange(stream))

        // Uninstall removes the directory. The descriptor now refers to an
        // inode nothing will ever write to again.
        try FileManager.default.removeItem(at: directory)
        try await Task.sleep(nanoseconds: 300_000_000)

        // Reinstall recreates it.
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        #expect(watcher.attachIfNeeded())

        let secondStream = watcher.events()
        try Data("{}".utf8).write(to: directory.appendingPathComponent("b.json"))
        #expect(await receivesChange(secondStream))
    }

    /// The end-to-end first run: repository at launch, install, then a hook.
    @Test
    func hookEventsReachTheLowLatencyPathOnAFirstRunInstall() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        #expect(
            !FileManager.default.fileExists(atPath: paths.eventsDirectory.path),
            "the support directory must not exist yet for this to be a first run"
        )

        // Constructed at launch, before onboarding has installed anything.
        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )
        #expect(!repository.isEventWatcherAttached)
        let stream = repository.changeEvents()

        // Onboarding installs, which is what creates the event directory.
        try await CodexHookInstaller(paths: paths).install()
        #expect(repository.attachEventWatcher())
        #expect(repository.isEventWatcherAttached)

        // The very next hook must arrive on the watcher rather than waiting out
        // a refresh deadline.
        try Data(#"{"received_at": 1}"#.utf8).write(
            to: paths.eventsDirectory.appendingPathComponent("1.json")
        )
        #expect(await receivesChange(stream))
    }

    /// A refresh re-attaches on its own, so the explicit nudge is a latency
    /// optimisation rather than the only route back.
    @Test
    func consumingEventsReattachesAWatcherThatCouldNotBindAtLaunch() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )
        #expect(!repository.isEventWatcherAttached)

        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )
        // No explicit attach: just the refresh the store performs anyway.
        _ = await repository.consumeEvents()
        #expect(repository.isEventWatcherAttached)
    }

    /// Configurations this app must refuse to edit rather than guess at.
    ///
    /// Every one of these is *valid JSON* -- malformed JSON already failed
    /// closed. These are the shapes the old implementation coerced away with
    /// `as? [String: Any] ?? [:]`, each of which silently replaced content the
    /// user owned.
    private static let hostileHookConfigurations: [(name: String, json: String)] = [
        (
            "root is an array",
            #"["not", "an", "object"]"#
        ),
        (
            "hooks is a string",
            #"{"hooks": "please do not eat this"}"#
        ),
        (
            "hooks is an array",
            #"{"hooks": [{"Stop": []}]}"#
        ),
        (
            "a managed event holds a string",
            #"{"hooks": {"Stop": "run-my-own-thing.sh"}}"#
        ),
        (
            "a managed event holds an array of strings",
            #"{"hooks": {"PreToolUse": ["do-a-thing"]}}"#
        ),
        (
            "a managed event's group hooks is a string",
            #"{"hooks": {"Stop": [{"hooks": "not-an-array"}]}}"#
        ),
        (
            "a managed event's group hooks mixes objects and strings",
            #"{"hooks": {"Stop": [{"hooks": [{"type": "command"}, "stray"]}]}}"#
        )
    ]

    /// Installing must never damage a configuration it does not understand.
    ///
    /// This is the CR-013 regression, and it matters well beyond Codex: the
    /// same merge shape is what a second agent's configuration would need, and
    /// those files carry far more than hooks.
    @Test @MainActor
    func installRefusesUnparseableConfigurationsAndLeavesThemByteIdentical() async throws {
        for hostile in Self.hostileHookConfigurations {
            let paths = makeTemporaryHookPaths()
            defer {
                try? FileManager.default.removeItem(
                    at: paths.supportDirectory.deletingLastPathComponent()
                )
            }
            try FileManager.default.createDirectory(
                at: paths.hooksConfiguration.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let originalBytes = Data(hostile.json.utf8)
            try originalBytes.write(to: paths.hooksConfiguration)

            let installer = CodexHookInstaller(paths: paths)
            var refused = false
            do {
                try await installer.install()
            } catch {
                refused = true
            }

            let afterBytes = try Data(contentsOf: paths.hooksConfiguration)
            #expect(refused, "install should refuse when \(hostile.name)")
            #expect(
                afterBytes == originalBytes,
                "install rewrote the file when \(hostile.name)"
            )
        }
    }

    /// Uninstalling must never corrupt the file and never leave a dangling
    /// command, whatever shape it meets.
    ///
    /// Asserted as the invariant rather than the mechanism, because there are
    /// two legitimate outcomes. If nothing of this app's is present, uninstall
    /// may proceed and must not touch the file. If something is present but
    /// unreachable, it must refuse and keep the helper. What it may never do is
    /// rewrite the file or delete a helper that is still referenced -- which is
    /// exactly what the old code did, silently.
    @Test @MainActor
    func uninstallNeverCorruptsTheConfigurationOrStrandsTheHelper() async throws {
        for hostile in Self.hostileHookConfigurations {
            let paths = makeTemporaryHookPaths()
            defer {
                try? FileManager.default.removeItem(
                    at: paths.supportDirectory.deletingLastPathComponent()
                )
            }
            try FileManager.default.createDirectory(
                at: paths.hooksConfiguration.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // A completed install, so there is a helper to strand.
            let installer = CodexHookInstaller(paths: paths)
            try await installer.install()
            #expect(FileManager.default.isExecutableFile(atPath: paths.script.path))

            // Then the configuration turns into something unreadable.
            let originalBytes = Data(hostile.json.utf8)
            try originalBytes.write(to: paths.hooksConfiguration)
            let managedCommand = "/usr/bin/python3 \"\(paths.script.path)\""

            var refused = false
            do {
                try await installer.uninstall()
            } catch {
                refused = true
            }

            let afterBytes = try Data(contentsOf: paths.hooksConfiguration)
            #expect(
                afterBytes == originalBytes,
                "uninstall rewrote the file when \(hostile.name)"
            )
            if refused {
                #expect(
                    FileManager.default.fileExists(atPath: paths.script.path),
                    "uninstall refused but still deleted the helper when \(hostile.name)"
                )
            } else {
                // Proceeding is only allowed when nothing referenced the helper.
                let remaining = try #require(
                    String(data: afterBytes, encoding: .utf8)
                )
                #expect(
                    !remaining.contains(paths.script.path),
                    "uninstall deleted a helper the file still references when \(hostile.name)"
                )
            }
        }
    }

    /// The three shapes where the document itself cannot be read must always
    /// refuse, because proceeding would mean writing over it.
    @Test @MainActor
    func uninstallRefusesWhenTheDocumentItselfCannotBeRead() async throws {
        let unreadable = [
            #"["not", "an", "object"]"#,
            #"{"hooks": "please do not eat this"}"#,
            #"{"hooks": [{"Stop": []}]}"#
        ]
        for json in unreadable {
            let paths = makeTemporaryHookPaths()
            defer {
                try? FileManager.default.removeItem(
                    at: paths.supportDirectory.deletingLastPathComponent()
                )
            }
            try FileManager.default.createDirectory(
                at: paths.hooksConfiguration.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let installer = CodexHookInstaller(paths: paths)
            try await installer.install()
            try Data(json.utf8).write(to: paths.hooksConfiguration)

            var refused = false
            do {
                try await installer.uninstall()
            } catch {
                refused = true
            }
            #expect(refused, "uninstall should refuse: \(json)")
            #expect(FileManager.default.fileExists(atPath: paths.script.path))
            #expect(try Data(contentsOf: paths.hooksConfiguration) == Data(json.utf8))
        }
    }

    /// The command hiding somewhere the structured editor cannot reach.
    ///
    /// The deep scan is what makes the guarantee total: the editor only walks
    /// shapes it understands, so this answers "did anything of ours survive
    /// somewhere we could not touch" without needing to understand that shape.
    @Test @MainActor
    func uninstallRefusesWhenTheManagedCommandHidesInAnUnreachableShape() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.hooksConfiguration.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        let managedCommand = "/usr/bin/python3 \"\(paths.script.path)\""

        // A hand-written copy of our command in a group shape the editor
        // deliberately refuses to rewrite: an unrelated event whose handler
        // array mixes objects with something else.
        let data = try Data(contentsOf: paths.hooksConfiguration)
        var root = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var hooks = try #require(root["hooks"] as? [String: Any])
        hooks["SomeOtherEvent"] = [
            ["hooks": [["type": "command", "command": managedCommand], "stray"]]
        ]
        root["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
            .write(to: paths.hooksConfiguration)
        let beforeBytes = try Data(contentsOf: paths.hooksConfiguration)

        var refused = false
        do {
            try await installer.uninstall()
        } catch {
            refused = true
        }

        #expect(refused)
        #expect(try Data(contentsOf: paths.hooksConfiguration) == beforeBytes)
        #expect(FileManager.default.fileExists(atPath: paths.script.path))
    }

    /// Everything outside the six managed definitions survives a round trip.
    @Test @MainActor
    func installAndUninstallPreserveEverythingTheyDoNotManage() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.hooksConfiguration.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Deliberately busy, the way a real user's file is: settings this app
        // knows nothing about, a user handler inside an event this app also
        // manages, an event shape it cannot parse, and unknown keys at every
        // level.
        let existing: [String: Any] = [
            "description": "my own description",
            "permissions": ["allow": ["Bash(ls:*)"]],
            "unknownTopLevel": ["deeply": ["nested": 42]],
            "hooks": [
                "Stop": [[
                    "matcher": "mine",
                    "customGroupKey": "keep me",
                    "hooks": [[
                        "type": "command",
                        "command": "/usr/bin/true",
                        "customHandlerKey": "keep me too"
                    ]]
                ]],
                "UserPromptSubmit": [[
                    "hooks": [["type": "command", "command": "/usr/bin/false"]]
                ]],
                "SomeEventWeCannotParse": "a bare string"
            ]
        ]
        let originalRoot = existing
        try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted])
            .write(to: paths.hooksConfiguration)

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()

        let installedRoot = try #require(
            JSONSerialization.jsonObject(
                with: try Data(contentsOf: paths.hooksConfiguration)
            ) as? [String: Any]
        )
        let installedHooks = try #require(installedRoot["hooks"] as? [String: Any])

        // Untouched settings, including one this app has no concept of.
        #expect(installedRoot["description"] as? String == "my own description")
        #expect(
            (installedRoot["permissions"] as? [String: Any])?["allow"] as? [String]
                == ["Bash(ls:*)"]
        )
        #expect(installedRoot["unknownTopLevel"] as? [String: Any] != nil)
        // An event shape it cannot parse is left exactly as found rather than
        // treated as an error -- this app could never have written there.
        #expect(installedHooks["SomeEventWeCannotParse"] as? String == "a bare string")

        // The user's own handlers survive inside events this app also manages.
        func commands(_ event: String, in hooks: [String: Any]) -> [String] {
            (hooks[event] as? [[String: Any]] ?? []).flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? []).compactMap {
                    $0["command"] as? String
                }
            }
        }
        #expect(commands("Stop", in: installedHooks).contains("/usr/bin/true"))
        #expect(
            commands("UserPromptSubmit", in: installedHooks).contains("/usr/bin/false")
        )
        // And their sibling keys are not rewritten.
        let stopGroups = try #require(installedHooks["Stop"] as? [[String: Any]])
        let userGroup = try #require(
            stopGroups.first { $0["customGroupKey"] as? String == "keep me" }
        )
        #expect(userGroup["matcher"] as? String == "mine")
        let userHandler = try #require(
            (userGroup["hooks"] as? [[String: Any]])?.first
        )
        #expect(userHandler["customHandlerKey"] as? String == "keep me too")

        try await installer.uninstall()

        let finalRoot = try #require(
            JSONSerialization.jsonObject(
                with: try Data(contentsOf: paths.hooksConfiguration)
            ) as? [String: Any]
        )
        let finalHooks = try #require(finalRoot["hooks"] as? [String: Any])

        #expect(finalRoot["description"] as? String == "my own description")
        #expect(finalRoot["unknownTopLevel"] as? [String: Any] != nil)
        #expect(finalHooks["SomeEventWeCannotParse"] as? String == "a bare string")
        #expect(commands("Stop", in: finalHooks) == ["/usr/bin/true"])
        #expect(commands("UserPromptSubmit", in: finalHooks) == ["/usr/bin/false"])
        // Nothing of this app's may remain anywhere in the document.
        let managedCommand = "/usr/bin/python3 \"\(paths.script.path)\""
        #expect(
            !ManagedHooksConfiguration.contains(command: managedCommand, in: finalRoot)
        )
        // The events this app added and then removed are gone entirely rather
        // than left as empty arrays.
        #expect(finalHooks["PreToolUse"] == nil)
        #expect(finalHooks["PermissionRequest"] == nil)
        _ = originalRoot
    }

    /// A description is this app's to write only on a file it created.
    @Test @MainActor
    func descriptionIsStampedOnlyOnAFileThisAppCreated() async throws {
        let created = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: created.supportDirectory.deletingLastPathComponent()
            )
        }
        try await CodexHookInstaller(paths: created).install()
        let createdRoot = try #require(
            JSONSerialization.jsonObject(
                with: try Data(contentsOf: created.hooksConfiguration)
            ) as? [String: Any]
        )
        #expect(createdRoot["description"] as? String != nil)

        let adopted = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: adopted.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: adopted.hooksConfiguration.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"hooks": {}}"#.utf8).write(to: adopted.hooksConfiguration)
        try await CodexHookInstaller(paths: adopted).install()
        let adoptedRoot = try #require(
            JSONSerialization.jsonObject(
                with: try Data(contentsOf: adopted.hooksConfiguration)
            ) as? [String: Any]
        )
        #expect(adoptedRoot["description"] == nil)
    }

    @Test @MainActor
    func hookInstallerMergesExistingConfigurationAndIsIdempotent() async throws {
        let paths = makeTemporaryHookPaths()
        defer { try? FileManager.default.removeItem(at: paths.supportDirectory.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(
            at: paths.hooksConfiguration.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let managedCommand = "/usr/bin/python3 \"\(paths.script.path)\""
        let existing: [String: Any] = [
            "hooks": [
                "Stop": [[
                    "hooks": [[
                        "type": "command",
                        "command": "/usr/bin/true"
                    ], [
                        "type": "command",
                        "command": managedCommand
                    ]]
                ]]
            ]
        ]
        try JSONSerialization.data(
            withJSONObject: existing,
            options: [.prettyPrinted]
        ).write(to: paths.hooksConfiguration)

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        try await installer.install()

        let status = await installer.status(hasObservedEvent: false)
        let data = try Data(contentsOf: paths.hooksConfiguration)
        let root = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let hooks = try #require(root["hooks"] as? [String: Any])
        let stopGroups = try #require(hooks["Stop"] as? [[String: Any]])
        let commands = stopGroups.flatMap { group in
            (group["hooks"] as? [[String: Any]] ?? []).compactMap {
                $0["command"] as? String
            }
        }

        #expect(status == .reviewRequired)
        #expect(commands.contains("/usr/bin/true"))
        #expect(commands.filter { $0.contains("codex_in_notch_hook.py") }.count == 1)
        #expect(hooks.keys.contains("UserPromptSubmit"))
        #expect(hooks.keys.contains("PermissionRequest"))
        #expect(hooks.keys.contains("PreToolUse"))
        #expect(hooks.keys.contains("PostToolUse"))
        #expect(hooks.keys.contains("SessionEnd"))

        // A helper this app did not write, at a path it manages exclusively.
        // repairRequired would NOT deregister it from hooks.json, so Codex would
        // keep executing it until the user noticed. Self-healing is the safer
        // response: the next refresh restores the bundled helper.
        try "#!/usr/bin/python3\nprint('{}')\n".write(
            to: paths.script,
            atomically: true,
            encoding: .utf8
        )
        await installer.invalidateInstallationCache()
        #expect(await installer.status(hasObservedEvent: true) == .active)
        #expect(try await installer.upgradeManagedHookIfNeeded())
        let healedScript = try String(contentsOf: paths.script, encoding: .utf8)
        #expect(healedScript.contains(#"payload.get("tool_use_id")"#))
        await installer.invalidateInstallationCache()
        #expect(await installer.status(hasObservedEvent: true) == .active)

        // With no marker this app never recorded installing anything, so an
        // unaccounted-for helper is flagged instead of overwritten. Both the
        // marker and the legacy settings file count, so both have to go.
        try FileManager.default.removeItem(at: paths.installMarker)
        try? FileManager.default.removeItem(at: paths.legacySettings)
        try "#!/usr/bin/python3\nprint('{}')\n".write(
            to: paths.script,
            atomically: true,
            encoding: .utf8
        )
        await installer.invalidateInstallationCache()
        #expect(await installer.status(hasObservedEvent: true) == .repairRequired)
        try await installer.install()
        await installer.invalidateInstallationCache()
        #expect(await installer.status(hasObservedEvent: true) == .active)

        try await installer.uninstall()
        let uninstalledData = try Data(contentsOf: paths.hooksConfiguration)
        let uninstalledRoot = try #require(
            JSONSerialization.jsonObject(with: uninstalledData) as? [String: Any]
        )
        let uninstalledHooks = try #require(uninstalledRoot["hooks"] as? [String: Any])
        let remainingCommands = (uninstalledHooks["Stop"] as? [[String: Any]] ?? [])
            .flatMap { group in
                (group["hooks"] as? [[String: Any]] ?? []).compactMap {
                    $0["command"] as? String
                }
            }
        #expect(remainingCommands == ["/usr/bin/true"])
    }

    @Test @MainActor
    func hookInstallerRepairsMissingAndAlteredDefinitions() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()

        let installedData = try Data(contentsOf: paths.hooksConfiguration)
        var root = try #require(
            JSONSerialization.jsonObject(with: installedData) as? [String: Any]
        )
        var hooks = try #require(root["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "SessionEnd")
        root["hooks"] = hooks
        try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: paths.hooksConfiguration, options: .atomic)

        await installer.invalidateInstallationCache()
        #expect(await installer.status(hasObservedEvent: true) == .repairRequired)

        try await installer.install()

        await installer.invalidateInstallationCache()
        #expect(await installer.status(hasObservedEvent: false) == .reviewRequired)
        let repairedData = try Data(contentsOf: paths.hooksConfiguration)
        let repairedRoot = try #require(
            JSONSerialization.jsonObject(with: repairedData) as? [String: Any]
        )
        let repairedHooks = try #require(
            repairedRoot["hooks"] as? [String: Any]
        )
        #expect(repairedHooks.keys.contains("SessionEnd"))
        #expect(repairedHooks.keys.contains("UserPromptSubmit"))
        #expect(repairedHooks.keys.contains("PermissionRequest"))
        #expect(repairedHooks.keys.contains("PreToolUse"))
        #expect(repairedHooks.keys.contains("PostToolUse"))
        #expect(repairedHooks.keys.contains("Stop"))

        var alteredRoot = repairedRoot
        var alteredHooks = repairedHooks
        var preToolGroups = try #require(
            alteredHooks["PreToolUse"] as? [[String: Any]]
        )
        let groupIndex = try #require(preToolGroups.indices.first)
        var preToolGroup = preToolGroups[groupIndex]
        preToolGroup["matcher"] = "request_user_input"
        var handlers = try #require(
            preToolGroup["hooks"] as? [[String: Any]]
        )
        let handlerIndex = try #require(handlers.indices.first)
        handlers[handlerIndex]["timeout"] = 99
        preToolGroup["hooks"] = handlers
        preToolGroups[groupIndex] = preToolGroup
        alteredHooks["PreToolUse"] = preToolGroups
        alteredRoot["hooks"] = alteredHooks
        try JSONSerialization.data(
            withJSONObject: alteredRoot,
            options: [.prettyPrinted, .sortedKeys]
        ).write(to: paths.hooksConfiguration, options: .atomic)

        await installer.invalidateInstallationCache()
        #expect(await installer.status(hasObservedEvent: true) == .repairRequired)

        try await installer.install()

        let exactData = try Data(contentsOf: paths.hooksConfiguration)
        let exactRoot = try #require(
            JSONSerialization.jsonObject(with: exactData) as? [String: Any]
        )
        let exactHooks = try #require(exactRoot["hooks"] as? [String: Any])
        let exactGroups = try #require(
            exactHooks["PreToolUse"] as? [[String: Any]]
        )
        let exactGroup = try #require(exactGroups.first)
        let exactHandlers = try #require(
            exactGroup["hooks"] as? [[String: Any]]
        )
        let exactHandler = try #require(exactHandlers.first)

        // PreToolUse is registered catch-all: no tool-name regex may decide
        // whether a wait is observed.
        #expect(exactGroup["matcher"] == nil)
        #expect(exactHandler["timeout"] as? Int == 3)
        await installer.invalidateInstallationCache()
        #expect(await installer.status(hasObservedEvent: false) == .reviewRequired)
    }

    /// Captured from a real Desktop approval on 2026-08-15: asking to run a
    /// shell command produces `PreToolUse(Bash, exec-…)`, then
    /// `PermissionRequest(Bash, tool_use_id: null)` ~30ms later, and nothing
    /// else until the human answers. The approval therefore has to borrow the
    /// id of the call still open for that tool -- which is also what closes it.
    @Test
    func commandApprovalPairsPermissionRequestWithTheOpenToolCall() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        let timestamp = Date().timeIntervalSince1970
        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )

        func write(_ event: [String: Any], _ index: Int) throws {
            try JSONSerialization.data(withJSONObject: event).write(
                to: paths.eventsDirectory.appendingPathComponent("\(index).json")
            )
        }

        try write([
            "received_at": timestamp,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-1",
            "turn_id": "turn-1"
        ], 0)
        try write([
            "received_at": timestamp + 1,
            "hook_event_name": "PreToolUse",
            "session_id": "thread-1",
            "turn_id": "turn-1",
            "tool_name": "Bash",
            "tool_use_id": "exec-1"
        ], 1)
        // Announced but not asked about yet: an open tool call is not a wait.
        var status = await repository.consumeEvents().turns.first?.status
        #expect(status == .running)

        try write([
            "received_at": timestamp + 2,
            "hook_event_name": "PermissionRequest",
            "session_id": "thread-1",
            "turn_id": "turn-1",
            "tool_name": "Bash"
        ], 2)
        status = await repository.consumeEvents().turns.first?.status
        #expect(status == .approvalNeeded)

        try write([
            "received_at": timestamp + 3,
            "hook_event_name": "PostToolUse",
            "session_id": "thread-1",
            "turn_id": "turn-1",
            "tool_name": "Bash",
            "tool_use_id": "exec-1"
        ], 3)
        status = await repository.consumeEvents().turns.first?.status
        #expect(status == .running)

        try write([
            "received_at": timestamp + 4,
            "hook_event_name": "Stop",
            "session_id": "thread-1",
            "turn_id": "turn-1"
        ], 4)
        status = await repository.consumeEvents().turns.first?.status
        #expect(status == .completed)
    }

    /// Captured from a real denial on 2026-08-15: denying the same Bash command
    /// produced *no* event for that call -- 67 seconds of silence and then the
    /// turn's `Stop`. The wait must still end, and here `Stop` is what ends it.
    @Test
    func deniedCommandEndsItsWaitAtTheTurnBoundary() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        let timestamp = Date().timeIntervalSince1970
        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )

        func write(_ event: [String: Any], _ index: Int) throws {
            try JSONSerialization.data(withJSONObject: event).write(
                to: paths.eventsDirectory.appendingPathComponent("\(index).json")
            )
        }

        try write([
            "received_at": timestamp,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-1",
            "turn_id": "turn-1"
        ], 0)
        try write([
            "received_at": timestamp + 1,
            "hook_event_name": "PreToolUse",
            "session_id": "thread-1",
            "turn_id": "turn-1",
            "tool_name": "Bash",
            "tool_use_id": "exec-1"
        ], 1)
        try write([
            "received_at": timestamp + 2,
            "hook_event_name": "PermissionRequest",
            "session_id": "thread-1",
            "turn_id": "turn-1",
            "tool_name": "Bash"
        ], 2)
        var status = await repository.consumeEvents().turns.first?.status
        #expect(status == .approvalNeeded)

        // Denied: `exec-1` is never mentioned again.
        try write([
            "received_at": timestamp + 67,
            "hook_event_name": "Stop",
            "session_id": "thread-1",
            "turn_id": "turn-1"
        ], 3)
        status = await repository.consumeEvents().turns.first?.status
        #expect(status == .completed)
    }

    /// Denying and then letting the agent try something else: the denied call is
    /// never closed, so the next call's activity is what proves the human
    /// answered. Without this the row claims it is still asking for the rest of
    /// the turn.
    @Test
    func denialFollowedByAnotherToolReturnsToRunning() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        let timestamp = Date().timeIntervalSince1970
        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )

        func write(_ event: [String: Any], _ index: Int) throws {
            try JSONSerialization.data(withJSONObject: event).write(
                to: paths.eventsDirectory.appendingPathComponent("\(index).json")
            )
        }

        try write([
            "received_at": timestamp,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-1",
            "turn_id": "turn-1"
        ], 0)
        try write([
            "received_at": timestamp + 1,
            "hook_event_name": "PreToolUse",
            "session_id": "thread-1",
            "turn_id": "turn-1",
            "tool_name": "Bash",
            "tool_use_id": "exec-1"
        ], 1)
        try write([
            "received_at": timestamp + 2,
            "hook_event_name": "PermissionRequest",
            "session_id": "thread-1",
            "turn_id": "turn-1",
            "tool_name": "Bash"
        ], 2)
        var status = await repository.consumeEvents().turns.first?.status
        #expect(status == .approvalNeeded)

        // Denied, and the agent tries a different approach.
        try write([
            "received_at": timestamp + 30,
            "hook_event_name": "PreToolUse",
            "session_id": "thread-1",
            "turn_id": "turn-1",
            "tool_name": "Read",
            "tool_use_id": "read-1"
        ], 3)
        status = await repository.consumeEvents().turns.first?.status
        #expect(status == .running)

        // The new call closing must not resurrect the abandoned approval.
        try write([
            "received_at": timestamp + 31,
            "hook_event_name": "PostToolUse",
            "session_id": "thread-1",
            "turn_id": "turn-1",
            "tool_name": "Read",
            "tool_use_id": "read-1"
        ], 4)
        status = await repository.consumeEvents().turns.first?.status
        #expect(status == .running)
    }

    /// An approval that owns its `tool_use_id` always gets a closing event, so
    /// another tool finishing must not end it early.
    @Test
    func requestPermissionsWaitSurvivesUnrelatedToolActivity() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        let timestamp = Date().timeIntervalSince1970
        let events: [[String: Any]] = [
            [
                "received_at": timestamp,
                "hook_event_name": "UserPromptSubmit",
                "session_id": "thread-1",
                "turn_id": "turn-1"
            ],
            [
                "received_at": timestamp + 1,
                "hook_event_name": "PreToolUse",
                "session_id": "thread-1",
                "turn_id": "turn-1",
                "tool_name": "request_permissions",
                "tool_use_id": "approval-1"
            ],
            [
                "received_at": timestamp + 2,
                "hook_event_name": "PostToolUse",
                "session_id": "thread-1",
                "turn_id": "turn-1",
                "tool_name": "Read",
                "tool_use_id": "read-1"
            ]
        ]
        for (index, event) in events.enumerated() {
            try JSONSerialization.data(withJSONObject: event).write(
                to: paths.eventsDirectory.appendingPathComponent("\(index).json")
            )
        }

        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )
        let status = await repository.consumeEvents().turns.first?.status
        #expect(status == .approvalNeeded)
    }

    /// The pairing is evidence, not a guess: an approval naming a tool other
    /// than the one still open cannot be matched, so it opens no wait.
    @Test
    func permissionRequestForAnotherToolDoesNotOpenAWait() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        let timestamp = Date().timeIntervalSince1970
        let events: [[String: Any]] = [
            [
                "received_at": timestamp,
                "hook_event_name": "UserPromptSubmit",
                "session_id": "thread-1",
                "turn_id": "turn-1"
            ],
            [
                "received_at": timestamp + 1,
                "hook_event_name": "PreToolUse",
                "session_id": "thread-1",
                "turn_id": "turn-1",
                "tool_name": "Bash",
                "tool_use_id": "exec-1"
            ],
            [
                "received_at": timestamp + 2,
                "hook_event_name": "PermissionRequest",
                "session_id": "thread-1",
                "turn_id": "turn-1",
                "tool_name": "WebFetch"
            ]
        ]
        for (index, event) in events.enumerated() {
            try JSONSerialization.data(withJSONObject: event).write(
                to: paths.eventsDirectory.appendingPathComponent("\(index).json")
            )
        }

        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )
        let status = await repository.consumeEvents().turns.first?.status
        #expect(status == .running)
    }

    @Test @MainActor
    func hookReducerTracksTurnLifecycleAndDoesNotPersistPreviewText() async throws {
        let paths = makeTemporaryHookPaths()
        defer { try? FileManager.default.removeItem(at: paths.supportDirectory.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        // The repository binds the socket, so it has to exist before any
        // helper would hand text to it.
        let channel = HookPreviewChannel(socketURL: paths.previewSocket)
        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast,
            previewChannel: channel
        )

        let timestamp = Date().timeIntervalSince1970
        let events: [[String: Any]] = [
            [
                "event_id": "event-prompt",
                "received_at": timestamp,
                "hook_event_name": "UserPromptSubmit",
                "session_id": "thread-1",
                "turn_id": "turn-1"
            ],
            [
                "event_id": "event-permission",
                "received_at": timestamp + 1,
                "hook_event_name": "PermissionRequest",
                "session_id": "thread-1",
                "turn_id": "turn-1"
            ],
            [
                "event_id": "event-post",
                "received_at": timestamp + 2,
                "hook_event_name": "PostToolUse",
                "session_id": "thread-1",
                "turn_id": "turn-1",
                "tool_name": "Bash",
                "tool_use_id": "bash-1"
            ]
        ]

        // Text arrives over the socket, never in the file -- which is the whole
        // point of CR-011. The helper sends before writing its file for exactly
        // this reason: the preview must already be in hand when the file lands.
        sendHookPreview(
            to: paths.previewSocket,
            eventID: "event-prompt",
            prompt: "private prompt"
        )
        try await waitForRetainedPreviews(channel, count: 1)

        for (index, event) in events.enumerated() {
            let data = try JSONSerialization.data(withJSONObject: event)
            try data.write(
                to: paths.eventsDirectory.appendingPathComponent("\(index).json")
            )
        }

        let waitingSnapshot = await repository.consumeEvents()
        #expect(waitingSnapshot.turns.first?.status == .running)

        sendHookPreview(
            to: paths.previewSocket,
            eventID: "event-stop",
            assistantMessage: "private answer"
        )
        try await waitForRetainedPreviews(channel, count: 1)

        let stop = try JSONSerialization.data(withJSONObject: [
            "event_id": "event-stop",
            "received_at": timestamp + 3,
            "hook_event_name": "Stop",
            "session_id": "thread-1",
            "turn_id": "turn-1"
        ])
        try stop.write(
            to: paths.eventsDirectory.appendingPathComponent("3.json")
        )

        let snapshot = await repository.consumeEvents()
        let turn = try #require(snapshot.turns.first)
        let persistedText = try String(contentsOf: paths.state, encoding: .utf8)
        let everythingOnDisk = allFileContents(under: paths.supportDirectory)
        channel.stop()

        // The claim in onboarding and Settings is absolute -- "No prompt or
        // answer is persisted" -- so assert it against every file this app
        // owns, not just the state file.
        #expect(!everythingOnDisk.contains("private prompt"))
        #expect(!everythingOnDisk.contains("private answer"))

        #expect(snapshot.hasObservedEvent)
        #expect(turn.threadID == "thread-1")
        #expect(turn.turnID == "turn-1")
        #expect(turn.sessionStatus == .completed)
        #expect(turn.status == .completed)
        #expect(turn.promptPreview == "private prompt")
        #expect(turn.assistantPreview == "private answer")
        #expect(!persistedText.contains("private prompt"))
        #expect(!persistedText.contains("private answer"))
        #expect(!persistedText.contains("thread-1"))
        #expect(!persistedText.contains("turn-1"))
        #expect(!persistedText.contains("turns"))
        #expect(
            try FileManager.default.contentsOfDirectory(
                at: paths.eventsDirectory,
                includingPropertiesForKeys: nil
            ).isEmpty
        )

        let legacyState: [String: Any] = [
            "turns": [[
                "threadID": "legacy-thread",
                "turnID": "legacy-turn",
                "status": "running",
                "startedAt": timestamp
            ]]
        ]
        try JSONSerialization.data(withJSONObject: legacyState).write(
            to: paths.state,
            options: .atomic
        )

        let restoredRepository = HookEventRepository(paths: paths)
        let restoredSnapshot = await restoredRepository.consumeEvents()
        #expect(restoredSnapshot.hasObservedEvent)
        #expect(restoredSnapshot.turns.isEmpty)
        let migratedText = try String(contentsOf: paths.state, encoding: .utf8)
        #expect(!migratedText.contains("legacy-thread"))
        #expect(!migratedText.contains("turns"))

        await restoredRepository.clearTurnsPreservingObservation()
        let clearedRepository = HookEventRepository(paths: paths)
        let clearedSnapshot = await clearedRepository.consumeEvents()
        #expect(clearedSnapshot.hasObservedEvent)
        #expect(clearedSnapshot.turns.isEmpty)
    }

    @Test @MainActor
    func hookReducerAdoptsAResumedTurnWithoutANewPromptHook() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        func write(_ event: [String: Any], named name: String) throws {
            try JSONSerialization.data(withJSONObject: event).write(
                to: paths.eventsDirectory.appendingPathComponent(name)
            )
        }

        let channel = HookPreviewChannel(socketURL: paths.previewSocket)
        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast,
            previewChannel: channel
        )
        defer { channel.stop() }

        sendHookPreview(
            to: paths.previewSocket,
            eventID: "event-prompt",
            prompt: "continue this task"
        )
        try await waitForRetainedPreviews(channel, count: 1)

        try write([
            "event_id": "event-prompt",
            "received_at": 100.0,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-1",
            "turn_id": "turn-before-pause"
        ], named: "0.json")

        let beforePause = await repository.consumeEvents()
        #expect(beforePause.turns.first?.turnID == "turn-before-pause")
        #expect(beforePause.turns.first?.status == .running)

        // Desktop resumes an interrupted response as a new Turn without
        // emitting another UserPromptSubmit Hook. The first live Hook carrying
        // that new identity must advance the reducer to the resumed Turn.
        try write([
            "received_at": 101.0,
            "hook_event_name": "PostToolUse",
            "session_id": "thread-1",
            "turn_id": "turn-after-resume",
            "tool_name": "Bash",
            "tool_use_id": "tool-after-resume"
        ], named: "1.json")
        let resumed = await repository.consumeEvents()
        let resumedTurn = try #require(resumed.turns.first)
        #expect(resumedTurn.turnID == "turn-after-resume")
        #expect(resumedTurn.status == .running)
        #expect(resumedTurn.retiredTurnIDs.contains("turn-before-pause"))
        #expect(resumedTurn.promptPreview == "continue this task")

        try write([
            "received_at": 102.0,
            "hook_event_name": "Stop",
            "session_id": "thread-1",
            "turn_id": "turn-before-pause"
        ], named: "2.json")
        let staleStop = await repository.consumeEvents()
        #expect(staleStop.turns.first?.turnID == "turn-after-resume")
        #expect(staleStop.turns.first?.status == .running)

        try write([
            "received_at": 103.0,
            "hook_event_name": "Stop",
            "session_id": "thread-1",
            "turn_id": "turn-after-resume"
        ], named: "3.json")
        let completed = await repository.consumeEvents()
        #expect(completed.turns.first?.turnID == "turn-after-resume")
        #expect(completed.turns.first?.status == .completed)
    }

    @Test @MainActor
    func hookReducerCompletesAResumedTurnWhenStopIsItsFirstHook() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        let prompt = try JSONSerialization.data(withJSONObject: [
            "received_at": 100.0,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-1",
            "turn_id": "turn-before-pause"
        ])
        try prompt.write(
            to: paths.eventsDirectory.appendingPathComponent("0.json")
        )

        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )
        #expect(await repository.consumeEvents().turns.first?.status == .running)

        let stop = try JSONSerialization.data(withJSONObject: [
            "received_at": 101.0,
            "hook_event_name": "Stop",
            "session_id": "thread-1",
            "turn_id": "turn-after-resume"
        ])
        try stop.write(
            to: paths.eventsDirectory.appendingPathComponent("1.json")
        )

        let completed = await repository.consumeEvents()
        #expect(completed.turns.first?.turnID == "turn-after-resume")
        #expect(completed.turns.first?.status == .completed)
        #expect(
            completed.turns.first?.retiredTurnIDs.contains("turn-before-pause")
                == true
        )
    }

    @Test @MainActor
    func hookReducerRequiresStableTurnIdentity() async throws {
        let paths = makeTemporaryHookPaths()
        defer { try? FileManager.default.removeItem(at: paths.supportDirectory.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        let invalidEvent = try JSONSerialization.data(withJSONObject: [
            "received_at": 101.0,
            "hook_event_name": "PermissionRequest",
            "session_id": "thread-1"
        ])
        try invalidEvent.write(
            to: paths.eventsDirectory.appendingPathComponent("missing-turn.json")
        )

        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: Date(timeIntervalSince1970: 100)
        )
        let snapshot = await repository.consumeEvents()
        let quarantinedFiles = try FileManager.default.contentsOfDirectory(
            at: paths.eventsDirectory,
            includingPropertiesForKeys: nil
        )

        #expect(!snapshot.hasObservedEvent)
        #expect(snapshot.turns.isEmpty)
        #expect(snapshot.diagnostic?.contains("稳定身份") == true)
        #expect(quarantinedFiles.map(\.pathExtension) == ["invalid"])
    }

    @Test @MainActor
    func hookReducerPairsInputResultsAndIgnoresOldTurnEvents() async throws {
        let paths = makeTemporaryHookPaths()
        defer { try? FileManager.default.removeItem(at: paths.supportDirectory.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        func write(_ event: [String: Any], named name: String) throws {
            try JSONSerialization.data(withJSONObject: event).write(
                to: paths.eventsDirectory.appendingPathComponent(name)
            )
        }

        let firstBatch: [[String: Any]] = [
            [
                "received_at": 100.0,
                "hook_event_name": "UserPromptSubmit",
                "session_id": "thread-1",
                "turn_id": "turn-1"
            ],
            [
                "received_at": 200.0,
                "hook_event_name": "UserPromptSubmit",
                "session_id": "thread-1",
                "turn_id": "turn-2"
            ],
            [
                "received_at": 201.0,
                "hook_event_name": "PreToolUse",
                "session_id": "thread-1",
                "turn_id": "turn-2",
                "tool_name": "request_user_input",
                "tool_use_id": "input-2"
            ],
            [
                "received_at": 202.0,
                "hook_event_name": "PostToolUse",
                "session_id": "thread-1",
                "turn_id": "turn-2",
                "tool_use_id": "unrelated-tool"
            ],
            [
                "received_at": 203.0,
                "hook_event_name": "PermissionRequest",
                "session_id": "thread-1",
                "turn_id": "turn-1"
            ],
            [
                "received_at": 204.0,
                "hook_event_name": "Stop",
                "session_id": "thread-1",
                "turn_id": "turn-1"
            ],
            [
                "received_at": 250.0,
                "hook_event_name": "UserPromptSubmit",
                "session_id": "thread-1",
                "turn_id": "turn-1"
            ]
        ]
        for (index, event) in firstBatch.enumerated() {
            try write(event, named: "\(index).json")
        }

        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )
        let waiting = await repository.consumeEvents()
        #expect(waiting.turns.first?.turnID == "turn-2")
        #expect(waiting.turns.first?.status == .inputNeeded)

        try write([
            "received_at": 251.0,
            "hook_event_name": "PostToolUse",
            "session_id": "thread-1",
            "turn_id": "turn-2",
            "tool_use_id": "input-2"
        ], named: "7.json")
        let resumed = await repository.consumeEvents()
        #expect(resumed.turns.first?.status == .running)

        try write([
            "received_at": 252.0,
            "hook_event_name": "PermissionRequest",
            "session_id": "thread-1",
            "turn_id": "turn-2"
        ], named: "8.json")
        try write([
            "received_at": 253.0,
            "hook_event_name": "PostToolUse",
            "session_id": "thread-1",
            "turn_id": "turn-2",
            "tool_use_id": "bash-2"
        ], named: "9.json")
        let permissionRequest = await repository.consumeEvents()
        #expect(permissionRequest.turns.first?.status == .running)
    }

    @Test @MainActor
    func startupBacklogDoesNotRestoreAnyTurn() async throws {
        let paths = makeTemporaryHookPaths()
        defer { try? FileManager.default.removeItem(at: paths.supportDirectory.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        let backlog: [[String: Any]] = [
            [
                "received_at": 90.0,
                "hook_event_name": "UserPromptSubmit",
                "session_id": "thread-1",
                "turn_id": "turn-1"
            ],
            [
                "received_at": 91.0,
                "hook_event_name": "PermissionRequest",
                "session_id": "thread-1",
                "turn_id": "turn-1"
            ],
            [
                "received_at": 92.0,
                "hook_event_name": "PreToolUse",
                "session_id": "thread-1",
                "turn_id": "turn-1",
                "tool_name": "request_user_input",
                "tool_use_id": "input-1"
            ],
            [
                "received_at": 93.0,
                "hook_event_name": "Stop",
                "session_id": "thread-1",
                "turn_id": "turn-1"
            ],
            [
                "received_at": 94.0,
                "hook_event_name": "SessionEnd",
                "session_id": "thread-1"
            ]
        ]
        for (index, event) in backlog.enumerated() {
            let data = try JSONSerialization.data(withJSONObject: event)
            try data.write(
                to: paths.eventsDirectory.appendingPathComponent("\(index).json")
            )
        }

        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: Date(timeIntervalSince1970: 100)
        )
        let historical = await repository.consumeEvents()
        #expect(historical.hasObservedEvent)
        #expect(!historical.hasObservedLiveEvent)
        #expect(!historical.didConsumeEvents)
        #expect(historical.turns.isEmpty)

        let livePrompt = try JSONSerialization.data(withJSONObject: [
            "received_at": 101.0,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-1",
            "turn_id": "turn-2"
        ])
        try livePrompt.write(
            to: paths.eventsDirectory.appendingPathComponent("3.json")
        )
        let live = await repository.consumeEvents()
        #expect(live.hasObservedLiveEvent)
        #expect(live.didConsumeEvents)
        #expect(live.turns.first?.turnID == "turn-2")
        #expect(live.turns.first?.status == .running)
    }

    @Test @MainActor
    func installedHookScriptWritesAConsumablePrivateEvent() async throws {
        let paths = makeTemporaryHookPaths()
        defer { try? FileManager.default.removeItem(at: paths.supportDirectory.deletingLastPathComponent()) }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()

        // Listening before the helper runs, the way the app does: the helper
        // sends its preview and then writes the file that wakes the reducer.
        let channel = HookPreviewChannel(socketURL: paths.previewSocket)
        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast,
            previewChannel: channel
        )

        let input = Pipe()
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [paths.script.path]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        let payload = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "UserPromptSubmit",
            "session_id": "thread-script",
            "turn_id": "turn-script",
            "cwd": "/tmp",
            "reason": "private reason",
            "tool_use_id": "tool-script",
            "prompt": "script preview"
        ])
        try input.fileHandleForWriting.write(contentsOf: payload)
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let eventURL = try #require(
            FileManager.default.contentsOfDirectory(
                at: paths.eventsDirectory,
                includingPropertiesForKeys: nil
            ).first
        )
        let rawEventText = try String(contentsOf: eventURL, encoding: .utf8)
        let rawEvent = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: eventURL)
            ) as? [String: Any]
        )
        let snapshot = await repository.consumeEvents()
        let everythingOnDisk = allFileContents(under: paths.supportDirectory)
        channel.stop()

        #expect(process.terminationStatus == 0)
        #expect(String(data: stdout, encoding: .utf8) == "{}\n")
        #expect(rawEvent["tool_use_id"] as? String == "tool-script")
        #expect(rawEvent["cwd"] == nil)
        #expect(rawEvent["reason"] == nil)
        #expect(snapshot.turns.first?.threadID == "thread-script")

        // The real helper handed the preview over the socket, so the reducer
        // has it and no file this app owns ever contained it.
        #expect(snapshot.turns.first?.promptPreview == "script preview")
        #expect(rawEvent["prompt"] == nil)
        #expect(!rawEventText.contains("script preview"))
        #expect(!everythingOnDisk.contains("script preview"))
    }

    /// The privacy switch, at the boundary where it used to fail open.
    ///
    /// It was a file the helper read, written through an unheld `Task` with the
    /// error swallowed: two quick toggles could land out of order, and a single
    /// failed write left the UI showing "off" while text kept being collected
    /// (CR-012). It is now one in-memory flag, so "off" means the next message
    /// is dropped on arrival, and the last caller always wins.
    @Test
    func disablingPreviewsDropsTextOnArrivalAndLastWriteWins() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        let channel = HookPreviewChannel(socketURL: paths.previewSocket)
        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast,
            previewChannel: channel
        )
        defer { channel.stop() }

        repository.setContentPreviewsEnabled(false)
        sendHookPreview(
            to: paths.previewSocket,
            eventID: "event-off",
            prompt: "must not be retained"
        )
        // Nothing to wait for on the happy path, so give the reader a real
        // chance to do the wrong thing before asserting that it did not.
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(channel.retainedPreviewCount == 0)

        // Rapid toggling: the last call is the state, with no ordering window.
        repository.setContentPreviewsEnabled(true)
        repository.setContentPreviewsEnabled(false)
        repository.setContentPreviewsEnabled(true)
        sendHookPreview(
            to: paths.previewSocket,
            eventID: "event-on",
            prompt: "may be retained"
        )
        try await waitForRetainedPreviews(channel, count: 1)

        // Turning it off also drops what was already collected.
        repository.setContentPreviewsEnabled(false)
        #expect(channel.retainedPreviewCount == 0)

        let everythingOnDisk = allFileContents(under: paths.supportDirectory)
        #expect(!everythingOnDisk.contains("must not be retained"))
        #expect(!everythingOnDisk.contains("may be retained"))
    }

    /// Unclaimed previews cannot grow without bound.
    ///
    /// They pile up only when the file that would claim them never arrives -- a
    /// quarantined event, or a helper that sent text and then failed to write.
    @Test
    func unclaimedPreviewsAreBoundedByTheRetentionCap() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.supportDirectory,
            withIntermediateDirectories: true
        )

        let channel = HookPreviewChannel(
            socketURL: paths.previewSocket,
            maximumRetainedPreviews: 4
        )
        #expect(channel.start())
        defer { channel.stop() }

        for index in 0 ..< 12 {
            sendHookPreview(
                to: paths.previewSocket,
                eventID: "event-\(index)",
                prompt: "prompt \(index)"
            )
        }
        try await waitForRetainedPreviews(channel, count: 4)
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(channel.retainedPreviewCount == 4)
        // The cap evicts oldest-first, so the newest survivor is still there
        // and the oldest is long gone.
        #expect(channel.claimPreview(forEventID: "event-11")?.prompt == "prompt 11")
        #expect(channel.claimPreview(forEventID: "event-0") == nil)
        // A claim consumes, so the same text can never be served twice.
        #expect(channel.claimPreview(forEventID: "event-11") == nil)
    }

    /// A store holding nothing, so a timing assertion starts from a clock with
    /// no sleepers on it and a session list the test controls entirely.
    @MainActor
    private func makeIdleStore(clock: TestClock) -> MonitorStore {
        MonitorStore(
            displays: [
                makeDisplay(id: "notched", ordinal: 1, menuBarHeight: 46, hasNotch: true)
            ],
            initialSnapshot: makeSessionSnapshot([]),
            clock: clock
        )
    }

    private func makeSession(
        threadID: String = "thread",
        status: SessionStatus,
        startedAt: Date?
    ) -> MonitoredSession {
        MonitoredSession(
            threadID: threadID,
            turnID: "turn-\(threadID)",
            projectName: "Chats",
            title: "Timed turn",
            preview: nil,
            status: status,
            startedAt: startedAt
        )
    }

    private func makeSessionSnapshot(
        _ sessions: [MonitoredSession]
    ) -> AgentSnapshot {
        AgentSnapshot(
            availability: .ready,
            sessions: sessions,
            quota: .unavailable,
            diagnostic: nil
        )
    }

    private func makeDisplay(
        id: String,
        ordinal: Int,
        menuBarHeight: CGFloat,
        hasNotch: Bool
    ) -> DisplayOption {
        let frame = NSRect(x: CGFloat(ordinal - 1) * 1_920, y: 0, width: 1_920, height: 1_080)
        let auxiliaryHeight = hasNotch ? menuBarHeight : 0
        let auxiliaryWidth = hasNotch ? (frame.width - 200) / 2 : 0

        return DisplayOption(
            id: id,
            ordinal: ordinal,
            name: "Display \(ordinal)",
            frame: frame,
            visibleFrame: NSRect(
                x: frame.minX,
                y: frame.minY,
                width: frame.width,
                height: frame.height - menuBarHeight
            ),
            safeAreaInsets: NSEdgeInsets(
                top: auxiliaryHeight,
                left: 0,
                bottom: 0,
                right: 0
            ),
            auxiliaryTopLeftArea: hasNotch
                ? NSRect(
                    x: frame.minX,
                    y: frame.maxY - menuBarHeight,
                    width: auxiliaryWidth,
                    height: menuBarHeight
                )
                : nil,
            auxiliaryTopRightArea: hasNotch
                ? NSRect(
                    x: frame.maxX - auxiliaryWidth,
                    y: frame.maxY - menuBarHeight,
                    width: auxiliaryWidth,
                    height: menuBarHeight
                )
                : nil,
            fallbackMenuBarHeight: 22
        )
    }

    /// Whether a change stream delivers at least one signal in time.
    ///
    /// Bounded so a regression reports as a failure rather than hanging the
    /// suite. `AsyncStream`'s build closure runs during `events()`, so the
    /// continuation is registered before the caller mutates anything and a
    /// signal that arrives first is buffered rather than lost.
    private func receivesChange(
        _ stream: AsyncStream<Void>,
        within seconds: Double = 3
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in stream { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(
                    nanoseconds: UInt64(seconds * 1_000_000_000)
                )
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private func makeTemporaryWatchRoot() -> URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("cin-w-\(UUID().uuidString.prefix(8))")
    }

    /// Hands preview text to a listening ``HookPreviewChannel``.
    ///
    /// Speaks the same wire format the installed Python helper does -- one line
    /// of JSON on a Unix socket -- so these tests exercise the real path rather
    /// than a Swift-side shortcut around it.
    @discardableResult
    private func sendHookPreview(
        to socketURL: URL,
        eventID: String,
        prompt: String? = nil,
        assistantMessage: String? = nil
    ) -> Bool {
        var payload: [String: Any] = ["event_id": eventID]
        if let prompt { payload["prompt"] = prompt }
        if let assistantMessage { payload["last_assistant_message"] = assistantMessage }
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else {
            return false
        }
        data.append(0x0A)

        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketURL.path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            return false
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return false }

        return data.withUnsafeBytes { buffer in
            write(descriptor, buffer.baseAddress, buffer.count)
        } == data.count
    }

    /// Waits for the channel's background reader to take delivery.
    private func waitForRetainedPreviews(
        _ channel: HookPreviewChannel,
        count: Int
    ) async throws {
        for _ in 0 ..< 200 {
            if channel.retainedPreviewCount >= count { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        Issue.record("preview channel never received \(count) message(s)")
    }

    /// Every regular file under a directory, for "is the text anywhere" checks.
    private func allFileContents(under directory: URL) -> String {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return ""
        }
        var combined = ""
        for case let url as URL in enumerator {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                combined += text
            }
        }
        return combined
    }

    /// Registering a hook whose events are then thrown away is not possible.
    ///
    /// The installer's list and the reducer's list used to be two hand-written
    /// literals. Nothing connected them, and a drift between them fails in the
    /// worst available way: the hook installs, fires, and every event it
    /// produces is quarantined as unrecognised — which reads as a corrupt file
    /// rather than a missing case.
    @Test @MainActor
    func everyRegisteredHookDefinitionMapsToASignalForItsAgent() {
        let vocabulary = CodexHookVocabulary()
        #expect(vocabulary.agent == .codex)
        #expect(!vocabulary.managedDefinitions.isEmpty)

        for definition in vocabulary.managedDefinitions {
            #expect(
                vocabulary.signal(forEvent: definition.event, toolName: nil) != nil,
                "\(definition.event) is registered but produces no signal"
            )
        }

        // The tool-name refinements are part of the same table, so a rename of
        // either tool has to fail here rather than silently downgrade a wait
        // into an ordinary tool call.
        #expect(
            vocabulary.signal(forEvent: "PreToolUse", toolName: "request_user_input")
                == .inputWaitOpened
        )
        #expect(
            vocabulary.signal(forEvent: "PreToolUse", toolName: "request_permissions")
                == .approvalWaitOpened
        )
        #expect(vocabulary.signal(forEvent: "PreToolUse", toolName: "shell") == .toolCallOpened)
        #expect(vocabulary.signal(forEvent: "NotOurs", toolName: nil) == nil)
    }

    /// A recognised event with nothing to say is consumed, not quarantined.
    ///
    /// Quarantine means "we did not understand this file" and raises a
    /// diagnostic. `SessionEnd` has always been understood and has always been
    /// a no-op, and the vocabulary has to keep those two answers apart — fold
    /// them together and every ordinary event a product emits and this app
    /// ignores gets reported as corruption.
    @Test @MainActor
    func aRecognisedButInertEventIsConsumedRatherThanQuarantined() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        func write(_ event: [String: Any], named name: String) throws {
            try JSONSerialization.data(withJSONObject: event).write(
                to: paths.eventsDirectory.appendingPathComponent(name)
            )
        }

        // Recognised, and deliberately without effect. It carries no turn id,
        // so it also proves the inert answer lands before the identity gate.
        try write([
            "received_at": 100.0,
            "hook_event_name": "SessionEnd",
            "session_id": "thread-1"
        ], named: "inert.json")
        try write([
            "received_at": 101.0,
            "hook_event_name": "SomeEventWeDoNotKnow",
            "session_id": "thread-1",
            "turn_id": "turn-1"
        ], named: "unknown.json")

        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )
        let snapshot = await repository.consumeEvents()
        #expect(snapshot.turns.isEmpty)

        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(
                atPath: paths.eventsDirectory.appendingPathComponent(name).path
            )
        }

        #expect(!exists("inert.json"))
        #expect(!exists("inert.invalid"))
        #expect(!exists("unknown.json"))
        #expect(exists("unknown.invalid"))
    }

    /// Each row goes to its own product's navigator.
    @Test @MainActor
    func theRouterDispatchesByAgent() async throws {
        let codex = AgentNavigatorStub()
        let claude = AgentNavigatorStub(
            outcome: .raisedApplication(host: "Claude Desktop")
        )
        let router = AgentNavigationRouter([.codex: codex, .claudeCode: claude])

        let codexOutcome = try await router.open(
            makeSession(agent: .codex, threadID: "codex-thread")
        )
        let claudeOutcome = try await router.open(
            makeSession(agent: .claudeCode, threadID: "claude-session")
        )

        #expect(codexOutcome == .openedThread(host: "Codex Desktop"))
        #expect(claudeOutcome == .raisedApplication(host: "Claude Desktop"))
        #expect(codex.requestedAgents == [.codex])
        #expect(claude.requestedAgents == [.claudeCode])
        #expect(codex.requestedThreadIDs == ["codex-thread"])

        // A product with no navigator registered fails as itself rather than
        // being quietly handed to whoever is first in the table.
        let onlyCodex = AgentNavigationRouter([.codex: codex])
        await #expect(throws: AgentNavigationError.noNavigator(.claudeCode)) {
            try await onlyCodex.open(makeSession(agent: .claudeCode, threadID: "x"))
        }
    }

    /// The sentence after a click says what was actually achieved.
    ///
    /// A Claude Code row draws no mark for the fact that it cannot be reopened
    /// exactly — one mark per row, and the timer has it — so the message is the
    /// only place the difference can be told. Reporting "已在 Codex Desktop 中
    /// 打开" for a row that merely raised an app would be a lie in the one
    /// place left to tell the truth.
    @Test @MainActor
    func anImpreciseTargetReportsWhatItActuallyOpened() async {
        let session = makeSession(agent: .claudeCode, threadID: "cc")
        let store = MonitorStore(
            navigator: AgentNavigationRouter([
                .claudeCode: AgentNavigatorStub(
                    outcome: .raisedApplication(host: "Claude Desktop")
                )
            ])
        )

        #expect(await store.openAndWait(session))
        #expect(store.lastIntegrationMessage.contains("已唤起 Claude Desktop"))
        #expect(store.lastIntegrationMessage.contains("无法定位到具体会话"))
        #expect(!store.lastIntegrationMessage.contains("Codex"))
    }

    /// Exact navigation stays a Codex requirement, and only a Codex one.
    ///
    /// ADR 0004 makes returning to the exact thread a release gate, worded
    /// unconditionally. Claude Code has no supported way to focus an existing
    /// session at all, so applying that gate to both products would block a
    /// product on a capability that does not exist.
    @Test @MainActor
    func exactNavigationRemainsARequirementForCodexOnly() async throws {
        let codexOutcome = try await AgentNavigationRouter([
            .codex: AgentNavigatorStub()
        ]).open(makeSession(agent: .codex, threadID: "t"))
        #expect(codexOutcome == .openedThread(host: "Codex Desktop"))

        let claudeOutcome = try await AgentNavigationRouter([
            .claudeCode: AgentNavigatorStub(
                outcome: .focusedTerminal(host: "iTerm2")
            )
        ]).open(makeSession(agent: .claudeCode, threadID: "t"))
        #expect(claudeOutcome != .openedThread(host: "Codex Desktop"))
        #expect(
            claudeOutcome.message(forTitle: "Task")
                == "已聚焦 iTerm2：Task"
        )
    }

    private func makeSession(
        agent: AgentKind,
        threadID: String,
        status: SessionStatus = .completed
    ) -> MonitoredSession {
        MonitoredSession(
            agent: agent,
            threadID: threadID,
            turnID: "turn",
            projectName: "codex-in-notch",
            title: "Open this chat",
            preview: nil,
            status: status,
            startedAt: nil
        )
    }

    private func makeAgentSnapshot(
        _ agent: AgentKind,
        availability: MonitorAvailability = .ready,
        sessions: [MonitoredSession] = [],
        diagnostic: String? = nil
    ) -> AgentSnapshot {
        AgentSnapshot(
            agent: agent,
            availability: availability,
            sessions: sessions,
            quota: .unavailable,
            diagnostic: diagnostic
        )
    }

    private func makeTemporaryHookPaths() -> HookIntegrationPaths {
        // Deliberately short. The preview socket lives inside this directory,
        // and a Unix domain socket path may not exceed 104 bytes -- the system
        // temporary directory plus a full UUID spends 135 of them, so binding
        // would fail in tests for a reason that has nothing to do with the
        // code under test.
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("cin-\(UUID().uuidString.prefix(8))")
        return HookIntegrationPaths(
            supportDirectory: root.appendingPathComponent("AS"),
            hooksConfiguration: root.appendingPathComponent(".codex/hooks.json")
        )
    }

    private func waitForThreadReads(
        _ client: CodexAppServerStub,
        atLeast expectedCount: Int
    ) async throws {
        for _ in 0..<200 {
            if await client.requestCount(method: "thread/read") >= expectedCount {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        Issue.record("Expected at least \(expectedCount) thread/read requests")
    }

    private func waitForThreadListRequests(
        _ client: CodexAppServerStub,
        atLeast expectedCount: Int,
        completed: Bool = false
    ) async throws {
        for _ in 0..<200 {
            let count = completed
                ? await client.completedThreadListRequestCount()
                : await client.requestCount(method: "thread/list")
            if count >= expectedCount {
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        Issue.record(
            "Expected at least \(expectedCount) \(completed ? "completed " : "")thread/list requests"
        )
    }

    private var legacyManagedHookScript: String {
        #"""
#!/usr/bin/python3
import json
import os
import sys
import time
import uuid

SUPPORT = os.path.dirname(os.path.abspath(__file__))
EVENTS = os.path.join(SUPPORT, "events")
SETTINGS = os.path.join(SUPPORT, "hook-settings.json")

def previews_enabled():
    try:
        with open(SETTINGS, "r", encoding="utf-8") as handle:
            return bool(json.load(handle).get("showsContentPreviews", True))
    except Exception:
        return False

try:
    payload = json.load(sys.stdin)
    event = {
        "event_id": str(uuid.uuid4()),
        "received_at": time.time(),
        "hook_event_name": payload.get("hook_event_name"),
        "session_id": payload.get("session_id"),
        "turn_id": payload.get("turn_id"),
        "cwd": payload.get("cwd"),
        "tool_name": payload.get("tool_name"),
        "reason": payload.get("reason"),
    }
    if previews_enabled():
        prompt = payload.get("prompt")
        assistant = payload.get("last_assistant_message")
        if isinstance(prompt, str):
            event["prompt"] = prompt[:240]
        if isinstance(assistant, str):
            event["last_assistant_message"] = assistant[:240]

    os.makedirs(EVENTS, mode=0o700, exist_ok=True)
    filename = "%020d-%s.json" % (time.time_ns(), event["event_id"])
    target = os.path.join(EVENTS, filename)
    temporary = target + ".tmp"
    with open(temporary, "x", encoding="utf-8") as handle:
        os.chmod(temporary, 0o600)
        json.dump(event, handle, separators=(",", ":"))
    os.replace(temporary, target)
except Exception:
    pass

# Stop hooks require JSON on stdout. An empty object is a no-op for every
# configured event and never changes Codex behavior.
print("{}")
"""#
    }
}

/// A service whose deadline is permanently overdue, however often it is asked.
///
/// This is the shape every real instance of the bug took: a deadline derived
/// from state that the refresh it triggers does not update.
private actor StuckDeadlineMonitoringStub: AgentMonitoring {
    nonisolated let agent = AgentKind.codex
    nonisolated let stateChangeEvents = AsyncStream<Void> { $0.finish() }

    private let deadline: Date
    private var snapshots = 0

    init(deadline: Date) {
        self.deadline = deadline
    }

    func nextRefreshDeadline() async -> Date? { deadline }

    func fetchSnapshot(showsContentPreviews: Bool) async -> AgentSnapshot {
        snapshots += 1
        return AgentSnapshot(
            availability: .ready,
            sessions: [],
            quota: .unavailable,
            diagnostic: nil
        )
    }

    func snapshotCount() -> Int { snapshots }

    func hookSetupStatus() async -> HookSetupStatus { .reviewRequired }
    func installHooks() async throws {}
    func removeHooks() async throws {}
    func clearSessions() async {}
    nonisolated func setContentPreviewsEnabled(_ isEnabled: Bool) {}
    func discardCollectedPreviews() async {}
    func disconnect() async {}
}

/// A service whose snapshot can be held open, so a refresh can be observed
/// while it is genuinely in flight.
private actor GatedMonitoringStub: AgentMonitoring {
    nonisolated let agent = AgentKind.codex
    nonisolated let stateChangeEvents = AsyncStream<Void> { $0.finish() }

    private var observedSnapshots = 0
    private var status: HookSetupStatus = .reviewRequired
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var holdsSnapshots = false
    private var installRequests = 0
    private var removeRequests = 0
    private var isApplyingIntegrationChange = false
    private(set) var observedOverlappingIntegrationChange = false

    func nextRefreshDeadline() async -> Date? { nil }

    func fetchSnapshot(showsContentPreviews: Bool) async -> AgentSnapshot {
        observedSnapshots += 1
        if holdsSnapshots {
            await withCheckedContinuation { waiters.append($0) }
        }
        return AgentSnapshot(
            availability: .ready,
            sessions: [],
            quota: .unavailable,
            diagnostic: nil,
            setupStatus: status
        )
    }

    func hookSetupStatus() async -> HookSetupStatus { status }

    func installHooks() async throws {
        try await applyIntegrationChange {
            installRequests += 1
            status = .reviewRequired
        }
    }

    func removeHooks() async throws {
        try await applyIntegrationChange {
            removeRequests += 1
            status = .notInstalled
        }
    }

    /// Records whether two integration changes were ever in flight together.
    private func applyIntegrationChange(
        _ body: () -> Void
    ) async throws {
        if isApplyingIntegrationChange {
            observedOverlappingIntegrationChange = true
        }
        isApplyingIntegrationChange = true
        // A real install touches the disk; yielding here gives an unserialised
        // caller every chance to interleave.
        await Task.yield()
        body()
        isApplyingIntegrationChange = false
    }

    func clearSessions() async {}
    nonisolated func setContentPreviewsEnabled(_ isEnabled: Bool) {}
    func discardCollectedPreviews() async {}
    func disconnect() async {}

    func setStatus(_ status: HookSetupStatus) { self.status = status }
    func setHoldsSnapshots(_ holds: Bool) { holdsSnapshots = holds }
    func snapshotCount() -> Int { observedSnapshots }
    func installCount() -> Int { installRequests }
    func removeCount() -> Int { removeRequests }

    func releaseHeldSnapshots() {
        let held = waiters
        waiters.removeAll()
        held.forEach { $0.resume() }
    }
}

private actor IntegrationMonitoringStub: AgentMonitoring {
    nonisolated let agent = AgentKind.codex
    nonisolated let stateChangeEvents = AsyncStream<Void> { $0.finish() }

    // Nothing to schedule: the stub's output never changes on its own.
    func nextRefreshDeadline() async -> Date? { nil }

    private var setupStatus: HookSetupStatus = .notInstalled
    private var installRequests = 0
    private var removeRequests = 0

    func fetchSnapshot(showsContentPreviews: Bool) async -> AgentSnapshot {
        AgentSnapshot(
            availability: setupStatus.isIntegrationEnabled
                ? .connecting
                : .setupRequired,
            sessions: [],
            quota: .unavailable,
            diagnostic: nil
        )
    }

    func hookSetupStatus() async -> HookSetupStatus {
        setupStatus
    }

    func installHooks() async throws {
        installRequests += 1
        setupStatus = .reviewRequired
    }

    func removeHooks() async throws {
        removeRequests += 1
        setupStatus = .notInstalled
    }

    func clearSessions() async {}

    nonisolated func setContentPreviewsEnabled(_ isEnabled: Bool) {}

    func discardCollectedPreviews() async {}

    func disconnect() async {}

    func installCount() -> Int {
        installRequests
    }

    func removeCount() -> Int {
        removeRequests
    }
}

private actor DesktopUnreadStateStub: DesktopUnreadStateProviding {
    private var value: DesktopUnreadStateSnapshot

    init(_ value: DesktopUnreadStateSnapshot) {
        self.value = value
    }

    func snapshot() async -> DesktopUnreadStateSnapshot {
        value
    }

    nonisolated func changeEvents() -> AsyncStream<Void> {
        AsyncStream { _ in }
    }

    func setSnapshot(_ snapshot: DesktopUnreadStateSnapshot) {
        value = snapshot
    }
}

private actor NavigationTargetCheckerStub: CodexNavigationTargetChecking {
    private let isNavigable: Bool
    private var requests: [String] = []

    init(isNavigable: Bool) {
        self.isNavigable = isNavigable
    }

    func isThreadNavigable(_ threadID: String) async throws -> Bool {
        requests.append(threadID)
        return isNavigable
    }

    func requestedThreadIDs() -> [String] {
        requests
    }
}

private actor CodexAppServerStub: CodexAppServerCommunicating {
    private let listedThreads: [JSONValue]
    private let connectResult: Result<Void, CodexAppServerError>
    private let threadListError: CodexAppServerError?
    private var threadListDelayNanoseconds: UInt64
    private var threadReadDelayNanoseconds: UInt64 = 0
    private var loadedListResults: [Result<JSONValue, CodexAppServerError>]
    private let supportsThreadRead: Bool
    private var methods: [String] = []
    private var threadReadParams: [JSONValue] = []
    private var completedThreadListRequests = 0
    private var disconnects = 0

    init(
        listedThreads: [JSONValue],
        loadedListResults: [Result<JSONValue, CodexAppServerError>],
        threadListDelayNanoseconds: UInt64 = 0,
        connectResult: Result<Void, CodexAppServerError> = .success(()),
        threadListError: CodexAppServerError? = nil,
        supportsThreadRead: Bool = true
    ) {
        self.listedThreads = listedThreads
        self.connectResult = connectResult
        self.threadListError = threadListError
        self.loadedListResults = loadedListResults
        self.threadListDelayNanoseconds = threadListDelayNanoseconds
        self.supportsThreadRead = supportsThreadRead
    }

    func connect() async throws {
        try connectResult.get()
    }

    func request(
        method: String,
        params: JSONValue?,
        timeoutNanoseconds: UInt64?
    ) async throws -> JSONValue {
        methods.append(method)
        switch method {
        case "thread/list":
            if let threadListError {
                throw threadListError
            }
            if threadListDelayNanoseconds > 0 {
                try await Task.sleep(
                    nanoseconds: threadListDelayNanoseconds
                )
            }
            completedThreadListRequests += 1
            return .object([
                "data": .array(listedThreads),
                "nextCursor": .null
            ])
        case "thread/read":
            threadReadParams.append(params ?? .null)
            guard supportsThreadRead else {
                throw CodexAppServerError.remote(
                    code: -32601,
                    message: "Method not found: thread/read"
                )
            }
            // The real server only populates `turns` when includeTurns is true,
            // so the stub mirrors that: a metadata read never carries turns.
            let requestedID = params?["threadId"]?.stringValue
            guard let thread = listedThreads.first(
                where: { $0["id"]?.stringValue == requestedID }
            ) else {
                throw CodexAppServerError.remote(
                    code: -32602,
                    message: "Unknown thread"
                )
            }
            if threadReadDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: threadReadDelayNanoseconds)
            }
            var metadata = thread.objectValue ?? [:]
            if params?["includeTurns"]?.boolValue != true {
                metadata["turns"] = .array([])
            }
            return .object(["thread": .object(metadata)])
        case "thread/loaded/list":
            guard !loadedListResults.isEmpty else {
                throw CodexAppServerError.protocolViolation(
                    "unexpected thread/loaded/list request"
                )
            }
            return try loadedListResults.removeFirst().get()
        case "account/read":
            return .object([
                "account": .object([
                    "type": .string("chatgpt"),
                    "chatgptAccountId": .string("test-account")
                ])
            ])
        case "account/rateLimits/read":
            return .object([
                "rateLimits": .object([
                    "primary": .object([
                        "usedPercent": .number(30)
                    ])
                ])
            ])
        case "account/usage/read":
            return .object([
                "summary": .object([:]),
                "dailyUsageBuckets": .array([])
            ])
        default:
            throw CodexAppServerError.remote(
                code: -32601,
                message: "Unexpected method: \(method)"
            )
        }
    }

    func disconnect() async {
        disconnects += 1
    }

    func requestedMethods() -> [String] {
        methods
    }

    func requestCount(method: String) -> Int {
        methods.filter { $0 == method }.count
    }

    func recordedThreadReadParams() -> [JSONValue] {
        threadReadParams
    }

    func completedThreadListRequestCount() -> Int {
        completedThreadListRequests
    }

    func setThreadListDelayNanoseconds(_ delay: UInt64) {
        threadListDelayNanoseconds = delay
    }

    func setThreadReadDelayNanoseconds(_ delay: UInt64) {
        threadReadDelayNanoseconds = delay
    }

    func disconnectCount() -> Int {
        disconnects
    }
}

private actor RecordingAppServerClient: CodexAppServerCommunicating {
    private let base: CodexAppServerClient
    private var methods: [String] = []

    init(base: CodexAppServerClient) {
        self.base = base
    }

    func connect() async throws {
        try await base.connect()
    }

    func request(
        method: String,
        params: JSONValue?,
        timeoutNanoseconds: UInt64?
    ) async throws -> JSONValue {
        methods.append(method)
        return try await base.request(
            method: method,
            params: params,
            timeoutNanoseconds: timeoutNanoseconds
        )
    }

    func disconnect() async {
        await base.disconnect()
    }

    func requestedMethods() -> [String] {
        methods
    }

    func requestCount(method: String) -> Int {
        methods.filter { $0 == method }.count
    }
}

@MainActor
private final class CodexWorkspaceStub: CodexWorkspaceOpening {
    let applicationURL: URL?
    private(set) var requestedBundleIdentifiers: [String] = []
    private(set) var openedURL: URL?
    private(set) var openedApplicationURL: URL?

    init(applicationURL: URL?) {
        self.applicationURL = applicationURL
    }

    func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        requestedBundleIdentifiers.append(bundleIdentifier)
        return applicationURL
    }

    func open(_ url: URL, withApplicationAt applicationURL: URL) async throws {
        openedURL = url
        openedApplicationURL = applicationURL
    }
}

@MainActor
private final class AgentNavigatorStub: AgentNavigating {
    private let error: (any Error)?
    private let outcome: NavigationOutcome
    private(set) var requestedThreadIDs: [String] = []
    private(set) var requestedAgents: [AgentKind] = []

    init(
        error: (any Error)? = nil,
        outcome: NavigationOutcome = .openedThread(host: "Codex Desktop")
    ) {
        self.error = error
        self.outcome = outcome
    }

    @discardableResult
    func open(_ session: MonitoredSession) async throws -> NavigationOutcome {
        requestedThreadIDs.append(session.threadID)
        requestedAgents.append(session.agent)
        if let error {
            throw error
        }
        return outcome
    }
}

extension CodexInNotchTests {
    /// A Completed row the user has not read still asks to be looked at.
    ///
    /// Only the user reading it can hide it, and that arrives on the watcher as
    /// a file change -- a hint, not a guarantee. Reporting nothing for such a
    /// row left the disappearance resting entirely on that one edge, with no
    /// bound when it landed late: traced on the live app at eight seconds of
    /// silence between the row being listed and the user reading it.
    ///
    /// The deadline must be measured forward from `now`, not from the terminal
    /// boundary. The latter sits permanently in the past, which the store
    /// clamps to its one-second floor and no refresh can move.
    @Test
    func terminalGateBooksARecheckWhileARowIsStillUnread() {
        var gate = TerminalUnreadMembershipGate(
            settlingInterval: 2,
            unreadRecheckInterval: 1
        )
        let start = Date(timeIntervalSince1970: 1_000)
        let unread = DesktopUnreadStateSnapshot(
            unreadThreadIDs: ["thread"],
            source: .current
        )

        let displayedAtOnce = gate.shouldDisplay(
            sessionID: "thread:turn", threadID: "thread", status: .completed,
            terminalBoundaryAt: start, unreadState: unread, now: start
        )
        #expect(displayedAtOnce)

        let later = start.addingTimeInterval(600)
        let stillDisplayed = gate.shouldDisplay(
            sessionID: "thread:turn", threadID: "thread", status: .completed,
            terminalBoundaryAt: start, unreadState: unread, now: later
        )
        #expect(stillDisplayed, "an unread terminal row stays listed")

        let deadline = gate.nextDeadline(now: later)
        #expect(
            deadline == later.addingTimeInterval(1),
            "an unread row must book a re-check, not go unwatched: got \(String(describing: deadline?.timeIntervalSince(later)))"
        )
        #expect(
            deadline.map { $0 > later } == true,
            "a deadline already in the past is the busy loop this replaced"
        )
    }

    /// The floor moves with each look, so it can never go stale.
    ///
    /// This is the property that separates the re-check from the deadline it
    /// replaced: the refresh at the reported instant re-evaluates the row and
    /// books the next look, rather than re-reporting an instant nothing can
    /// clear.
    @Test
    func terminalGateRecheckMovesForwardOnEveryLook() {
        var gate = TerminalUnreadMembershipGate(
            settlingInterval: 2,
            unreadRecheckInterval: 1
        )
        let start = Date(timeIntervalSince1970: 1_000)
        let unread = DesktopUnreadStateSnapshot(
            unreadThreadIDs: ["thread"],
            source: .current
        )

        _ = gate.shouldDisplay(
            sessionID: "thread:turn", threadID: "thread", status: .completed,
            terminalBoundaryAt: start, unreadState: unread, now: start
        )
        let first = gate.nextDeadline(now: start)

        let woken = start.addingTimeInterval(1)
        _ = gate.shouldDisplay(
            sessionID: "thread:turn", threadID: "thread", status: .completed,
            terminalBoundaryAt: start, unreadState: unread, now: woken
        )
        let second = gate.nextDeadline(now: woken)

        #expect(first == start.addingTimeInterval(1))
        #expect(second == woken.addingTimeInterval(1))
        #expect(
            second.map { $0 > woken } == true,
            "the re-check must stay ahead of the refresh that served it"
        )
    }

    /// Reading the row still hides it on the very next look, not on a window.
    ///
    /// The re-check is a floor under the watcher, not a delay added to it: once
    /// Desktop reports the thread read, the row goes on that evaluation.
    @Test
    func terminalGateHidesOnTheFirstLookAfterTheUserReadsIt() {
        var gate = TerminalUnreadMembershipGate(
            settlingInterval: 2,
            unreadRecheckInterval: 1
        )
        let start = Date(timeIntervalSince1970: 1_000)
        let unread = DesktopUnreadStateSnapshot(
            unreadThreadIDs: ["thread"],
            source: .current
        )
        let read = DesktopUnreadStateSnapshot(unreadThreadIDs: [], source: .current)

        _ = gate.shouldDisplay(
            sessionID: "thread:turn", threadID: "thread", status: .completed,
            terminalBoundaryAt: start, unreadState: unread, now: start
        )

        // Long past the settling window, so nothing but the unread evidence
        // itself can be doing the hiding here.
        let readAt = start.addingTimeInterval(600)
        let displayed = gate.shouldDisplay(
            sessionID: "thread:turn", threadID: "thread", status: .completed,
            terminalBoundaryAt: start, unreadState: read, now: readAt
        )
        #expect(!displayed, "a row observed unread hides the moment it reads as read")
        #expect(
            gate.nextDeadline(now: readAt) == nil,
            "a hidden row asks for nothing"
        )
    }

    /// The window that *is* real still gets reported, or the row never leaves.
    @Test
    func terminalGateStillSchedulesTheWindowItCanActuallyClear() {
        var gate = TerminalUnreadMembershipGate(settlingInterval: 2)
        let start = Date(timeIntervalSince1970: 1_000)
        // Authoritative, and Desktop does not consider it unread: the row is
        // inside its settling window and waiting really will hide it.
        let read = DesktopUnreadStateSnapshot(unreadThreadIDs: [], source: .current)

        let displayed = gate.shouldDisplay(
            sessionID: "thread:turn", threadID: "thread", status: .completed,
            terminalBoundaryAt: start, unreadState: read, now: start
        )
        #expect(displayed, "a just-finished turn is not hidden instantly")
        #expect(gate.nextDeadline(now: start) == start.addingTimeInterval(2))

        // Once the window passes, the row hides and stops asking to be woken.
        let hidden = gate.shouldDisplay(
            sessionID: "thread:turn", threadID: "thread", status: .completed,
            terminalBoundaryAt: start, unreadState: read,
            now: start.addingTimeInterval(2.1)
        )
        #expect(!hidden)
        #expect(gate.nextDeadline(now: start.addingTimeInterval(2.1)) == nil)
    }

    /// An unreadable state cannot hide anything, but it can become readable.
    ///
    /// Waiting alone does not hide this row either, so it takes the same
    /// forward-measured re-check as an unread one rather than nothing at all.
    @Test
    func terminalGateBooksARecheckWhileTheUnreadStateIsUnreadable() {
        var gate = TerminalUnreadMembershipGate(
            settlingInterval: 2,
            unreadRecheckInterval: 1
        )
        let start = Date(timeIntervalSince1970: 1_000)
        let unreadable = DesktopUnreadStateSnapshot(
            unreadThreadIDs: [],
            source: .lastKnownGood
        )

        let now = start.addingTimeInterval(600)
        let displayed = gate.shouldDisplay(
            sessionID: "thread:turn", threadID: "thread", status: .completed,
            terminalBoundaryAt: start, unreadState: unreadable, now: now
        )
        #expect(displayed, "an unreadable state must never hide a row")
        #expect(gate.nextDeadline(now: now) == now.addingTimeInterval(1))
    }

    /// A row that stops rendering must stop asking to be woken for.
    ///
    /// A Hook-tracked thread parses fine while its metadata is absent, and
    /// parses to nothing once that metadata reveals it is a sub-agent or
    /// ephemeral thread -- nothing filters those out of `threadRecords`. The
    /// gate entry created on the first pass was then never evaluated again, but
    /// `retain` kept it alive because it was keyed on every Hook state rather
    /// than on the sessions actually evaluated. Frozen inside its settling
    /// window, it reported a deadline that went stale and stayed stale, which
    /// the store clamps to its one-second floor.
    @Test @MainActor
    func aSessionThatStopsRenderingStopsSchedulingWakeUps() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install()
        // Hook timestamps have to sit on the test clock's timeline, or the
        // settling window is measured against a boundary years away.
        let clock = TestClock()
        let base = clock.now().timeIntervalSince1970
        for (index, event) in [
            [
                "received_at": base,
                "hook_event_name": "UserPromptSubmit",
                "session_id": "thread-sub",
                "turn_id": "turn-1"
            ],
            [
                "received_at": base + 1,
                "hook_event_name": "Stop",
                "session_id": "thread-sub",
                "turn_id": "turn-1"
            ]
        ].enumerated() {
            try JSONSerialization.data(withJSONObject: event).write(
                to: paths.eventsDirectory.appendingPathComponent("\(index).json")
            )
        }

        // The list reveals this thread is a sub-agent, so from the next pass on
        // it renders no row at all.
        let client = CodexAppServerStub(
            listedThreads: [
                .object([
                    "id": .string("thread-sub"),
                    "ephemeral": .bool(false),
                    "threadSource": .string("user"),
                    "agentRole": .string("reviewer"),
                    "name": .string("Sub-agent work")
                ])
            ],
            loadedListResults: []
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(
                paths: paths,
                clock: clock,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer,
            unreadState: DesktopUnreadStateStub(
                DesktopUnreadStateSnapshot(unreadThreadIDs: [], source: .current)
            ),
            clock: clock,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        // First pass: no metadata yet, so the Completed row renders and the
        // gate starts its settling window.
        let first = await service.fetchSnapshot(showsContentPreviews: false)
        #expect(first.sessions.count == 1, "the row renders before metadata lands")
        try await waitForThreadListRequests(client, atLeast: 1, completed: true)

        // Second pass, past the settling window but well inside every other
        // window, so the only deadline that could be stale is the gate's.
        await clock.advance(by: 10)
        let second = await service.fetchSnapshot(showsContentPreviews: false)
        #expect(second.sessions.isEmpty, "a sub-agent thread renders no row")

        let deadline = await service.nextRefreshDeadline()
        await service.disconnect()

        let staleBy = deadline.map { Int(clock.now().timeIntervalSince($0)) } ?? 0
        #expect(
            deadline == nil || deadline! >= clock.now(),
            "a row nobody renders left a deadline \(staleBy)s in the past"
        )
    }

    /// A suppressed disconnect has to schedule its own re-examination.
    ///
    /// The grace period only bounds the wait if something looks again when it
    /// expires. The store slept on the service's deadlines, which know nothing
    /// about this gate, so a real disconnect could sit unpublished until an
    /// unrelated wake-up or the 60s heartbeat -- against a documented budget
    /// that counts the grace as 3s.
    @Test
    func connectionGateSchedulesItsOwnGraceExpiry() {
        var gate = ConnectionStabilityGate(gracePeriod: 3)
        let t0 = Date(timeIntervalSince1970: 1_000)

        #expect(gate.nextPublishDeadline == nil, "nothing suppressed yet")

        let publishedImmediately = gate.shouldPublish(
            candidate: .disconnected, current: .ready, observedAt: t0
        )
        #expect(!publishedImmediately, "a blip is suppressed")
        #expect(
            gate.nextPublishDeadline == t0.addingTimeInterval(3),
            "the suppression must schedule the moment it expires"
        )

        let publishedAtExpiry = gate.shouldPublish(
            candidate: .disconnected, current: .ready,
            observedAt: t0.addingTimeInterval(3)
        )
        #expect(publishedAtExpiry)

        // Publishing clears it, so the deadline cannot be re-reported forever.
        let afterPublish = gate.shouldPublish(
            candidate: .disconnected, current: .disconnected,
            observedAt: t0.addingTimeInterval(4)
        )
        #expect(afterPublish)
        #expect(gate.nextPublishDeadline == nil)
    }

    /// And a recovery inside the grace clears it too.
    @Test
    func connectionGateStopsSchedulingWhenTheBlipRecovers() {
        var gate = ConnectionStabilityGate(gracePeriod: 3)
        let t0 = Date(timeIntervalSince1970: 1_000)
        _ = gate.shouldPublish(candidate: .disconnected, current: .ready, observedAt: t0)
        #expect(gate.nextPublishDeadline != nil)

        let recovered = gate.shouldPublish(
            candidate: .ready, current: .ready,
            observedAt: t0.addingTimeInterval(1)
        )
        #expect(recovered)
        #expect(gate.nextPublishDeadline == nil, "a recovery must cancel the wake-up")
    }
}

import AppKit
import Testing
@testable import CodexInNotch

struct CodexInNotchTests {
    @Test @MainActor
    func fallbackRunningBaselineMatchesFigma() {
        let size = PanelMetrics.size(
            geometry: .noNotch,
            isExpanded: false,
            statusReadoutText: "Running",
            expandedUsageReadoutText: "72%",
            centerOcclusionWidth: 0,
            compactHeight: PanelMetrics.referenceCompactHeight
        )

        #expect(size.width == 168)
        #expect(size.height == 46)
    }

    @Test @MainActor
    func fallbackWidthGrowsForLongerStatus() {
        let runningWidth = PanelMetrics.fallbackCompactWidth(statusReadoutText: "Running")
        let waitingWidth = PanelMetrics.fallbackCompactWidth(statusReadoutText: "Approval needed")

        #expect(waitingWidth > runningWidth)
        #expect(PanelMetrics.fallbackCompactWidth(statusReadoutText: "Input needed") == 200)
    }

    @Test @MainActor
    func expandedSizeUsesWiderBaselineAndKeepsCompactHeaderHeight() {
        let noNotchSize = PanelMetrics.size(
            geometry: .noNotch,
            isExpanded: true,
            statusReadoutText: "Running",
            expandedUsageReadoutText: "72%",
            centerOcclusionWidth: 0,
            compactHeight: 24
        )
        let notchedSize = PanelMetrics.size(
            geometry: .notched,
            isExpanded: true,
            statusReadoutText: "Running",
            expandedUsageReadoutText: "72%",
            centerOcclusionWidth: 200,
            compactHeight: 38
        )

        #expect(noNotchSize.width == 520)
        #expect(notchedSize.width > noNotchSize.width)
        #expect(noNotchSize.height == 24 + PanelMetrics.expandedContentHeight)
        #expect(notchedSize.height == 38 + PanelMetrics.expandedContentHeight)
    }

    @Test
    func expandedWidthKeepsEveryStatusNameClearOfWideNotch() {
        let centerOcclusionWidth: CGFloat = 220
        let width = PanelMetrics.expandedWidth(
            centerOcclusionWidth: centerOcclusionWidth,
            usageReadoutText: "100%"
        )
        let availableSideWidth = (width - centerOcclusionWidth) / 2

        for status in MonitorStatus.allCases {
            let requiredWidth = PanelMetrics.expandedHorizontalPadding
                + PanelMetrics.expandedStatusReadoutWidth(status: status)
                + PanelMetrics.expandedNotchClearance
            #expect(requiredWidth <= availableSideWidth)
        }

        let requiredUsageWidth = PanelMetrics.expandedHorizontalPadding
            + PanelMetrics.expandedUsageReadoutWidth(text: "100%")
            + PanelMetrics.expandedNotchClearance
        #expect(requiredUsageWidth <= availableSideWidth)
    }

    @Test @MainActor
    func usageThresholdsMatchTheFigmaContract() {
        #expect(UsageLevel(remainingPercent: 51) == .healthy)
        #expect(UsageLevel(remainingPercent: 50) == .warning)
        #expect(UsageLevel(remainingPercent: 15) == .warning)
        #expect(UsageLevel(remainingPercent: 14) == .critical)
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
            MonitorSnapshot(
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
        #expect(store.expandedUsageReadoutText == "72%")

        store.applyForTesting(
            MonitorSnapshot(
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
        #expect(store.compactStatusReadoutText == "Input needed")
        #expect(store.expandedUsageReadoutText == "72%")
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
            initialSnapshot: MonitorSnapshot(
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
            MonitorSnapshot(
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
            MonitorSnapshot(
                availability: .ready,
                sessions: [currentTurn, nextTurn],
                quota: .unavailable,
                diagnostic: nil
            )
        )

        #expect(store.sessions == [nextTurn])
        #expect(store.status == .running)
    }

    @Test
    func statusSetCoversEveryFigmaVariant() {
        #expect(MonitorStatus.allCases.count == 13)
        #expect(MonitorStatus.setupRequired.displayName == "Set up integration")
        #expect(MonitorStatus.inputNeeded.displayName == "Input needed")
        #expect(MonitorStatus.approvalNeeded.displayName == "Approval needed")
        #expect(MonitorStatus.connecting.displayName == "Connecting to Codex")
        #expect(MonitorStatus.unsupportedVersion.displayName == "Codex version unsupported")
        #expect(MonitorStatus.disconnected.displayName == "Codex disconnected")
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
            let store = MonitorStore(displays: [display])

            store.pointerEnteredPanel()
            try await Task.sleep(nanoseconds: 200_000_000)
            #expect(store.isExpanded)

            store.pointerExitedPanel()
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(!store.isExpanded)
        }
    }

    @Test @MainActor
    func disconnectedAvailabilityClearsAggregateEvenIfAStaleSessionExists() {
        let session = MonitoredSession(
            threadID: "thread",
            turnID: "turn",
            projectName: "Chats",
            title: "Stale task",
            preview: nil,
            status: .running,
            startedAt: Date()
        )

        #expect(
            MonitorAggregation.status(
                availability: .disconnected,
                sessions: [session]
            ) == .disconnected
        )
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
        let ready = MonitorSnapshot(
            availability: .ready,
            sessions: [session],
            quota: QuotaSnapshot(remainingPercent: 70, resetsAt: nil),
            diagnostic: nil
        )
        let disconnected = MonitorSnapshot(
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
        let ready = MonitorSnapshot(
            availability: .ready,
            sessions: [],
            quota: .unavailable,
            diagnostic: nil
        )
        let disconnected = MonitorSnapshot(
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
            MonitorAggregation.status(
                availability: .ready,
                sessions: [running, input]
            ) == .inputNeeded
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

    @Test @MainActor
    func activeThreadParserUsesProjectWaitingFlagAndPublicPreview() {
        let thread = JSONValue.object([
            "id": .string("thread-1"),
            "ephemeral": .bool(false),
            "parentThreadId": .null,
            "threadSource": .string("user"),
            "name": .string("Implement monitor"),
            "preview": .string("Original prompt"),
            "section": .object([
                "id": .string("project-1"),
                "name": .string("Codex in Notch")
            ]),
            "status": .object([
                "type": .string("active"),
                "activeFlags": .array([.string("waitingOnUserInput")])
            ]),
            "turns": .array([
                .object([
                    "id": .string("turn-1"),
                    "status": .string("inProgress"),
                    "startedAt": .number(1_000),
                    "completedAt": .null,
                    "durationMs": .null,
                    "items": .array([
                        .object([
                            "type": .string("agentMessage"),
                            "text": .string("Please choose a value")
                        ])
                    ])
                ])
            ])
        ])

        let session = CodexSnapshotParser.activeSession(from: thread)

        #expect(session?.threadID == "thread-1")
        #expect(session?.turnID == "turn-1")
        #expect(session?.projectName == "Codex in Notch")
        #expect(session?.status == .inputNeeded)
        #expect(session?.preview == "Please choose a value")
        #expect(session?.startedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test @MainActor
    func activeThreadParserRefusesToInventATurnIdentity() {
        let thread = JSONValue.object([
            "id": .string("thread-without-turn"),
            "threadSource": .string("user"),
            "status": .object([
                "type": .string("active"),
                "activeFlags": .array([])
            ])
        ])

        #expect(CodexSnapshotParser.activeSession(from: thread) == nil)
    }

    @Test @MainActor
    func appServerFlagsCorrectHookStateButDoNotCrossTurnIdentity() {
        let state = HookTurnState(
            threadID: "thread-1",
            turnID: "turn-1",
            lifecycleStatus: .running,
            pendingInput: nil,
            isApprovalPending: true,
            startedAt: Date(timeIntervalSince1970: 1_000),
            lastEventAt: Date(timeIntervalSince1970: 1_001),
            hasLiveBoundary: true,
            retiredTurnIDs: [],
            promptPreview: nil,
            assistantPreview: nil
        )
        let threadLevelOnly = JSONValue.object([
            "id": .string("thread-1"),
            "threadSource": .string("user"),
            "status": .object([
                "type": .string("active"),
                "activeFlags": .array([])
            ])
        ])
        let correctedThread = JSONValue.object([
            "id": .string("thread-1"),
            "threadSource": .string("user"),
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
        let differentActiveTurn = JSONValue.object([
            "id": .string("thread-1"),
            "threadSource": .string("user"),
            "status": .object([
                "type": .string("active"),
                "activeFlags": .array([])
            ]),
            "turns": .array([
                .object([
                    "id": .string("turn-2"),
                    "status": .string("inProgress")
                ])
            ])
        ])

        #expect(
            CodexSnapshotParser.session(from: state, thread: correctedThread)?.status
                == .running
        )
        #expect(
            CodexSnapshotParser.session(from: state, thread: threadLevelOnly)?.status
                == .running
        )
        var historicalState = state
        historicalState.hasLiveBoundary = false
        #expect(
            CodexSnapshotParser.session(
                from: historicalState,
                thread: threadLevelOnly
            )?.status == .approvalNeeded
        )
        var terminalState = state
        terminalState.lifecycleStatus = .completed
        terminalState.isApprovalPending = false
        #expect(
            CodexSnapshotParser.session(
                from: terminalState,
                thread: threadLevelOnly
            )?.status == .completed
        )
        #expect(
            CodexSnapshotParser.session(from: state, thread: differentActiveTurn)?.status
                == .approvalNeeded
        )
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

        let session = CodexSnapshotParser.activeSession(
            from: thread,
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
    func appServerTerminalStatesMapToDistinctMonitorStates() {
        func turn(status: String) -> JSONValue {
            .object(["status": .string(status)])
        }

        #expect(CodexSnapshotParser.terminalStatus(from: turn(status: "completed")) == .completed)
        #expect(CodexSnapshotParser.terminalStatus(from: turn(status: "failed")) == .error)
        #expect(CodexSnapshotParser.terminalStatus(from: turn(status: "interrupted")) == .cancelled)
        #expect(CodexSnapshotParser.terminalStatus(from: turn(status: "inProgress")) == nil)
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
            initialSnapshot: MonitorSnapshot(
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
                MonitorSnapshot(
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
                + 16
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

        try await navigator.open(threadID: "thread-123")

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
            try await navigator.open(threadID: "deleted-thread")
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
        let successNavigator = CodexNavigatorStub()
        let successStore = MonitorStore(navigator: successNavigator)
        successStore.isExpanded = true

        let didOpen = await successStore.openAndWait(session)

        #expect(didOpen)
        #expect(!successStore.isExpanded)
        #expect(successNavigator.requestedThreadIDs == ["thread-123"])

        let failureNavigator = CodexNavigatorStub(error: .openRejected)
        let failureStore = MonitorStore(navigator: failureNavigator)
        failureStore.isExpanded = true

        let didOpenMissingTarget = await failureStore.openAndWait(session)

        #expect(!didOpenMissingTarget)
        #expect(failureStore.isExpanded)
        #expect(failureStore.lastIntegrationMessage.contains("未能接受"))
    }

    @Test @MainActor
    func startupAvoidsThreadReadsAndPreservesReadyStateAfterLocalTimeout() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install(showsContentPreviews: true)

        let listedThread = JSONValue.object([
            "id": .string("thread-1"),
            "ephemeral": .bool(false),
            "parentThreadId": .null,
            "threadSource": .string("user"),
            "name": .string("Fast startup"),
            "section": .object(["name": .string("Codex in Notch")]),
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
            loadedListResults: [
                .success(.object([
                    "data": .array([.string("thread-1")])
                ])),
                .failure(.timeout(method: "thread/loaded/list"))
            ]
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(
                paths: paths,
                liveEventCutoff: .distantPast
            ),
            hookInstaller: installer
        )

        let ready = await service.fetchSnapshot(showsContentPreviews: true)
        let afterTimeout = await service.fetchSnapshot(showsContentPreviews: true)
        let requestedMethods = await client.requestedMethods()

        #expect(ready.availability == .ready)
        #expect(ready.sessions.count == 1)
        #expect(ready.sessions.first?.status == .running)
        #expect(ready.sessions.first?.turnID == "turn-1")
        #expect(afterTimeout.availability == .ready)
        #expect(afterTimeout.sessions == ready.sessions)
        #expect(afterTimeout.diagnostic?.contains("保留最近状态") == true)
        #expect(!requestedMethods.contains("thread/read"))
        #expect(await client.disconnectCount() == 0)

        await service.disconnect()
    }

    @Test @MainActor
    func trustedHookMarkerRestartsReadyWithoutRestoringTurnState() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install(showsContentPreviews: false)
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
        let methods = await restoredClient.requestedMethods()
        await restoredService.disconnect()

        #expect(restored.availability == .ready)
        #expect(restored.sessions.isEmpty)
        #expect(methods.contains("thread/list"))
        #expect(!methods.contains("thread/loaded/list"))
        #expect(!methods.contains("thread/read"))
    }

    @Test @MainActor
    func newHookBoundaryRefreshesAppServerFlagsBeforeCorrection() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install(showsContentPreviews: false)
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

        let approval = try JSONSerialization.data(withJSONObject: [
            "received_at": timestamp + 1,
            "hook_event_name": "PermissionRequest",
            "session_id": "thread-1",
            "turn_id": "turn-1"
        ])
        try approval.write(
            to: paths.eventsDirectory.appendingPathComponent("1.json")
        )
        let corrected = await service.fetchSnapshot(showsContentPreviews: false)
        let threadListRequests = await client.requestCount(method: "thread/list")
        await service.disconnect()

        #expect(corrected.sessions.first?.status == .running)
        #expect(threadListRequests == 2)
    }

    @Test @MainActor
    func unknownDetailReadDoesNotBlockOrDuplicateTheReadySnapshot() async throws {
        let paths = makeTemporaryHookPaths()
        defer {
            try? FileManager.default.removeItem(
                at: paths.supportDirectory.deletingLastPathComponent()
            )
        }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install(showsContentPreviews: false)
        let event = try JSONSerialization.data(withJSONObject: [
            "received_at": Date().timeIntervalSince1970,
            "hook_event_name": "Stop",
            "session_id": "thread-unknown",
            "turn_id": "turn-unknown"
        ])
        try event.write(
            to: paths.eventsDirectory.appendingPathComponent("unknown.json")
        )

        let client = CodexAppServerStub(
            listedThreads: [.object([
                "id": .string("thread-unknown"),
                "ephemeral": .bool(false),
                "threadSource": .string("user"),
                "name": .string("Unknown turn"),
                "updatedAt": .number(Date().timeIntervalSince1970)
            ])],
            loadedListResults: [],
            threadReadDelayNanoseconds: 2_000_000_000
        )
        let service = LiveCodexMonitorService(
            client: client,
            hookEvents: HookEventRepository(paths: paths),
            hookInstaller: installer,
            desktopProcessIdentifierProvider: { 4_242 }
        )

        let startedAt = Date()
        let first = await service.fetchSnapshot(showsContentPreviews: false)
        let elapsed = Date().timeIntervalSince(startedAt)
        for _ in 0..<50 {
            if await client.requestCount(method: "thread/read") > 0 {
                break
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let second = await service.fetchSnapshot(showsContentPreviews: false)
        let methods = await client.requestedMethods()
        await service.disconnect()

        #expect(first.availability == .ready)
        #expect(first.sessions.first?.status == .unknown)
        #expect(second.availability == .ready)
        // The detail stub sleeps for two seconds. Keep enough headroom for
        // parallel MainActor test scheduling while still proving fetchSnapshot
        // did not await the detail request.
        #expect(elapsed < 1.5)
        #expect(methods.filter { $0 == "thread/read" }.count == 1)
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
        try await installer.install(showsContentPreviews: false)
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
        let requestedMethods = await client.requestedMethods()
        await service.disconnect()

        #expect(snapshot.availability == .ready)
        #expect(requestedMethods.contains("thread/list"))
        #expect(!requestedMethods.contains("thread/loaded/list"))
        #expect(!requestedMethods.contains("thread/read"))
        #expect(elapsed < 10)
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
        try await installer.install(showsContentPreviews: false)
        try await installer.install(showsContentPreviews: false)

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

        try "#!/usr/bin/python3\nprint('{}')\n".write(
            to: paths.script,
            atomically: true,
            encoding: .utf8
        )
        #expect(await installer.status(hasObservedEvent: true) == .notInstalled)
        try await installer.install(showsContentPreviews: false)
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
    func hookReducerTracksTurnLifecycleAndDoesNotPersistPreviewText() async throws {
        let paths = makeTemporaryHookPaths()
        defer { try? FileManager.default.removeItem(at: paths.supportDirectory.deletingLastPathComponent()) }
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
                "turn_id": "turn-1",
                "prompt": "private prompt"
            ],
            [
                "received_at": timestamp + 1,
                "hook_event_name": "PermissionRequest",
                "session_id": "thread-1",
                "turn_id": "turn-1"
            ],
            [
                "received_at": timestamp + 2,
                "hook_event_name": "PostToolUse",
                "session_id": "thread-1",
                "turn_id": "turn-1",
                "tool_name": "Bash",
                "tool_use_id": "bash-1"
            ]
        ]

        for (index, event) in events.enumerated() {
            let data = try JSONSerialization.data(withJSONObject: event)
            try data.write(
                to: paths.eventsDirectory.appendingPathComponent("\(index).json")
            )
        }

        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )
        let waitingSnapshot = await repository.consumeEvents()
        #expect(waitingSnapshot.turns.first?.status == .approvalNeeded)

        let stop = try JSONSerialization.data(withJSONObject: [
            "received_at": timestamp + 3,
            "hook_event_name": "Stop",
            "session_id": "thread-1",
            "turn_id": "turn-1",
            "last_assistant_message": "private answer"
        ])
        try stop.write(
            to: paths.eventsDirectory.appendingPathComponent("3.json")
        )

        let snapshot = await repository.consumeEvents()
        let turn = try #require(snapshot.turns.first)
        let persistedText = try String(contentsOf: paths.state, encoding: .utf8)

        #expect(snapshot.hasObservedEvent)
        #expect(turn.threadID == "thread-1")
        #expect(turn.turnID == "turn-1")
        #expect(turn.status == .unknown)
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
        let approval = await repository.consumeEvents()
        #expect(approval.turns.first?.status == .approvalNeeded)
    }

    @Test @MainActor
    func startupBacklogDoesNotRestoreAnActiveTurn() async throws {
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
        #expect(live.turns.first?.turnID == "turn-2")
        #expect(live.turns.first?.status == .running)
    }

    @Test @MainActor
    func appServerEvidenceCorrectsOnlyTheExactCurrentTurn() async throws {
        let paths = makeTemporaryHookPaths()
        defer { try? FileManager.default.removeItem(at: paths.supportDirectory.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: paths.eventsDirectory,
            withIntermediateDirectories: true
        )

        let events: [[String: Any]] = [
            [
                "received_at": 100.0,
                "hook_event_name": "UserPromptSubmit",
                "session_id": "thread-1",
                "turn_id": "turn-1"
            ],
            [
                "received_at": 101.0,
                "hook_event_name": "PermissionRequest",
                "session_id": "thread-1",
                "turn_id": "turn-1"
            ]
        ]
        for (index, event) in events.enumerated() {
            let data = try JSONSerialization.data(withJSONObject: event)
            try data.write(
                to: paths.eventsDirectory.appendingPathComponent("\(index).json")
            )
        }

        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )
        #expect(await repository.consumeEvents().turns.first?.status == .approvalNeeded)

        let ignoredDifferentTurn = await repository.reconcileActiveStatus(
            threadID: "thread-1",
            turnID: "other-turn",
            isInputPending: false,
            isApprovalPending: false
        )
        #expect(!ignoredDifferentTurn)
        #expect(await repository.consumeEvents().turns.first?.status == .approvalNeeded)

        let appliedInput = await repository.reconcileActiveStatus(
            threadID: "thread-1",
            turnID: "turn-1",
            isInputPending: true,
            isApprovalPending: true
        )
        #expect(appliedInput)
        #expect(await repository.consumeEvents().turns.first?.status == .inputNeeded)

        let appliedRunning = await repository.reconcileActiveStatus(
            threadID: "thread-1",
            turnID: "turn-1",
            isInputPending: false,
            isApprovalPending: false
        )
        #expect(appliedRunning)
        #expect(await repository.consumeEvents().turns.first?.status == .running)

        let appliedTerminal = await repository.resolveTerminalStatus(
            threadID: "thread-1",
            turnID: "turn-1",
            status: .completed
        )
        #expect(appliedTerminal)
        #expect(await repository.consumeEvents().turns.first?.status == .completed)

        let refusedReopen = await repository.reconcileActiveStatus(
            threadID: "thread-1",
            turnID: "turn-1",
            isInputPending: false,
            isApprovalPending: false
        )
        #expect(!refusedReopen)
        #expect(await repository.consumeEvents().turns.first?.status == .completed)
    }

    @Test @MainActor
    func installedHookScriptWritesAConsumablePrivateEvent() async throws {
        let paths = makeTemporaryHookPaths()
        defer { try? FileManager.default.removeItem(at: paths.supportDirectory.deletingLastPathComponent()) }

        let installer = CodexHookInstaller(paths: paths)
        try await installer.install(showsContentPreviews: true)

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
        let rawEvent = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: eventURL)
            ) as? [String: Any]
        )
        let repository = HookEventRepository(
            paths: paths,
            liveEventCutoff: .distantPast
        )
        let snapshot = await repository.consumeEvents()

        #expect(process.terminationStatus == 0)
        #expect(String(data: stdout, encoding: .utf8) == "{}\n")
        #expect(rawEvent["tool_use_id"] as? String == "tool-script")
        #expect(rawEvent["cwd"] == nil)
        #expect(rawEvent["reason"] == nil)
        #expect(snapshot.turns.first?.threadID == "thread-script")
        #expect(snapshot.turns.first?.promptPreview == "script preview")
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

    private func makeTemporaryHookPaths() -> HookIntegrationPaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexInNotchTests-\(UUID().uuidString)")
        return HookIntegrationPaths(
            supportDirectory: root.appendingPathComponent("ApplicationSupport"),
            hooksConfiguration: root.appendingPathComponent(".codex/hooks.json")
        )
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
    private let threadReadDelayNanoseconds: UInt64
    private var loadedListResults: [Result<JSONValue, CodexAppServerError>]
    private var methods: [String] = []
    private var disconnects = 0

    init(
        listedThreads: [JSONValue],
        loadedListResults: [Result<JSONValue, CodexAppServerError>],
        threadReadDelayNanoseconds: UInt64 = 0
    ) {
        self.listedThreads = listedThreads
        self.loadedListResults = loadedListResults
        self.threadReadDelayNanoseconds = threadReadDelayNanoseconds
    }

    func connect() async throws {}

    func request(
        method: String,
        params: JSONValue?,
        timeoutNanoseconds: UInt64?
    ) async throws -> JSONValue {
        methods.append(method)
        switch method {
        case "thread/list":
            return .object([
                "data": .array(listedThreads),
                "nextCursor": .null
            ])
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
        case "thread/read":
            if threadReadDelayNanoseconds > 0 {
                try await Task.sleep(
                    nanoseconds: threadReadDelayNanoseconds
                )
            }
            throw CodexAppServerError.timeout(method: method)
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
private final class CodexNavigatorStub: CodexNavigating {
    private let error: CodexNavigationError?
    private(set) var requestedThreadIDs: [String] = []

    init(error: CodexNavigationError? = nil) {
        self.error = error
    }

    func open(threadID: String) async throws {
        requestedThreadIDs.append(threadID)
        if let error {
            throw error
        }
    }
}

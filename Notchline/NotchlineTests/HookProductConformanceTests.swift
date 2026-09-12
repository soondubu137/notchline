import Foundation
import Testing
@testable import Notchline

/// The Tier 0 and Tier 1 fixtures of `tiered-support.md` §7, run against the
/// Provider a hook-based product gets for free (``HookProductProvider``).
///
/// The product under test is synthetic: two vocabularies that map only what
/// the tier requires, over a temporary root, with presence and admission
/// stubbed. It borrows `AgentKind.claudeCode` because the enum has no third
/// case yet — a real third product arrives with its own descriptor in P5 — and
/// nothing here reads anything of Claude Code's: the paths are the fixture's,
/// the vocabulary is the fixture's, and the socket is never bound to the
/// user's.
@Suite(.serialized)
struct HookProductConformanceTests {
    // MARK: - Fixtures

    /// A product whose hooks say only "a Turn started" and "it ended".
    private struct ListedOnlyVocabulary: AgentHookVocabulary {
        let agent: AgentKind = .claudeCode
        let managedDefinitions = [
            ManagedHookDefinition(event: "UserPromptSubmit", matcher: nil),
            ManagedHookDefinition(event: "Stop", matcher: nil)
        ]
        let legacyCommandMarkers: [String] = []
        let reportsApprovalDenials = false
        let carriesPromptText = true
        let carriesFinalAnswerText = false
        let messageDeltaEventName: String? = nil
        let wakesOnToolCallOpened = false
        let settlesHeldTurnsFromRecord = false
        let restoreDefinitionAdvice = "Turn the switch off and on."
        let answeringTimeoutSeconds = 60
        let answering: (any RequestAnswering)? = nil

        func signal(forEvent name: String, toolName: String?) -> HookSignal? {
            switch name {
            case "UserPromptSubmit": .turnStarted
            case "Stop": .turnEnded
            default: nil
            }
        }

        func request(
            forEvent name: String,
            toolName: String?,
            toolInput: JSONValue?,
            permissionSuggestions: JSONValue?,
            openedBy toolUseID: String
        ) -> AgentRequest? {
            nil
        }
    }

    /// The same product, one tier up: it also says when a tool call is open and
    /// when it is waiting on a person, and shows the command — but has no way
    /// to carry an answer back.
    private struct AttendedVocabulary: AgentHookVocabulary {
        let agent: AgentKind = .claudeCode
        let managedDefinitions = [
            ManagedHookDefinition(event: "UserPromptSubmit", matcher: nil),
            ManagedHookDefinition(event: "PreToolUse", matcher: nil),
            ManagedHookDefinition(event: "PermissionRequest", matcher: nil),
            ManagedHookDefinition(event: "PostToolUse", matcher: nil),
            ManagedHookDefinition(event: "Stop", matcher: nil)
        ]
        let legacyCommandMarkers: [String] = []
        let reportsApprovalDenials = false
        let carriesPromptText = true
        let carriesFinalAnswerText = false
        let messageDeltaEventName: String? = nil
        let wakesOnToolCallOpened = false
        let settlesHeldTurnsFromRecord = false
        let restoreDefinitionAdvice = "Turn the switch off and on."
        let answeringTimeoutSeconds = 60
        let answering: (any RequestAnswering)? = nil

        func signal(forEvent name: String, toolName: String?) -> HookSignal? {
            switch name {
            case "UserPromptSubmit": .turnStarted
            case "PreToolUse": .toolCallOpened
            case "PermissionRequest": .approvalWaitInferred
            case "PostToolUse": .toolCallClosed
            case "Stop": .turnEnded
            default: nil
            }
        }

        func request(
            forEvent name: String,
            toolName: String?,
            toolInput: JSONValue?,
            permissionSuggestions: JSONValue?,
            openedBy toolUseID: String
        ) -> AgentRequest? {
            guard name == "PermissionRequest" else { return nil }
            return AgentRequest(id: toolUseID, toolName: toolName, form: .command("rm -rf build"))
        }
    }

    private final class PresenceStub: ProductPresenceReporting, @unchecked Sendable {
        private let lock = NSLock()
        private var value: AgentPresence
        init(_ value: AgentPresence) { self.value = value }
        nonisolated func set(_ value: AgentPresence) {
            lock.lock()
            self.value = value
            lock.unlock()
        }
        nonisolated func presence() async -> AgentPresence {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    /// Limits read on a clock of the product's own, answering what the test
    /// says and recording whether a read was asked for.
    private actor UsageStub: UsageReading {
        let quota: QuotaSnapshot
        let deadline: Date?
        let diagnostic: String?
        private(set) var readsAskedFor = 0
        init(quota: QuotaSnapshot, deadline: Date?, diagnostic: String?) {
            self.quota = quota
            self.deadline = deadline
            self.diagnostic = diagnostic
        }
        func currentQuota() -> QuotaSnapshot { quota }
        func readIfStale() { readsAskedFor += 1 }
        func nextReadDeadline() -> Date? { deadline }
        func quotaDiagnostic() -> String? { diagnostic }
    }

    private final class AdmissionStub: ThreadAdmitting, @unchecked Sendable {
        private let lock = NSLock()
        private var value: ThreadAdmission = .everyObservedThread
        nonisolated func set(_ value: ThreadAdmission) {
            lock.lock()
            self.value = value
            lock.unlock()
        }
        nonisolated func admission() async -> ThreadAdmission {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    /// One synthetic product over a root of its own, torn down with it.
    private struct Product {
        let root: URL
        let paths: HookIntegrationPaths
        let presence = PresenceStub(.open)
        let admission = AdmissionStub()
        let provider: HookProductProvider

        init(vocabulary: any AgentHookVocabulary, usage: (any UsageReading)? = nil) throws {
            // Short on purpose: a Unix socket path may not exceed 104 bytes.
            root = URL(fileURLWithPath: "/tmp")
                .appendingPathComponent("hpp-\(UUID().uuidString.prefix(8))")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            paths = HookIntegrationPaths(
                supportDirectory: root.appendingPathComponent("AS"),
                hooksConfiguration: root.appendingPathComponent("settings.json"),
                agent: vocabulary.agent
            )
            provider = HookProductProvider(
                agent: vocabulary.agent,
                paths: paths,
                vocabulary: vocabulary,
                presence: presence,
                admission: admission,
                usage: usage
            )
        }

        func deliver(_ event: [String: Any], at date: Date) throws {
            let data = try JSONSerialization.data(withJSONObject: event)
            _ = provider.repository.deliver(data, at: date)
        }

        func tearDown() async {
            await provider.disconnect()
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// Well in the past, because the reducer's new-Turn reconciliation grace is
    /// measured against the real clock and a fixture dated ahead of it would
    /// never be old enough to retire.
    private let t0 = Date(timeIntervalSince1970: 1_757_000_000)

    private func submission(_ thread: String, turn: String, cwd: String = "/Users/someone/Projects/demo") -> [String: Any] {
        [
            "hook_event_name": "UserPromptSubmit",
            "session_id": thread,
            "prompt_id": turn,
            "cwd": cwd,
            "prompt": "Fix the build"
        ]
    }

    private func stop(_ thread: String, turn: String) -> [String: Any] {
        ["hook_event_name": "Stop", "session_id": thread, "prompt_id": turn]
    }

    // MARK: - Tier 0: Listed

    /// Setup, a row on submission, `Completed` on the end event, and the Tier 0
    /// row content: the directory's last component, the prompt, the start.
    @Test
    func aStartAndAnEndAreARowThatComesAndGoes() async throws {
        let product = try Product(vocabulary: ListedOnlyVocabulary())
        defer { Task { await product.tearDown() } }

        #expect(await product.provider.setupStatus() == .notInstalled)
        let unregistered = await product.provider.fetchSnapshot()
        #expect(unregistered.availability == .setupRequired)
        #expect(unregistered.sessions.isEmpty)

        try await product.provider.installIntegration()
        #expect(await product.provider.setupStatus() == .active)
        let registered = await product.provider.fetchSnapshot()
        #expect(registered.availability == .ready)
        #expect(registered.presence == .open)
        #expect(registered.sessions.isEmpty)
        // No windows rather than one made of dashes: a Provider that reads no
        // quota gets an outer footer row and no lines under it
        // (`quota-footer-v2.md` §5).
        #expect(registered.quota == .noneReported)
        #expect(registered.quota.windows.isEmpty)

        try product.deliver(submission("t1", turn: "p1"), at: t0)
        let running = await product.provider.fetchSnapshot()
        let row = try #require(running.sessions.first)
        #expect(running.sessions.count == 1)
        #expect(row.agent == .claudeCode)
        #expect(row.threadID == "t1")
        #expect(row.turnID == "p1")
        #expect(row.status == .running)
        #expect(row.projectName == "demo")
        #expect(row.title == "Fix the build")
        #expect(row.startedAt == t0)
        #expect(row.finishedAt == nil)
        #expect(row.request == nil)

        try product.deliver(stop("t1", turn: "p1"), at: t0.addingTimeInterval(9))
        let finished = await product.provider.fetchSnapshot()
        let done = try #require(finished.sessions.first)
        #expect(done.status == .completed)
        #expect(done.finishedAt == t0.addingTimeInterval(9))
        // This product supplies no read evidence, so the row stays until its
        // own exits apply -- and books nothing while it stands, because there
        // is no reading a re-check could take (`tiered-support.md` §2, the
        // Tier 0 lifecycle). A product that hands in
        // ``TerminalReadEvidence`` gets the other behaviour and pays for it;
        // see `AntigravityConformanceTests`.
        #expect(await product.provider.fetchSnapshot().sessions.count == 1)
        #expect(await product.provider.nextRefreshDeadline() == nil)

        try await product.provider.removeIntegration()
        #expect(await product.provider.setupStatus() == .notInstalled)
        #expect(await product.provider.fetchSnapshot().availability == .setupRequired)
    }

    /// A Thread has one open Turn: the next submission replaces the row once
    /// the first Turn has ended, and a late event for the Turn it replaced
    /// changes nothing.
    @Test
    func anOldTurnsEventCannotTouchTheTurnThatReplacedIt() async throws {
        let product = try Product(vocabulary: ListedOnlyVocabulary())
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()

        try product.deliver(submission("t1", turn: "p1"), at: t0)
        try product.deliver(stop("t1", turn: "p1"), at: t0.addingTimeInterval(4))
        try product.deliver(submission("t1", turn: "p2"), at: t0.addingTimeInterval(5))
        // Duplicate end for the retired Turn, arriving late.
        try product.deliver(stop("t1", turn: "p1"), at: t0.addingTimeInterval(6))
        let snapshot = await product.provider.fetchSnapshot()
        #expect(snapshot.sessions.count == 1)
        #expect(snapshot.sessions.first?.turnID == "p2")
        #expect(snapshot.sessions.first?.status == .running)
        #expect(snapshot.sessions.first?.startedAt == t0.addingTimeInterval(5))
    }

    /// A second submission while the first Turn is still working is not this
    /// Thread's next Turn — one agent, one open Turn — so it is held rather than
    /// drawn over the running row (the reducer's identity rule, `tech-design.md`
    /// §9.2).
    @Test
    func aSubmissionDuringARunningTurnDoesNotReplaceIt() async throws {
        let product = try Product(vocabulary: ListedOnlyVocabulary())
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()

        try product.deliver(submission("t1", turn: "p1"), at: t0)
        try product.deliver(submission("t1", turn: "p2"), at: t0.addingTimeInterval(5))
        let snapshot = await product.provider.fetchSnapshot()
        #expect(snapshot.sessions.count == 1)
        #expect(snapshot.sessions.first?.turnID == "p1")
        #expect(snapshot.sessions.first?.status == .running)
    }

    /// A submission directory the product did not send is not guessed.
    @Test
    func aMissingDirectoryIsAnUntitledFolderNotAGuess() throws {
        #expect(HookProductProvider.projectName(forWorkingDirectory: nil) == "Untitled folder")
        #expect(HookProductProvider.projectName(forWorkingDirectory: "") == "Untitled folder")
        #expect(HookProductProvider.projectName(forWorkingDirectory: "/") == "Untitled folder")
        #expect(HookProductProvider.projectName(forWorkingDirectory: "/Users/x/Projects/demo/") == "demo")
    }

    /// Presence draws the matrix and the reducer lights it: a closed product
    /// lists nothing but is still observable, and an unknown one is honestly
    /// unwatchable rather than quietly empty.
    @Test
    func presenceDecidesWhatIsListedAndNeverWhatIsKnown() async throws {
        let product = try Product(vocabulary: ListedOnlyVocabulary())
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        try product.deliver(submission("t1", turn: "p1"), at: t0)

        product.presence.set(.closed)
        let closed = await product.provider.fetchSnapshot()
        #expect(closed.availability == .ready)
        #expect(closed.presence == .closed)
        #expect(closed.sessions.isEmpty)
        #expect(!closed.isConnected)

        product.presence.set(.unknown)
        let unknown = await product.provider.fetchSnapshot()
        #expect(unknown.availability == .disconnected)
        #expect(unknown.diagnostic?.contains("cannot tell whether it is open") == true)

        product.presence.set(.open)
        let open = await product.provider.fetchSnapshot()
        #expect(open.isConnected)
        #expect(open.sessions.count == 1, "the Turn survived the product being closed and unknown")
    }

    /// Only the product's own list retires a Thread, and only a read that
    /// began after the Thread last spoke can do it. The Turn is ended first:
    /// absence from a list never ends a live Turn (`tiered-support.md` §2).
    @Test
    func onlyAnAdmissionListThatPostdatesTheThreadRetiresIt() async throws {
        let product = try Product(vocabulary: ListedOnlyVocabulary())
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()
        try product.deliver(submission("t1", turn: "p1"), at: t0)
        try product.deliver(stop("t1", turn: "p1"), at: t0)

        product.admission.set(.unknown)
        #expect(await product.provider.fetchSnapshot().sessions.count == 1)

        // A list read before the submission cannot have seen it.
        product.admission.set(.exactly([], readAt: t0.addingTimeInterval(-1)))
        #expect(await product.provider.fetchSnapshot().sessions.count == 1)

        product.admission.set(.exactly(["t1", "t9"], readAt: t0.addingTimeInterval(1)))
        #expect(await product.provider.fetchSnapshot().sessions.count == 1)

        product.admission.set(.exactly(["t9"], readAt: t0.addingTimeInterval(2)))
        #expect(await product.provider.fetchSnapshot().sessions.isEmpty)
    }

    /// The store operates the product through the contracts alone: one switch,
    /// installed and removed, with no product-named code in between.
    @Test @MainActor
    func theStoreRunsTheProductThroughItsContractsAlone() async throws {
        let product = try Product(vocabulary: ListedOnlyVocabulary())
        defer { Task { await product.tearDown() } }
        let store = MonitorStore(services: [product.provider])
        defer { store.stopMonitoring() }

        #expect(!store.integrationSwitchIsOn(for: .claudeCode))
        #expect(await store.setIntegrationEnabledAndWait(true, for: .claudeCode))
        #expect(store.integrationSwitchIsOn(for: .claudeCode))
        #expect(store.setupStatus(for: .claudeCode) == .active)
        #expect(await product.provider.setupStatus() == .active)

        #expect(await store.setIntegrationEnabledAndWait(false, for: .claudeCode))
        #expect(!store.integrationSwitchIsOn(for: .claudeCode))
        #expect(store.agentAvailability(for: .claudeCode) == .setupRequired)
    }

    // MARK: - Tier 1: Attended

    /// A wait opens on the request event, shows what it is waiting for, and
    /// closes when the tool call it borrowed its identity from closes. With no
    /// answer encoding, the row offers no affirmative — it never claims a way
    /// back it does not have.
    @Test
    func aWaitIsShownButNotAnsweredWithoutAnEncoding() async throws {
        let product = try Product(vocabulary: AttendedVocabulary())
        defer { Task { await product.tearDown() } }
        try await product.provider.installIntegration()

        try product.deliver(submission("t1", turn: "p1"), at: t0)
        try product.deliver(
            [
                "hook_event_name": "PreToolUse", "session_id": "t1", "prompt_id": "p1",
                "tool_name": "Bash", "tool_use_id": "tu-1",
                "tool_input": ["command": "rm -rf build"]
            ],
            at: t0.addingTimeInterval(1)
        )
        try product.deliver(
            [
                "hook_event_name": "PermissionRequest", "session_id": "t1", "prompt_id": "p1",
                "tool_name": "Bash", "tool_use_id": "tu-1",
                "tool_input": ["command": "rm -rf build"]
            ],
            at: t0.addingTimeInterval(2)
        )
        let waiting = await product.provider.fetchSnapshot()
        let row = try #require(waiting.sessions.first)
        #expect(row.status == .approvalNeeded)
        let request = try #require(row.request)
        #expect(request.form == .command("rm -rf build"))
        #expect(!request.canBeAnswered)
        #expect(request.answerHandle == nil)

        try product.deliver(
            [
                "hook_event_name": "PostToolUse", "session_id": "t1", "prompt_id": "p1",
                "tool_name": "Bash", "tool_use_id": "tu-1"
            ],
            at: t0.addingTimeInterval(3)
        )
        let resumed = await product.provider.fetchSnapshot()
        #expect(resumed.sessions.first?.status == .running)
        #expect(resumed.sessions.first?.request == nil)
    }

    // MARK: - Capabilities

    /// A product that hands in a usage reader publishes its limits, books the
    /// reader's deadline, and says its sentence last; the same Provider with
    /// none publishes no windows and books nothing (`quota-footer-v2.md` §5).
    @Test
    func aUsageReaderIsPublishedAndBookedOnlyWhereOneIsHandedIn() async throws {
        let quota = QuotaSnapshot(
            windows: [QuotaWindow(label: "5h limit", remainingPercent: 62, resetsAt: nil)]
        )
        let deadline = t0.addingTimeInterval(1_800)
        let usage = UsageStub(quota: quota, deadline: deadline, diagnostic: "Sign the CLI in.")
        let product = try Product(vocabulary: ListedOnlyVocabulary(), usage: usage)
        defer { Task { await product.tearDown() } }

        let unregistered = await product.provider.fetchSnapshot()
        #expect(unregistered.quota == .unavailable)
        #expect(await usage.readsAskedFor == 0)

        try await product.provider.installIntegration()
        let registered = await product.provider.fetchSnapshot()
        #expect(registered.quota == quota)
        #expect(registered.diagnostic == "Sign the CLI in.")
        #expect(await usage.readsAskedFor == 1)
        #expect(await product.provider.nextRefreshDeadline() == deadline)

        let bare = try Product(vocabulary: ListedOnlyVocabulary())
        defer { Task { await bare.tearDown() } }
        try await bare.provider.installIntegration()
        #expect(await bare.provider.fetchSnapshot().quota == .noneReported)
        #expect(await bare.provider.nextRefreshDeadline() == nil)
    }
}

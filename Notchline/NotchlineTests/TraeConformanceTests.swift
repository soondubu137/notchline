import AppKit
import SwiftUI
import Foundation
import Testing
@testable import Notchline

@MainActor
struct TraeConformanceTests {
    private let t0 = 1_789_270_000.0
    private func id(_ n: Int) -> String { String(repeating: "0", count: 24 - String(n, radix: 16).count) + String(n, radix: 16) }
    private func row(thread: Int = 1, turn: Int = 2, status: String = "in_progress", at: Double? = nil,
                     requests: [TraeDisplayedRequest] = [], preview: String? = "Displayed words") -> TraeDisplayedTurn {
        TraeDisplayedTurn(threadID: id(thread), turnID: id(turn), messageID: id(turn + 100),
            userMessageID: id(turn + 200), title: "Native title", folder: "/Projects/example", status: status,
            startedAt: at ?? t0 + 1, endedAt: status == "in_progress" ? nil : t0 + 10,
            historical: false, preview: preview, requests: requests)
    }
    private func command(_ n: Int = 5, producer: String = "root") -> TraeDisplayedRequest {
        TraeDisplayedRequest(id: id(n), toolID: id(n + 1000), producer: producer, name: "RunCommand",
            kind: "command", command: "printf test", details: ["cwd": .string("/Projects/example")], questions: nil)
    }
    private func frame(_ sequence: Int, _ rows: [TraeDisplayedTurn], baseline: Bool = false, at: Double? = nil) -> TraeFrame {
        TraeFrame(type: "snapshot", schema: 1, version: "3.5.91", sequence: sequence,
            baseline: baseline, observedAt: at ?? t0 + Double(sequence), rows: rows)
    }
    private func consume(_ frame: TraeFrame, _ boundary: inout TraeEvidenceBoundary,
                         _ repository: MonitoringRepository, peer: String = "window") throws {
        try boundary.consume(frame, peer: peer, repository: repository, epoch: repository.observationEpoch)
    }

    @Test func historicalBaselineDoesNotAdmitACompletedOrAlreadyRunningTurn() async throws {
        var boundary = TraeEvidenceBoundary(); let repository = MonitoringRepository(policy: .explicit)
        try consume(frame(1, [row(at: t0 - 10), row(thread: 3, turn: 4, status: "completed")], baseline: true), &boundary, repository)
        try consume(frame(2, [row(at: t0 - 10, requests: [command()])]), &boundary, repository)
        #expect(await repository.drainDeliveredEvents().turns.isEmpty)
    }
    @Test func liveStartProgressWaitResolutionAndCancellationUseSharedReducer() async throws {
        var boundary = TraeEvidenceBoundary(); let repository = MonitoringRepository(policy: .explicit)
        try consume(frame(1, [], baseline: true), &boundary, repository)
        try consume(frame(2, [row()]), &boundary, repository)
        var state = await repository.drainDeliveredEvents()
        #expect(state.turns.first?.status == .running)
        #expect(state.turns.first?.startedAt == Date(timeIntervalSince1970: t0 + 1))
        #expect(repository.messageReader.preview(forSession: id(1), inTurn: id(2)) == "Displayed words")
        try consume(frame(3, [row(requests: [command()])]), &boundary, repository)
        state = await repository.drainDeliveredEvents()
        #expect(state.turns.first?.status == .approvalNeeded)
        let request = try #require(state.turns.first?.requestsAwaitingAnAnswer.first)
        #expect(!request.canBeAnswered)
        #expect(request.operations == .readingOnly)
        #expect(request.form == .command("printf test"))
        try consume(frame(4, [row()]), &boundary, repository)
        #expect(await repository.drainDeliveredEvents().turns.first?.status == .running)
        try consume(frame(5, [row(status: "canceled", preview: nil)]), &boundary, repository)
        state = await repository.drainDeliveredEvents()
        #expect(state.turns.first?.status == .completed)
        #expect(state.turns.first?.requestsAwaitingAnAnswer.isEmpty == true)
    }
    @Test func simultaneousThreadsAndSameThreadTurnsKeepTheirIdentities() async throws {
        var boundary = TraeEvidenceBoundary(); let repository = MonitoringRepository(policy: .explicit)
        try consume(frame(1, [], baseline: true), &boundary, repository)
        try consume(frame(2, [row(requests: [command()]), row(thread: 3, turn: 4, requests: [command(6)])]), &boundary, repository)
        #expect(await repository.drainDeliveredEvents().turns.count == 2)
        try consume(frame(3, [row(status: "completed")]), &boundary, repository)
        try consume(frame(4, [row(turn: 7, at: t0 + 20, preview: nil)], at: t0 + 20), &boundary, repository)
        let state = await repository.drainDeliveredEvents()
        let first = try #require(state.turns.first { $0.threadID == id(1) })
        #expect(first.turnID == id(7)); #expect(first.status == .running)
        #expect(first.requestsAwaitingAnAnswer.isEmpty)
        #expect(repository.messageReader.preview(forSession: id(1), inTurn: id(7)) == nil)
        #expect(state.turns.first { $0.threadID == id(3) }?.status == .approvalNeeded)
    }
    @Test func duplicateFramesAndOtherWindowsCannotReplaceTheOwner() async throws {
        var boundary = TraeEvidenceBoundary(); let repository = MonitoringRepository(policy: .explicit)
        try consume(frame(1, [], baseline: true), &boundary, repository)
        try consume(frame(2, [row(requests: [command()])]), &boundary, repository)
        try consume(frame(2, [row(status: "completed")]), &boundary, repository)
        try consume(frame(1, [row(status: "completed")], baseline: true), &boundary, repository, peer: "other")
        #expect(await repository.drainDeliveredEvents().turns.first?.status == .approvalNeeded)
    }
    @Test func malformedOrMissingFieldsDoNotClearKnownRequests() async throws {
        var boundary = TraeEvidenceBoundary(); let repository = MonitoringRepository(policy: .explicit)
        try consume(frame(1, [], baseline: true), &boundary, repository)
        try consume(frame(2, [row(requests: [command()])]), &boundary, repository)
        let bad = TraeFrame(type: "snapshot", schema: 1, version: "3.5.91", sequence: 3, baseline: false, observedAt: t0 + 3)
        #expect(throws: TraeBridgeError.self) { try consume(bad, &boundary, repository) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(TraeDisplayedTurn.self, from: Data("{}".utf8)) }
        #expect(await repository.drainDeliveredEvents().turns.first?.status == .approvalNeeded)
    }
    @Test func mismatchedVersionsAndSequenceGapsFailClosed() async throws {
        var boundary = TraeEvidenceBoundary(); let repository = MonitoringRepository(policy: .explicit)
        var bad = frame(1, [], baseline: true); bad.version = "3.5.92"
        #expect(throws: TraeBridgeError.self) { try consume(bad, &boundary, repository) }
        try consume(frame(1, [], baseline: true), &boundary, repository)
        #expect(throws: TraeBridgeError.self) { try consume(frame(3, [row()]), &boundary, repository) }
        #expect(await repository.drainDeliveredEvents().turns.isEmpty)
    }
    @Test func reconnectCorrectsOnlyPreviouslyObservedTurns() async throws {
        var boundary = TraeEvidenceBoundary(); let repository = MonitoringRepository(policy: .explicit)
        try consume(frame(1, [], baseline: true), &boundary, repository)
        try consume(frame(2, [row(requests: [command()])]), &boundary, repository)
        _ = await repository.drainDeliveredEvents()
        boundary.lost(peer: "window")
        try consume(frame(1, [row(status: "canceled"), row(thread: 3, turn: 4)], baseline: true, at: t0 + 20), &boundary, repository)
        let state = await repository.drainDeliveredEvents()
        #expect(state.turns.count == 1); #expect(state.turns.first?.status == .completed)
    }
    @Test func independentRequestCollectionsResolveOnlyMatchingProducer() async throws {
        var boundary = TraeEvidenceBoundary(); let repository = MonitoringRepository(policy: .explicit)
        try consume(frame(1, [], baseline: true), &boundary, repository)
        try consume(frame(2, [row(requests: [command(producer: "one"), command(6, producer: "two")])]), &boundary, repository)
        #expect(await repository.drainDeliveredEvents().turns.first?.requestsAwaitingAnAnswer.count == 2)
        try consume(frame(3, [row(requests: [command(6, producer: "two")])]), &boundary, repository)
        let requests = await repository.drainDeliveredEvents().turns.first?.requestsAwaitingAnAnswer
        #expect(requests?.count == 1); #expect(requests?.first?.id == "two:" + id(6))
    }
    @Test func structuredQuestionsKeepOptionsTextLimitsAndReadingOnlyNavigation() throws {
        let question = TraeDisplayedQuestion(id: "q-0", header: "Shape", text: "Which shapes?",
            options: [.init(id: "Circle", label: "Circle", description: "A round shape"), .init(id: "__other__", label: "Others", description: nil)],
            multiple: true, freeText: true, optional: false, maximumTextLength: 500)
        let note = TraeDisplayedQuestion(id: "q-short-answer", header: nil, text: "Additional information?",
            options: [], multiple: false, freeText: true, optional: true, maximumTextLength: 1000)
        let native = TraeDisplayedRequest(id: id(5), toolID: id(6), producer: "root", name: "AskUserQuestion",
            kind: "questions", command: nil, details: nil, questions: [question, note])
        try native.validate()
        let request = native.request()
        guard case let .questions(questions) = request.form else { Issue.record("Expected questions"); return }
        #expect(questions.count == 2); #expect(questions[0].allowsSeveralAnswers)
        #expect(questions[0].options[0].description == "A round shape")
        #expect(questions[0].readingHint?.contains("500") == true)
        #expect(questions[1].readingHint?.contains("Optional") == true)
        #expect(questions[1].readingHint?.contains("1000") == true)
        #expect(!request.canBeAnswered); #expect(request.answerHandle == nil)
    }
    @Test func settingsDescribeCompanionSetupRatherThanHooks() {
        let descriptor = ProductRegistry.descriptor(for: .trae)
        #expect(descriptor.setup.isConfigurable)
        #expect(descriptor.setup.managedHooks == nil)
        #expect(descriptor.setup.installedMessage.contains("when Trae’s windows next open"))
        #expect(descriptor.watches?.contains("3.5.91") == true)
        #expect(descriptor.notShown?.contains("SOLO") == true)
    }
    @Test func companionSettingsDistinguishInstallationFromConnectionAndVersion() {
        let descriptor = ProductRegistry.descriptor(for: .trae)
        let off = ProductSettingsCopy(descriptor: descriptor, setup: .notInstalled, availability: .setupRequired, diagnostic: nil)
        let active = ProductSettingsCopy(descriptor: descriptor, setup: .active, availability: .ready, diagnostic: nil)
        let incompatible = ProductSettingsCopy(descriptor: descriptor, setup: .reviewRequired, availability: .unsupportedVersion, diagnostic: nil)
        let waiting = ProductSettingsCopy(descriptor: descriptor, setup: .reviewRequired, availability: .disconnected, diagnostic: nil)
        // A companion Trae's manifest disagrees with reads the mismatched-registration recovery sentence.
        let stale = ProductSettingsCopy(descriptor: descriptor, setup: .repairRequired, availability: .setupRequired, diagnostic: nil)
        #expect(off.status == "Not set up")
        #expect(active.status == "Connected")
        #expect(incompatible.status == "Version unsupported")
        #expect(!waiting.status.contains("reopen"))
        #expect(stale.status == "Setup needs repair")
        #expect(!IntegrationSetupStatus.repairRequired.isIntegrationEnabled)
    }

    @Test func packageContainsOnlyObserverAndNavigationCode() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchline-trae-package-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Notchline/Products/Trae/Companion")
        let installation = TraeInstallation(directory: root, resources: sources)
        let archive = try installation.package(in: root)
        #expect(FileManager.default.fileExists(atPath: archive.path))
        let bridge = try String(contentsOf: root.appendingPathComponent("package/extension/bridge-v1.js"), encoding: .utf8)
        #expect(!bridge.contains("sendUserDecision")); #expect(!bridge.contains("ahaIpc.connect"))
        #expect(!bridge.contains("stopSession(")); #expect(!bridge.contains("submitChatMessage"))
        #expect(bridge.contains("switchToSession"))
    }
    private func recordedFrames() throws -> [TraeFrame] {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Trae/displayed-3.5.91.jsonl")
        return try Data(contentsOf: file).split(separator: 10).map { try JSONDecoder().decode(TraeFrame.self, from: Data($0)) }
    }

    @Test func capturedNativeTurnsSurviveReconnectWithoutHistoricalAdmission() async throws {
        let frames = try recordedFrames()
        var boundary = TraeEvidenceBoundary(); let repository = MonitoringRepository(policy: .explicit)
        var sawCommand = false, sawQuestions = false, sawCancellation = false
        for frame in frames {
            if frame.baseline == true && !boundary.observedThreadIDs.isEmpty { boundary.lost(peer: "window") }
            try consume(frame, &boundary, repository)
            let state = await repository.drainDeliveredEvents()
            for turn in state.turns {
                sawCommand = sawCommand || turn.status == .approvalNeeded
                sawQuestions = sawQuestions || turn.status == .inputNeeded
                sawCancellation = sawCancellation || (turn.turnID.hasSuffix("e01e") && turn.status == .completed)
                if turn.turnID.hasSuffix("dfcd") { Issue.record("The initial historical Turn was admitted") }
            }
        }
        #expect(sawCommand && sawQuestions && sawCancellation)
        let end = await repository.drainDeliveredEvents()
        #expect(end.turns.count == 2)
        #expect(end.turns.allSatisfy { $0.status == .completed && $0.requestsAwaitingAnAnswer.isEmpty })
        #expect(boundary.observedThreadIDs.count == 2)
    }

    @Test func anotherWindowsStaleBaselineCannotReopenAnEndedTurn() async throws {
        var boundary = TraeEvidenceBoundary(); let repository = MonitoringRepository(policy: .explicit)
        try consume(frame(1, [], baseline: true), &boundary, repository)
        try consume(frame(2, [row()]), &boundary, repository)
        try consume(frame(3, [row(status: "completed")]), &boundary, repository)
        _ = await repository.drainDeliveredEvents()
        boundary.lost(peer: "window")
        try consume(frame(1, [row(requests: [command()])], baseline: true), &boundary, repository, peer: "other")
        #expect(boundary.current[id(1)]?.status == "completed")
        #expect(await repository.drainDeliveredEvents().turns.first?.status == .completed)
        #expect(await repository.drainDeliveredEvents().turns.first?.requestsAwaitingAnAnswer.isEmpty == true)
    }

    @Test func scopeExclusionHidesNavigationWithoutInventingAnEnd() async throws {
        var boundary = TraeEvidenceBoundary(); let repository = MonitoringRepository(policy: .explicit)
        try consume(frame(1, [], baseline: true), &boundary, repository)
        try consume(frame(2, [row(requests: [command()])]), &boundary, repository)
        var excluded = frame(3, []); excluded.excluded = [id(1)]
        try consume(excluded, &boundary, repository)
        #expect(boundary.peer(for: id(1)) == nil)
        #expect(await repository.drainDeliveredEvents().turns.first?.status == .approvalNeeded)
        boundary.lost(peer: "window")
        #expect(boundary.observedThreadIDs == [id(1)])
    }

    @Test func registrationReadsTraesOwnManifestRatherThanARememberedBelief() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchline-trae-manifest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = root.appendingPathComponent("extensions.json")
        let installation = TraeInstallation(application: URL(fileURLWithPath: "/nonexistent/Trae.app"),
                                            directory: root, extensionsManifest: manifest)
        // Missing and unrelated manifests are absent; corruption is an unknown check.
        #expect(installation.registration == .absent)
        try Data("{".utf8).write(to: manifest)
        #expect(installation.registration == .unreadable)
        for value in ["[]", #"[{"identifier":{"id":"someone.else"},"version":"1.2.0"}]"#] {
            try Data(value.utf8).write(to: manifest); #expect(installation.registration == .absent)
        }
        try Data(#"[{"identifier":{"id":"notchline.trae-companion"},"version":"1.1.0"}]"#.utf8).write(to: manifest)
        #expect(installation.registration == .mismatched)
        // Trae's extension host lower-cases VSIX identifiers; the read tolerates any case.
        try Data(#"[{"identifier":{"id":"NOTCHLINE.TRAE-COMPANION"},"version":"1.2.1"}]"#.utf8).write(to: manifest)
        #expect(installation.registration == .mismatched, "a manifest entry alone cannot prove the package exists")
        let package = root.appendingPathComponent("notchline.trae-companion-1.2.1/package.json")
        try FileManager.default.createDirectory(at: package.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"publisher":"notchline","name":"trae-companion","version":"1.2.1"}"#.utf8).write(to: package)
        #expect(installation.registration == .current)
        try Data("{".utf8).write(to: package)
        #expect(installation.registration == .unreadable)
        try Data(#"{"publisher":"notchline","name":"trae-companion","version":"9.0.0"}"#.utf8).write(to: package)
        #expect(installation.registration == .mismatched)
        // Corruption is never an invitation to coerce or overwrite the product's manifest.
        try Data("{".utf8).write(to: manifest)
        await #expect(throws: (any Error).self) { try await installation.remove() }
        #expect(try String(contentsOf: manifest, encoding: .utf8) == "{")

    }

    @Test func removalFallsBackToEditingTraesManifestWhenTheCLIFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchline-trae-fallback-\(UUID().uuidString)")
        let extensionsDirectory = root.appendingPathComponent("extensions")
        try FileManager.default.createDirectory(at: extensionsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = extensionsDirectory.appendingPathComponent("extensions.json")
        // An unmodelled `metadata` field: removal must rewrite the manifest as loose JSON, not drop it.
        let companionFolder = extensionsDirectory.appendingPathComponent("notchline.trae-companion-1.2.1")
        let otherFolder = extensionsDirectory.appendingPathComponent("someone.else-9.9.9")
        try FileManager.default.createDirectory(at: companionFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherFolder, withIntermediateDirectories: true)
        try Data(#"""
        [
          {"identifier":{"id":"notchline.trae-companion"},"version":"1.2.1","relativeLocation":"notchline.trae-companion-1.2.1"},
          {"identifier":{"id":"someone.else"},"version":"9.9.9","relativeLocation":"someone.else-9.9.9","metadata":{"pinned":true}}
        ]
        """#.utf8).write(to: manifest)
        let installation = TraeInstallation(
            // Nonexistent, so the CLI branch fails and the fallback runs.
            application: URL(fileURLWithPath: "/nonexistent/Trae.app"),
            directory: root,
            extensionsManifest: manifest
        )
        try Data(#"{"publisher":"notchline","name":"trae-companion","version":"1.2.1"}"#.utf8)
            .write(to: companionFolder.appendingPathComponent("package.json"))
        #expect(installation.registration == .current)
        try await installation.remove()
        #expect(installation.registration == .absent)
        #expect(!FileManager.default.fileExists(atPath: companionFolder.path))
        #expect(FileManager.default.fileExists(atPath: otherFolder.path))
        let rewritten = try JSONSerialization.jsonObject(with: try Data(contentsOf: manifest)) as? [[String: Any]]
        #expect(rewritten?.count == 1)
        #expect((rewritten?.first?["identifier"] as? [String: Any])?["id"] as? String == "someone.else")
        #expect((rewritten?.first?["metadata"] as? [String: Any])?["pinned"] as? Bool == true)
    }

    @Test func removingAnAlreadyAbsentCompanionSucceedsWithoutInvokingTraesCLI() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchline-trae-remove-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Trae's CLI exits 1 for "is not installed"; removal treats that as done, or the switch never
        // turns off. The nonexistent app path proves the CLI is not invoked.
        let installation = TraeInstallation(
            application: URL(fileURLWithPath: "/nonexistent/Trae.app"),
            directory: root,
            extensionsManifest: root.appendingPathComponent("extensions.json")
        )
        try await installation.remove()
    }

    @Test func nativeRequestFormsFitTheActualReadingOnlyRow() throws {
        let requests = try recordedFrames().flatMap { $0.rows ?? [] }.flatMap(\.requests)
        let command = try #require(requests.first { $0.kind == "command" })
        let questions = try #require(requests.first { $0.kind == "questions" })
        let row = MonitoredSession(agent: .trae, threadID: id(1), turnID: id(2), projectName: "Trae acceptance",
            title: "Read the native request", preview: "NL-ACCEPT-PROGRESS", status: .inputNeeded,
            startedAt: Date(), requests: [questions.request(), command.request()])
        let store = MonitorStore(displays: [], initialSnapshot: AgentSnapshot(agent: .trae, availability: .ready,
            sessions: [row], quota: .noneReported, diagnostic: nil))
        store.toggleOpenRow(row)
        let width = PanelMetrics.requestBodyWidth + 2 * PanelMetrics.sessionRowPadding
        let output = ProcessInfo.processInfo.environment["NOTCHLINE_TRAE_FIGURES"]
        for index in 0..<4 {
            if index == 3 { store.stepRequest(1) }
            let height = try #require(store.openRowHeight)
            let view = OpenRow(session: row).environmentObject(store)
            let host = NSHostingView(rootView: view.frame(width: width))
            host.frame.size = NSSize(width: width, height: height); host.layoutSubtreeIfNeeded()
            #expect(abs(host.fittingSize.height - height) < 1)
            #expect(store.openAnswerRow == nil)
            if let output {
                try AnatomyFigureRenderer.png(view, size: CGSize(width: width, height: height),
                    to: URL(fileURLWithPath: output).appendingPathComponent("request-\(index).png"))
            }
            if index < 2 { store.goForwardAQuestion() }
        }
        if let output {
            let view = AppSettingsView().environmentObject(store)
            let host = NSHostingView(rootView: view); host.layoutSubtreeIfNeeded()
            try AnatomyFigureRenderer.png(view, size: host.fittingSize,
                to: URL(fileURLWithPath: output).appendingPathComponent("settings.png"))
        }
    }
}

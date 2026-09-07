import AppKit
import SwiftUI
import Testing
@testable import Notchline

struct OptionPresentationTests {
    @Test @MainActor
    func optionDrawingMatchesMeasurementAndEveryExpandedLineIsReachable() throws {
        let description = String(repeating: "Read every part of this description before deciding. ", count: 18) + "\nFinal paragraph."
        let options = [
            AgentQuestionOption(id: 7, label: String(repeating: "A complete title ", count: 10), description: description),
            AgentQuestionOption(id: 11, label: "Short option", description: nil),
            AgentQuestionOption(id: 23, label: "Another option", description: "A short description.")
        ]
        let request = AgentRequest(id: "layout", toolName: "AskUserQuestion", form: .questions([
            AgentQuestion(id: 0, header: "Approach", text: "Which approach should we take?", options: options, allowsSeveralAnswers: false)
        ]))
        let store = MonitorStore(displays: [], services: [], preferences: nil)
        for width: CGFloat in [320, PanelMetrics.requestBodyWidth] {
            for expanded: Set<Int> in [[], [7]] {
                let layout = try #require(RequestBodyLayout.laidOut(request, expandedOptions: expanded, width: width))
                let first = try #require(layout.optionLayouts.first)
                #expect(first.option.description == description)
                #expect(first.titleLines.joined() == options[0].label)
                #expect(first.canExpand)
                #expect(first.collapsedLines.count == 2)
                #expect(first.collapsedLines.last?.hasSuffix("…") == true)
                #expect(first.visibleDescription.count == (expanded.isEmpty ? 2 : first.descriptionLines.count))
                #expect(first.descriptionLines.last == "Final paragraph.")
                let host = NSHostingView(rootView: RequestBodyView(layout: layout).environmentObject(store).frame(width: width))
                host.setFrameSize(NSSize(width: width, height: layout.contentHeight))
                host.layoutSubtreeIfNeeded()
                #expect(abs(host.fittingSize.height - layout.contentHeight) < 0.5)
                #expect(layout.drawnHeight <= 300)
                #expect(layout.linesBelowTheFold(scrolledBy: max(0, layout.contentHeight - layout.drawnHeight)) == 0)
                if !expanded.isEmpty { #expect(layout.linesBelowTheFold(scrolledBy: 0) > 0) }
                let rowHeight = PanelMetrics.openRowFixedHeight + layout.drawnHeight
                #expect(PanelMetrics.sessionViewportHeight(liveRowCount: 3, openRowHeight: rowHeight) >= rowHeight)
            }
        }
    }

    @Test @MainActor
    func aReplacementRequestCannotInheritThePreviousAnswerOrDisclosure() async throws {
        func snapshot(_ id: String) -> AgentSnapshot {
            let request = AgentRequest(id: id, toolName: "AskUserQuestion", form: .questions([
                AgentQuestion(id: 0, header: nil, text: "Which approach?", options: [
                    AgentQuestionOption(id: 7, label: "Inspect first", description: String(repeating: "Read the complete explanation. ", count: 30))
                ], allowsSeveralAnswers: false)
            ]), replyTicket: 1)
            return AgentSnapshot(agent: .claudeCode, availability: .ready, sessions: [
                MonitoredSession(agent: .claudeCode, threadID: "same-thread", turnID: "turn", projectName: "notchline", title: "Question", preview: nil, status: .inputNeeded, startedAt: Date(), request: request)
            ], quota: .unavailable, diagnostic: nil)
        }
        let initial = snapshot("first-request")
        let store = MonitorStore(displays: [], services: [], initialSnapshot: initial, preferences: nil)
        store.toggleOpenRow(try #require(initial.sessions.first))
        let deadline = Date().addingTimeInterval(5)
        while !store.isAffirmativeArmed && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(store.isAffirmativeArmed)
        store.takeAnswer(.option(7))
        store.toggleOptionDescription(7)
        store.answerDraftChanged(to: "Use this answer instead")
        #expect(store.canSubmitCurrentAnswer)
        #expect(store.isOptionTicked(7))
        #expect(store.openRowBody?.optionLayouts.first?.isExpanded == true)
        let generation = store.answerDraftGeneration
        store.restageSpecimen([snapshot("second-request")])
        #expect(store.openSession?.request?.id == "second-request")
        #expect(store.answerDraft.isEmpty)
        #expect(!store.canSubmitCurrentAnswer)
        #expect(!store.isOptionTicked(7))
        #expect(store.openRowBody?.optionLayouts.first?.isExpanded == false)
        #expect(store.answerDraftGeneration > generation)
    }

    /// A tall open question is given the room the panel was sized for.
    ///
    /// §4.1: a question's body may take `300`, which puts its open row at
    /// `400` — past the `240` three closed rows are billed at — and the live
    /// viewport grows to fit that row. The window was sized from the metric
    /// while the list drew itself at the bare cap, so the panel stood open
    /// `160` taller than anything painted into it: the last option clipped
    /// under the footer, and a strip of empty panel below it. Both readings
    /// come off the store now, so there is one height rather than two.
    @Test @MainActor
    func aTallOpenQuestionIsGivenTheRoomThePanelWasSizedFor() throws {
        let description = String(
            repeating: "Read every part of this description before deciding. ",
            count: 18
        )
        let request = AgentRequest(id: "tall", toolName: "AskUserQuestion", form: .questions([
            AgentQuestion(id: 0, header: "Focus area", text: "Which area should I focus on next?", options: [
                AgentQuestionOption(id: 1, label: "UI work", description: description),
                AgentQuestionOption(id: 2, label: "Hook work", description: description),
                AgentQuestionOption(id: 3, label: "Performance work", description: description)
            ], allowsSeveralAnswers: false)
        ]))
        let snapshot = AgentSnapshot(agent: .claudeCode, availability: .ready, sessions: [
            MonitoredSession(agent: .claudeCode, threadID: "thread", turnID: "turn", projectName: "notchline", title: "Question", preview: nil, status: .inputNeeded, startedAt: Date(), request: request)
        ], quota: .unavailable, diagnostic: nil)
        let store = MonitorStore(displays: [], services: [], initialSnapshot: snapshot, preferences: nil)
        store.toggleOpenRow(try #require(snapshot.sessions.first))

        // The row is the tallest a question can make: the fixed heading and
        // answer footer, and a body at its own cap rather than the approval's.
        let row = try #require(store.openRowHeight)
        #expect(row == PanelMetrics.openRowFixedHeight + PanelMetrics.questionBodyMaximumHeight)
        #expect(row > PanelMetrics.sessionViewportCap)

        // The one open row is the whole of the list, and the list is given all
        // of it: nothing is left below the fold for a rail to offer.
        #expect(store.sessionListContentHeight == row)
        #expect(store.sessionViewportHeight == row)
        #expect(!(store.sessionListContentHeight > store.sessionViewportHeight))

        // And the panel is that room and its footer, with nothing unpainted.
        #expect(
            store.expandedContentHeight
                == store.sessionViewportHeight + store.expandedFooterHeight
        )

        // Laid out rather than taken from the metric: the metric was already
        // right when this broke, and only the drawn list disagreed with it.
        let host = NSHostingView(rootView: ActiveSessionList().environmentObject(store))
        host.layoutSubtreeIfNeeded()
        #expect(abs(host.fittingSize.height - row) < 0.5)
    }

}

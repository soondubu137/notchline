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

}

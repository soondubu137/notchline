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
            ]), answerHandle: AnswerHandle(ticket: 1))
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
        // of it: nothing is left below the fold for a rail to offer. **Plus
        // its block's heading** — the list is one block per product at every
        // count since 2026-09-09, and a heading is chrome that is never paid
        // for out of the row (`expanded-panel-v2.md` §4.3 rule 07), so it is
        // added to both sides rather than taken out of the row's own room.
        let headed = row + PanelMetrics.groupHeadingsHeight(count: 1)
        #expect(store.sessionListContentHeight == headed)
        #expect(store.sessionViewportHeight == headed)
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
        #expect(abs(host.fittingSize.height - headed) < 0.5)
    }

    /// The open row's body is laid out once per change, never once per read.
    ///
    /// **Every read used to be a full text layout**, and the panel is made of
    /// reads: the row's body, its position, its header and its accessibility
    /// text, the three heights the window is sized by
    /// (``MonitorStore/openRowHeight``,
    /// ``MonitorStore/sessionListContentHeight``,
    /// ``MonitorStore/sessionViewportHeight``), and
    /// ``MonitorStore/canSubmitCurrentAnswer`` on every control that reads it.
    /// Measured on Release on 2026-09-07, against one four-option question:
    /// **48** layouts to open the row, **26** for one option click, **24** over
    /// a second of scrolling the list past it, and **one per keystroke** — at
    /// `14 ms` each, which is the whole of why the row was slow.
    ///
    /// The two halves of that are pinned separately here. Reading lays out
    /// nothing, and neither does an answer: what a person ticks or types is not
    /// an input to the drawn lines, and only what changes them costs a layout.
    @Test @MainActor
    func theOpenRowsBodyIsLaidOutOncePerChangeRatherThanOncePerRead() async throws {
        let description = String(
            repeating: "Read every part of this description before deciding. ",
            count: 18
        )
        let request = AgentRequest(id: "cost", toolName: "AskUserQuestion", form: .questions([
            AgentQuestion(id: 0, header: "First", text: "Which approach should I take?", options: [
                AgentQuestionOption(id: 1, label: "Inspect first", description: description),
                AgentQuestionOption(id: 2, label: "Change it now", description: description)
            ], allowsSeveralAnswers: false),
            AgentQuestion(id: 1, header: "Second", text: "And where should it land?", options: [
                AgentQuestionOption(id: 1, label: "Here", description: description)
            ], allowsSeveralAnswers: false)
        ]), answerHandle: AnswerHandle(ticket: 1))
        let snapshot = AgentSnapshot(agent: .claudeCode, availability: .ready, sessions: [
            MonitoredSession(agent: .claudeCode, threadID: "thread", turnID: "turn", projectName: "notchline", title: "Question", preview: nil, status: .inputNeeded, startedAt: Date(), request: request)
        ], quota: .unavailable, diagnostic: nil)
        let store = MonitorStore(displays: [], services: [], initialSnapshot: snapshot, preferences: nil)
        store.toggleOpenRow(try #require(snapshot.sessions.first))
        // §6.3: nothing answers until the row has finished arriving.
        let deadline = Date().addingTimeInterval(5)
        while !store.isAffirmativeArmed && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.isAffirmativeArmed)
        _ = store.openRowBody

        // Everything the panel reads while drawing one pass, several times
        // over, is one layout's worth of work and no more.
        let afterOpening = store.bodyLayoutCount
        for _ in 0..<20 {
            _ = store.openRowBody
            _ = store.openRowBody?.position
            _ = store.openRowHeight
            _ = store.sessionListContentHeight
            _ = store.sessionViewportHeight
            _ = store.expandedContentHeight
            _ = store.questionHasASelection
            _ = store.canSubmitCurrentAnswer
        }
        #expect(store.bodyLayoutCount == afterOpening)

        // Nor does answering: a tick and a keystroke change what will be sent,
        // not the lines that are drawn.
        store.answerDraftChanged(to: "a typed answer")
        store.answerDraftChanged(to: "a typed answer of some length")
        store.takeAnswer(.option(1))
        #expect(store.isOptionTicked(1))
        #expect(store.bodyLayoutCount == afterOpening)

        // A disclosure and a step do change them, and cost exactly one each.
        store.toggleOptionDescription(1)
        #expect(store.openRowBody?.optionLayouts.first?.isExpanded == true)
        #expect(store.bodyLayoutCount == afterOpening + 1)
        store.takeAnswer(.affirmative)
        #expect(store.openRowBody?.position?.index == 2)
        #expect(store.bodyLayoutCount == afterOpening + 2)
        #expect(store.openSession?.request?.id == "cost")

        // And drawing the list really does read through all of that: one pass
        // over the whole panel, and still nothing laid out again.
        let drawn = store.bodyLayoutCount
        let host = NSHostingView(rootView: ActiveSessionList().environmentObject(store))
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height > 0)
        #expect(store.bodyLayoutCount == drawn)
    }

}

extension OptionPresentationTests {
    /// **The lit rectangle and the target are one rectangle** (§6.6). A card
    /// fills under the pointer over the whole of its `10` pt inset ring, and
    /// until 2026-09-07 it took a click only over its words: the button sat
    /// *inside* the padding rather than around it, and the disclosure was its
    /// sibling, so the ring and the whole of `Show more`'s line either side of
    /// two words answered the pointer and refused the click. Measured at
    /// `579 × 100`, that was `44%` of an expandable card's lit area — a click
    /// that did nothing, on the object the panel exists to let a person choose.
    ///
    /// **It is driven with real events at a real hosting view, because that is
    /// the only thing that measures it.** The hit order between a button, its
    /// padding and a control drawn over it is decided inside SwiftUI at
    /// dispatch time; the view tree reports nothing about it, and the same
    /// blindness once let a wheel catcher ship as a `.background` that took no
    /// events at all.
    @Test @MainActor
    func everyPointUnderAnOptionsFillTakesItsClick() async throws {
        let options = [
            AgentQuestionOption(id: 7, label: "Inspect first", description: String(repeating: "Read the complete explanation. ", count: 30)),
            AgentQuestionOption(id: 11, label: "Short option", description: nil)
        ]
        let request = AgentRequest(id: "targets", toolName: "AskUserQuestion", form: .questions([
            AgentQuestion(id: 0, header: "Approach", text: "Which approach?", options: options, allowsSeveralAnswers: false)
        ]), answerHandle: AnswerHandle(ticket: 1))
        let snapshot = AgentSnapshot(agent: .claudeCode, availability: .ready, sessions: [
            MonitoredSession(agent: .claudeCode, threadID: "thread", turnID: "turn", projectName: "notchline", title: "Question", preview: nil, status: .inputNeeded, startedAt: Date(), request: request)
        ], quota: .unavailable, diagnostic: nil)
        let store = MonitorStore(displays: [], services: [], initialSnapshot: snapshot, preferences: nil)
        store.toggleOpenRow(try #require(snapshot.sessions.first))
        let deadline = Date().addingTimeInterval(5)
        while !store.isAffirmativeArmed && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(store.isAffirmativeArmed)

        let width = PanelMetrics.requestBodyWidth
        let layout = try #require(RequestBodyLayout.laidOut(request, expandedOptions: [], width: width))
        let host = NSHostingView(rootView: RequestBodyView(layout: layout).environmentObject(store).frame(width: width))
        host.setFrameSize(NSSize(width: width, height: layout.contentHeight))
        // **Ordered in, and twenty thousand points off the left of every
        // screen.** A window that has never been ordered in has no window
        // number, and an `NSEvent` carrying that number is dropped before it
        // reaches anything — the whole card reads as dead and the test passes
        // or fails on nothing at all. This suite is hosted by the app itself
        // (`AppProcess.isHostingTests`), so where it is put matters: it is put
        // where no display reaches.
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: 0, width: width, height: layout.contentHeight), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()

        func click(_ point: CGPoint) {
            let inWindow = host.convert(point, to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(
                    with: type, location: inWindow, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
                ) else { continue }
                window.sendEvent(event)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.002))
        }

        /// The card each option was drawn on, taken from the list's own foot so
        /// the arithmetic is the layout's rather than this test's.
        var cards: [Int: CGRect] = [:]
        var top = layout.contentHeight
            - layout.optionLayouts.map(\.height).reduce(0, +)
            - CGFloat(layout.optionLayouts.count - 1) * PanelMetrics.optionSpacing
        for option in layout.optionLayouts {
            cards[option.id] = CGRect(x: 0, y: top, width: width, height: option.height)
            top += option.height + PanelMetrics.optionSpacing
        }
        let expandable = try #require(cards[7])
        let plain = try #require(cards[11])
        #expect(try #require(layout.optionLayouts.first).canExpand)

        func selects(_ id: Int, at point: CGPoint) -> Bool {
            store.takeAnswer(.option(id == 7 ? 11 : 7))
            click(point)
            return store.isOptionTicked(id)
        }

        // Two points in from each edge, because the fill's own boundary is
        // decided a fraction of a point either way and this is a test about
        // ten-point bands, not about the last pixel of a rounded corner.
        for (id, card) in [(7, expandable), (11, plain)] {
            for point in [
                CGPoint(x: card.minX + 2, y: card.minY + 2),
                CGPoint(x: card.maxX - 2, y: card.minY + 2),
                CGPoint(x: card.minX + 2, y: card.maxY - 2),
                CGPoint(x: card.maxX - 2, y: card.maxY - 2),
                CGPoint(x: card.midX, y: card.minY + 2),
                CGPoint(x: card.midX, y: card.maxY - 2),
                CGPoint(x: card.minX + 2, y: card.midY),
                CGPoint(x: card.maxX - 2, y: card.midY)
            ] {
                #expect(selects(id, at: point), "option \(id) refused a click at \(point) inside \(card)")
            }
        }

        // The disclosure's line is the card's everywhere but under its two
        // words, which are its own target and change nothing else.
        let disclosureY = expandable.maxY - PanelMetrics.optionInset - PanelMetrics.optionDisclosureHeight / 2
        #expect(selects(7, at: CGPoint(x: expandable.minX + 5, y: disclosureY)))
        #expect(selects(7, at: CGPoint(x: expandable.maxX - 5, y: disclosureY)))

        func isExpanded() -> Bool {
            store.openRowBody?.optionLayouts.first(where: { $0.id == 7 })?.isExpanded == true
        }
        store.takeAnswer(.option(11))
        #expect(!isExpanded())
        click(CGPoint(x: PanelMetrics.optionInset + PanelMetrics.optionHandleWidth + 5, y: disclosureY))
        #expect(isExpanded())
        #expect(store.isOptionTicked(11))
    }
}

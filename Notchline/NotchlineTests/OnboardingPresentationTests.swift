import AppKit
import SwiftUI
import Testing
@testable import Notchline

struct OnboardingPresentationTests {
    /// Each lesson's specimen is in the state that lesson is about.
    ///
    /// **The typed one has nothing ticked, and that is the correction**
    /// (`answer-in-notch.md` §5.4, 2026-09-07): it used to stage both options
    /// ticked *and* a draft, which taught the old rule that text outranked a
    /// selection. Under the rule that replaced it the same specimen would be a
    /// question answered by its ticks with a sentence beside them doing
    /// nothing — the opposite of what the page is for.
    @Test @MainActor
    func questionExamplesTeachSelectionAndTypedPriorityUsingTheRealDraft() throws {
        let examples = NotchSpecimen.openedSpecimens()
        for store in [examples.question, examples.multipleChoice, examples.typedAnswer] {
            #expect(!store.isWatching)
            #expect(store.openRowBody?.optionLayouts.first?.canExpand == true)
            #expect(store.openRowBody?.linesBelowTheFold(scrolledBy: 0) == 0)
            #expect(store.canSubmitCurrentAnswer)
            #expect(store.answerGround == .affirmative)
        }
        #expect(examples.question.openRowBody?.allowsSeveralAnswers == false)
        #expect(examples.question.isOptionTicked(0))
        #expect(!examples.question.isOptionTicked(1))
        #expect(examples.multipleChoice.openRowBody?.allowsSeveralAnswers == true)
        #expect(examples.multipleChoice.isOptionTicked(0))
        #expect(examples.multipleChoice.isOptionTicked(1))
        #expect(!examples.multipleChoice.questionUsesTypedAnswer)
        // The one the field answers: nothing chosen, so the words are it.
        #expect(!examples.typedAnswer.questionHasASelection)
        #expect(examples.typedAnswer.questionUsesTypedAnswer)
        #expect(examples.typedAnswer.answerDraft == "Use a compact summary with optional details.")
    }

    @Test @MainActor
    func everyTutorialExampleKeepsTheNavigationAtTheSameWindowSize() {
        let store = MonitorStore(displays: [], services: [], preferences: nil)
        for topic in AnswerLesson.allCases {
            for question in QuestionLesson.allCases {
                let host = NSHostingView(rootView: OnboardingView(page: .answer, answerLesson: topic, questionLesson: question).environmentObject(store))
                let size = NSSize(width: OnboardingLayout.width, height: OnboardingLayout.height)
                host.setFrameSize(size)
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize == size)
            }
        }
    }

    @Test @MainActor
    func switchingQuestionExamplesReplacesTheNativeAnswerField() throws {
        func field(in view: NSView) -> AnswerFieldView? {
            if let answer = view as? AnswerFieldView { return answer }
            return view.subviews.lazy.compactMap { field(in: $0) }.first
        }
        let host = NSHostingView(rootView: OpenQuestionAnatomy(lesson: .singleChoice))
        host.setFrameSize(NSSize(width: OnboardingLayout.cardWidth, height: 400))
        for example in [QuestionLesson.singleChoice, .typedAnswer, .multipleChoice, .typedAnswer] {
            host.rootView = OpenQuestionAnatomy(lesson: example)
            host.layoutSubtreeIfNeeded()
            let text = try #require(field(in: host)).string
            #expect(text == (example == .typedAnswer ? "Use a compact summary with optional details." : ""))
        }
    }

}

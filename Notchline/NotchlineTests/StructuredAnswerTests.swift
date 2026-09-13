import Foundation
import Testing
@testable import Notchline

/// Package 3 of `docs/product-generalisation-plan.md`: an answer travels as
/// what was done, and a request says what may be done with it.
struct StructuredAnswerTests {
    private func question(
        _ text: String = "Which database?",
        options: [String] = ["SQLite", "Postgres"],
        several: Bool = false,
        freeText: Bool = true,
        note: Bool = false,
        id: Int = 0
    ) -> AgentQuestion {
        AgentQuestion(
            id: id, header: nil, text: text,
            options: options.enumerated().map {
                AgentQuestionOption(id: $0.offset, label: $0.element, description: nil)
            },
            allowsSeveralAnswers: several, acceptsFreeText: freeText, acceptsNote: note
        )
    }

    /// The tool's own input, which the answers are merged back into.
    private let input = JSONValue.object(["questions": .array([])])

    /// The `answers` field Claude Code reads back, out of what was written.
    private func answers(in sent: Data?) throws -> [String: String] {
        let bytes = try #require(sent)
        let root = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let output = try #require(root["hookSpecificOutput"] as? [String: Any])
        let decision = try #require(output["decision"] as? [String: Any])
        let updated = try #require(decision["updatedInput"] as? [String: Any])
        return try #require(updated["answers"] as? [String: String])
    }

    /// A person typing a label and a person choosing it are two acts, told
    /// apart until the product's own field, which holds one string.
    @Test func aTypedLabelAndAChosenOptionAreDifferentAnswersSpelledAlike() throws {
        let asked = question()
        let chosen = AgentQuestionAnswer(question: asked, selectedOptionIDs: [1])
        let typed = AgentQuestionAnswer(question: asked, text: "Postgres")
        #expect(chosen != typed)
        #expect(chosen.selectedOptions == [asked.options[1]])
        #expect(typed.selectedOptions == [])

        let claude = ClaudeCodeRequestAnswering()
        let fromChoice = claude.hookOutput(for: .answers([chosen]), updating: input)
        #expect(fromChoice == claude.hookOutput(for: .answers([typed]), updating: input))
        #expect(try answers(in: fromChoice) == ["Which database?": "Postgres"])
    }

    /// An option labelled `A, B` is one option; `A` and `B` ticked are two.
    /// Claude Code's field is one string per question, so the two spell the
    /// same there by that product's own design and nowhere earlier.
    @Test func anOptionLabelledWithACommaIsNotTwoOptions() {
        let one = question(options: ["A, B", "C"], several: true)
        let two = question(options: ["A", "B"], several: true)
        let joinedLabel = AgentQuestionAnswer(question: one, selectedOptionIDs: [0])
        let both = AgentQuestionAnswer(question: two, selectedOptionIDs: [0, 1])
        #expect(joinedLabel.selectedOptions?.count == 1)
        #expect(both.selectedOptions?.count == 2)
        #expect(ClaudeCodeRequestAnswering.spelling(of: joinedLabel) == "A, B")
        #expect(ClaudeCodeRequestAnswering.spelling(of: both) == "A, B")
    }

    /// Two options wearing one label are two options, by position.
    @Test func twoOptionsWearingOneLabelAreToldApartByPosition() {
        let asked = question(options: ["Yes", "Yes"])
        let second = AgentQuestionAnswer(question: asked, selectedOptionIDs: [1])
        #expect(second.selectedOptions == [asked.options[1]])
        #expect(second != AgentQuestionAnswer(question: asked, selectedOptionIDs: [0]))
        #expect(ClaudeCodeRequestAnswering.spelling(of: second) == "Yes")
    }

    /// Two questions asked in the same words are two questions here, and one
    /// key in Claude Code's own `answers`, which its schema keys by text. The
    /// later answer wins there; that is the product's format, recorded rather
    /// than hidden behind a key the tool would not read.
    @Test func twoQuestionsAskedInTheSameWordsCollapseOnlyInTheNativeKey() throws {
        let first = question("Which?", options: ["A", "B"], id: 0)
        let second = question("Which?", options: ["C", "D"], id: 1)
        let answered: [AgentQuestionAnswer] = [
            AgentQuestionAnswer(question: first, selectedOptionIDs: [0]),
            AgentQuestionAnswer(question: second, selectedOptionIDs: [1])
        ]
        #expect(answered[0] != answered[1])
        #expect(answered.map { $0.selectedOptions?.first?.label } == ["A", "D"])
        let sent = ClaudeCodeRequestAnswering().hookOutput(for: .answers(answered), updating: input)
        #expect(try answers(in: sent) == ["Which?": "D"])
    }

    /// A product's own identifier is read where it sends one and stays apart
    /// from the position the surface draws, so an encoder that answers by
    /// identifier needs nothing beyond the answer it is handed.
    @Test func aNativeIdentifierIsReadAndKeptApartFromThePosition() throws {
        let toolInput = JSONValue.object(["questions": .array([
            .object([
                "id": .string("db"), "question": .string("Which database?"),
                "options": .array([.object(["label": .string("SQLite")])])
            ]),
            .object(["id": .number(7), "question": .string("Which host?")]),
            .object(["question": .string("Which region?")])
        ])])
        let read = try #require(AgentRequestReading.questions(in: toolInput))
        #expect(read.map(\.id) == [0, 1, 2])
        #expect(read.map(\.nativeID) == ["db", "7", nil])
        #expect(read.allSatisfy { !$0.acceptsNote && $0.acceptsFreeText })
        #expect(AgentRequestReading.questions(in: toolInput, acceptingNotes: true)?.allSatisfy(\.acceptsNote) == true)

        /// A product that answers by identifier: one line per question, the
        /// question's own id and its chosen options' positions.
        struct ByIdentifier: RequestAnswering {
            func hookOutput(for answer: AgentAnswer, updating input: JSONValue?) -> Data? {
                guard case let .answers(answered) = answer, answered.allSatisfy(\.fitsItsQuestion) else { return nil }
                return Data(answered.map { one in
                    "\(one.question.nativeID ?? "#\(one.question.id)")=" + (one.selectedOptionIDs.map(String.init).joined(separator: "+").nilIfEmpty ?? one.text ?? "")
                }.joined(separator: "\n").utf8)
            }
        }
        let sent = ByIdentifier().hookOutput(for: .answers([
            AgentQuestionAnswer(question: read[0], selectedOptionIDs: [0]),
            AgentQuestionAnswer(question: read[1], text: "Fly"),
            AgentQuestionAnswer(question: read[2], text: "eu")
        ]), updating: nil)
        #expect(sent.map { String(decoding: $0, as: UTF8.self) } == "db=0\n7=Fly\n#2=eu")
    }

    /// A question answered only by choosing draws no field, and refuses words
    /// at every layer that carries an answer.
    @Test func aChoicesOnlyQuestionTakesNoWords() {
        let asked = question(freeText: false)
        let request = AgentRequest(
            id: "q", toolName: "AskUserQuestion", form: .questions([asked]),
            answerHandle: AnswerHandle(ticket: 1)
        )
        #expect(request.canBeAnswered)
        #expect(request.answerRow()?.affirmative == "Submit")
        #expect(request.answerRow()?.placeholder == nil)
        #expect(!AgentQuestionAnswer(question: asked, text: "Other").fitsItsQuestion)
        #expect(AgentQuestionAnswer(question: asked, selectedOptionIDs: [0]).fitsItsQuestion)
        #expect(ClaudeCodeRequestAnswering().hookOutput(
            for: .answers([AgentQuestionAnswer(question: asked, text: "Other")]), updating: input
        ) == nil)
        // A question that takes words draws the field it always drew.
        let worded = AgentRequest(
            id: "q", toolName: "AskUserQuestion", form: .questions([question()]),
            answerHandle: AnswerHandle(ticket: 1)
        )
        #expect(worded.answerRow()?.placeholder == "your answer…")
    }

    /// An answer that does not fit its question is refused whole: a tick on an
    /// option the question no longer offers, two ticks on a single choice, a
    /// note where none may travel, or nothing at all. Half of it is not sent.
    @Test func anAnswerThatDoesNotFitItsQuestionIsRefusedWhole() {
        let asked = question()
        #expect(!AgentQuestionAnswer(question: asked, selectedOptionIDs: [7]).fitsItsQuestion)
        #expect(AgentQuestionAnswer(question: asked, selectedOptionIDs: [7]).selectedOptions == nil)
        #expect(!AgentQuestionAnswer(question: asked, selectedOptionIDs: [0, 1]).fitsItsQuestion)
        #expect(AgentQuestionAnswer(question: question(several: true), selectedOptionIDs: [0, 1]).fitsItsQuestion)
        #expect(!AgentQuestionAnswer(question: asked, text: "x", note: "n").fitsItsQuestion)
        #expect(AgentQuestionAnswer(question: question(note: true), text: "x", note: "n").fitsItsQuestion)
        #expect(!AgentQuestionAnswer(question: asked).fitsItsQuestion)
        #expect(!AgentQuestionAnswer(question: asked, text: "  \n").fitsItsQuestion)

        let fitting = AgentQuestionAnswer(question: asked, selectedOptionIDs: [0])
        let stale = AgentQuestionAnswer(question: question("Which host?", id: 1), selectedOptionIDs: [7])
        let claude = ClaudeCodeRequestAnswering()
        #expect(claude.hookOutput(for: .answers([fitting]), updating: input) != nil)
        #expect(claude.hookOutput(for: .answers([fitting, stale]), updating: input) == nil)
        #expect(claude.hookOutput(for: .answers([]), updating: input) != nil, "a set with nothing asked merges nothing")
    }

    /// A refusal takes words only where the connection was declared to carry
    /// them, and a request draws only the answers its connection accepts.
    @Test func aRefusalTakesWordsOnlyWhereTheConnectionDeclaredIt() {
        let silent = AnswerOperations(grant: true, refuse: true)
        let request = AgentRequest(
            id: "c", toolName: "Bash", form: .command("ls"),
            answerHandle: AnswerHandle(ticket: 1), operations: silent
        )
        #expect(request.canBeAnswered)
        #expect(request.answerRow()?.refusal == "Deny")
        #expect(request.answerRow()?.placeholder == nil)
        #expect(silent.permits(.refuse(nil)))
        #expect(!silent.permits(.refuse("write it elsewhere")))
        #expect(!silent.permits(.answers([])))
        #expect(AnswerOperations.decision.permits(.refuse("write it elsewhere")))
        #expect(AnswerOperations.decision.permits(.grant))
        #expect(!AnswerOperations.questionAnswers.permits(.grant))
        #expect(AnswerOperations.questionAnswers.permits(.answers([])))

        let grantOnly = AgentRequest(
            id: "c", toolName: "Bash", form: .command("ls"),
            answerHandle: AnswerHandle(ticket: 1), operations: AnswerOperations(grant: true)
        )
        #expect(grantOnly.answerRow()?.affirmative == "Approve")
        #expect(grantOnly.answerRow()?.refusal == nil)
        #expect(grantOnly.answerRow()?.placeholder == nil)
    }

    /// A form the connection cannot answer is read, whatever is held: a
    /// question over a decision-only channel, a decision over a
    /// questions-only one, and the form this app declines to draw.
    @Test func aFormTheConnectionCannotAnswerIsReadWhateverIsHeld() {
        let codexQuestion = AgentRequest(
            id: "q", toolName: "request_user_input", form: .questions([question()]),
            answerHandle: AnswerHandle(ticket: 1), operations: .decision
        )
        #expect(!codexQuestion.canBeAnswered)
        #expect(codexQuestion.answerRow() == nil)
        #expect(
            PanelMetrics.waitingMarkWord(for: .inputNeeded, canBeAnswered: codexQuestion.canBeAnswered)
                == PanelMetrics.waitingMarkReadWord
        )
        #expect(!AgentRequest(
            id: "c", toolName: "Bash", form: .command("ls"),
            answerHandle: AnswerHandle(ticket: 1), operations: .questionAnswers
        ).canBeAnswered)
        #expect(!AgentRequest(
            id: "e", toolName: "Elicitation", form: .unsupported,
            answerHandle: AnswerHandle(ticket: 1), operations: .decision
        ).canBeAnswered)
        // A request built with no declaration answers by its form, which is
        // what a body read off a `PreToolUse` carries until the event holding
        // the connection says otherwise.
        let undeclared = AgentRequest(id: "c", toolName: "Bash", form: .command("ls"))
        #expect(undeclared.operations == .decision)
        #expect(undeclared.answerable(on: AnswerHandle(ticket: 1)).canBeAnswered)
        #expect(!undeclared.answerable(on: AnswerHandle(ticket: 1), permitting: .readingOnly).canBeAnswered)
        // And the connection's declaration wins over the form's default when
        // the evidence carries one, not otherwise.
        let held = MonitoringEvidence(
            signal: .approvalWaitInferred, threadID: "t", observedAt: Date(),
            answerHandle: AnswerHandle(ticket: 2), answerOperations: .questionAnswers
        )
        #expect(undeclared.answerable(by: held).operations == .questionAnswers)
        let unheld = MonitoringEvidence(signal: .toolCallOpened, threadID: "t", observedAt: Date())
        #expect(undeclared.answerable(by: unheld).operations == .decision)
    }

    /// Each vocabulary declares what its held connection will act on, and the
    /// product that answers nothing declares nothing.
    @Test func theVocabulariesDeclareWhatTheirHeldConnectionAccepts() {
        let claude = ClaudeCodeHookVocabulary()
        let codex = CodexHookVocabulary()
        #expect(claude.answerOperations(forEvent: "PermissionRequest", toolName: "Bash") == .decision)
        #expect(claude.answerOperations(forEvent: "PermissionRequest", toolName: "ExitPlanMode") == .decision)
        #expect(claude.answerOperations(forEvent: "PermissionRequest", toolName: "AskUserQuestion") == .questionAnswers)
        #expect(claude.answerOperations(forEvent: "PreToolUse", toolName: "AskUserQuestion") == .readingOnly)
        #expect(codex.answerOperations(forEvent: "PermissionRequest", toolName: "request_user_input") == .decision)
        #expect(codex.answerOperations(forEvent: "PreToolUse", toolName: "request_permissions") == .readingOnly)
        #expect(AntigravityHookVocabulary().answerOperations(forEvent: "PermissionRequest", toolName: nil) == .readingOnly)
    }

    /// The boundary refuses an answer the connection was never declared for,
    /// before a byte is composed and without letting the connection go: the
    /// answer it does accept still travels afterwards.
    @Test func theBoundaryRefusesAnAnswerTheConnectionWasNotDeclaredFor() async throws {
        let root = URL(fileURLWithPath: "/tmp").appendingPathComponent("cin-ops-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = MonitoringRepository(
            paths: HookIntegrationPaths(
                supportDirectory: root.appendingPathComponent("AS"),
                hooksConfiguration: root.appendingPathComponent("settings.json"),
                agent: .claudeCode
            ),
            vocabulary: ClaudeCodeHookVocabulary()
        )
        let epoch = repository.observationEpoch
        func deliver(_ object: [String: Any], on descriptor: Int32? = nil) throws -> AgentHookListener.Disposition {
            repository.deliver(try JSONSerialization.data(withJSONObject: object), at: Date(), on: descriptor)
        }
        _ = try deliver(["hook_event_name": "UserPromptSubmit", "session_id": "s-1", "prompt_id": "t-1"])
        _ = try deliver([
            "hook_event_name": "PreToolUse", "session_id": "s-1", "prompt_id": "t-1",
            "tool_name": "Bash", "tool_use_id": "call-1", "tool_input": ["command": "ls"]
        ])
        let pair = try AnsweringSocketPair()
        defer { pair.closePeer() }
        #expect(try deliver([
            "hook_event_name": "PermissionRequest", "session_id": "s-1", "prompt_id": "t-1",
            "tool_name": "Bash", "tool_input": ["command": "ls"]
        ], on: pair.app) == .held)
        _ = epoch

        let waiting = await repository.drainDeliveredEvents()
        let request = try #require(waiting.turns.first?.requestAwaitingAnAnswer)
        #expect(request.operations == .decision)
        #expect(request.canBeAnswered)
        let handle = try #require(request.answerHandle)

        // A question's answers down a decision's connection: refused, nothing
        // written, the connection still held and the row still answerable.
        let answered = await repository.answer(
            .answers([AgentQuestionAnswer(question: question(), selectedOptionIDs: [0])]), on: handle
        )
        #expect(answered == .unsupportedOperation)
        #expect(!pair.peerHasInput())
        #expect(await repository.observedState().turns.first?.requestAwaitingAnAnswer?.canBeAnswered == true)

        // The decision it was declared for travels.
        #expect(await repository.answer(.refuse("not now"), on: handle) == .sent)
        #expect(pair.peerHasInput())
        let sent = try #require(pair.readFromPeer())
        #expect(String(decoding: sent, as: UTF8.self).contains(#""behavior":"deny""#))
        #expect(await repository.observedState().turns.first?.requestAwaitingAnAnswer?.canBeAnswered == false)
        // And the spent handle answers nothing more.
        #expect(await repository.answer(.grant, on: handle) == .expired(.notHeld))
    }
}

/// One connected pair of descriptors: the app's end is handed to the
/// repository, the peer's end is what the product would read.
struct AnsweringSocketPair {
    let app: Int32
    let peer: Int32

    init() throws {
        var descriptors: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
            throw POSIXError(.EIO)
        }
        app = descriptors[0]
        peer = descriptors[1]
    }

    /// Whether anything has arrived for the product, or its end has closed.
    func peerHasInput() -> Bool {
        var descriptor = pollfd(fd: peer, events: Int16(POLLIN), revents: 0)
        return poll(&descriptor, 1, 0) > 0
    }

    func readFromPeer() -> Data? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = Darwin.read(peer, &buffer, buffer.count)
        return count > 0 ? Data(buffer[0..<count]) : nil
    }

    func closePeer() {
        Darwin.close(peer)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

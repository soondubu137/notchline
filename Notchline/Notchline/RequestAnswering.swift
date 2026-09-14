import Foundation

/// What a person may do with one request over the connection held for it. Checked by the row
/// (``AgentRequest/answerRow(showing:)``), the store and ``HookReplyRegistry``. Not a support
/// level; per-question constraints live on ``AgentQuestion``.
nonisolated struct AnswerOperations: Sendable, Equatable, Hashable {
    var grant = false
    var refuse = false
    var refusalCarriesText = false
    var answersQuestions = false

    nonisolated init(
        grant: Bool = false,
        refuse: Bool = false,
        refusalCarriesText: Bool = false,
        answersQuestions: Bool = false
    ) {
        self.grant = grant
        self.refuse = refuse
        self.refusalCarriesText = refusalCarriesText
        self.answersQuestions = answersQuestions
    }

    /// Not `none`, which on an optional parameter is `nil`.
    nonisolated static let readingOnly = AnswerOperations()
    /// Both products' `PermissionRequest`.
    nonisolated static let decision = AnswerOperations(
        grant: true, refuse: true, refusalCarriesText: true
    )
    /// Claude Code's `AskUserQuestion`.
    nonisolated static let questionAnswers = AnswerOperations(answersQuestions: true)

    nonisolated var isEmpty: Bool { self == .readingOnly }
    nonisolated var refusalTakesText: Bool { refuse && refusalCarriesText }

    /// The shape only; whether answers fit their questions is the encoder's check.
    nonisolated func permits(_ answer: AgentAnswer) -> Bool {
        switch answer {
        case .grant:
            grant
        case let .refuse(message):
            refuse && (message == nil || refusalCarriesText)
        case .answers:
            answersQuestions
        }
    }
}

/// What sending an answer proved, and no more (`docs/product-generalisation-plan.md` package
/// 4). The Hooks channel's best is ``sent``. No outcome moves the row's status
/// (`answer-in-notch.md` §8.1) or allows a resend.
nonisolated enum AnswerOutcome: Sendable, Equatable {
    /// The product acknowledged acting. No shipping channel can prove this yet.
    case accepted
    /// Written and closed; nothing proves the product read it.
    case sent
    /// No connection held, nothing written. The row stays, saying `Read`.
    case expired(AnswerExpiry)
    /// Only a channel that hears back can report this.
    case rejected(String)
    /// Nothing was written and the handle is not spent.
    case unsupportedOperation
    /// May or may not have arrived. The handle is spent: never send it twice.
    case uncertain

    /// Whether the answer is known to have left this app whole.
    nonisolated var answerArrived: Bool {
        switch self {
        case .accepted, .sent: true
        case .expired, .rejected, .unsupportedOperation, .uncertain: false
        }
    }
}

nonisolated enum AnswerExpiry: Sendable, Equatable {
    /// Answered in the product's own window, or the product gave up waiting.
    case peerGone
    /// The product's answer window ran out while the connection was held.
    case timedOut
    /// Already spent, minted by another issuer, or released when its wait cleared.
    case notHeld
}

/// What a person answered, in product-neutral terms (`answer-in-notch.md` §7, §8).
nonisolated enum AgentAnswer: Sendable, Equatable {
    case grant
    /// Claude Code 2.1.261 delivers the message to the model as the refused tool's error.
    case refuse(String?)
    /// In the order asked.
    case answers([AgentQuestionAnswer])
}

/// One question answered, as option identities or typed text, never pre-joined labels; the
/// product's encoder spells it (``ClaudeCodeRequestAnswering``).
nonisolated struct AgentQuestionAnswer: Sendable, Equatable {
    let question: AgentQuestion
    /// By ``AgentQuestionOption/id``, in the product's order; empty where the person typed.
    let selectedOptionIDs: [Int]
    /// Where nothing was chosen (§5.4).
    let text: String?
    let note: String?

    nonisolated init(
        question: AgentQuestion,
        selectedOptionIDs: [Int] = [],
        text: String? = nil,
        note: String? = nil
    ) {
        self.question = question
        self.selectedOptionIDs = selectedOptionIDs
        self.text = text
        self.note = note
    }

    /// Nil where any chosen position is not one this question offers.
    nonisolated var selectedOptions: [AgentQuestionOption]? {
        question.options(at: selectedOptionIDs)
    }

    /// Offered options, one unless several are allowed, words or a note only where taken, and not
    /// empty. Every encoder checks this, so a stale tick is refused rather than guessed.
    nonisolated var fitsItsQuestion: Bool {
        guard let chosen = selectedOptions else { return false }
        if chosen.count > 1, !question.allowsSeveralAnswers { return false }
        let typed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !typed.isEmpty, !question.acceptsFreeText { return false }
        if let note, !note.isEmpty, !question.acceptsNote { return false }
        return !chosen.isEmpty || !typed.isEmpty
    }
}

/// The submission control the return key takes, or an option-selection intent. Approval text
/// moves the ground to refusal; questions stay affirmative.
nonisolated enum AnswerGround: Sendable, Equatable {
    /// `Approve`, `Accept`, or a question's `Next` or `Submit`.
    case affirmative
    /// `Deny` or `Send it back`: the answer that carries the text.
    case refusal
    case option(Int)

    /// Decided by the request's shape, never the laid-out body (14 ms per keystroke, Release).
    nonisolated static func `where`(
        _ request: AgentRequest?,
        carriesText: Bool
    ) -> AnswerGround {
        guard let shape = request?.answerRow() else { return .affirmative }
        if shape.refusal != nil {
            return carriesText ? .refusal : .affirmative
        }
        // Selection is draft state, never a default answer or a submission.
        return .affirmative
    }
}

/// A key that reached the panel because nothing holds the caret: focus, not an empty field,
/// decides (`answer-in-notch.md` §9.2).
nonisolated enum PanelKey: Sendable, Equatable {
    /// `⏎`: takes the answer the white ground is on.
    case submit
    /// `1`–`4`: the option at that position.
    case option(Int)
    /// `←` and `→`: previous or next question.
    case step(Int)
}

/// Unsent input for one row: lives as long as the row, survives collapsing, never written to
/// disk (`answer-in-notch.md` §10).
nonisolated struct AnswerProgress: Sendable, Equatable {
    /// The question showing (§5.3).
    var questionIndex: Int = 0
    /// The frontier (§5.7): `→` may only return to a question already reached; `Next` reaches a
    /// new one.
    var furthestQuestionReached: Int = 0
    /// Drafts by question position, kept on the way past (§5.7) so going back shows the answer.
    private var perQuestion: [Int: Draft] = [:]
    /// Stripped of its connection (``AgentRequest/asked``); a replacement with the same id and a
    /// different body starts empty.
    var request: AgentRequest?

    /// One question's unsent state; the text replaces ticks and expanded options (§5.4).
    nonisolated struct Draft: Sendable, Equatable {
        /// A refusal's reason, or a question's answer.
        var text: String = ""
        /// Ticked options (§5.5).
        var ticked: Set<Int> = []
        var expandedOptions: Set<Int> = []
    }

    nonisolated init(request: AgentRequest? = nil) {
        self.request = request
    }

    nonisolated func draft(forQuestion index: Int) -> Draft {
        perQuestion[index] ?? Draft()
    }

    /// A form that is not a question is a set of one at `0`, so it uses this accessor too.
    var showing: Draft {
        get { draft(forQuestion: questionIndex) }
        set { perQuestion[questionIndex] = newValue }
    }

    var draft: String {
        get { showing.text }
        set { showing.text = newValue }
    }

    var ticked: Set<Int> {
        get { showing.ticked }
        set { showing.ticked = newValue }
    }

    var expandedOptions: Set<Int> {
        get { showing.expandedOptions }
        set { showing.expandedOptions = newValue }
    }
}

/// A row's preview line once an answer has left it (§8 states 02 and 03), in the preview's
/// own ink: there is no failure ink.
nonisolated struct AnswerNotice: Sendable, Equatable {
    let text: String
    /// The notice stands until the preview says something newer; no clock needed.
    let previewWhenWritten: String?
}

/// How one product spells an answer on the hook output it awaits: the write half of
/// ``AgentHookVocabulary``. `nil` is real: Codex reserves `updatedInput` and fails the hook
/// closed on it (`answer-in-notch.md` §11 rule 06). `interrupt` is never written.
nonisolated protocol RequestAnswering: Sendable {
    /// The bytes to write, or `nil` where this product will not accept the answer.
    ///
    /// - Parameter input: the request's `tool_input`, into which question answers are merged.
    nonisolated func hookOutput(
        for answer: AgentAnswer,
        updating input: JSONValue?
    ) -> Data?
}

/// The `hookSpecificOutput` envelope, identical on both products.
nonisolated enum AgentHookOutput {
    nonisolated static func encode(
        eventName: String,
        fields: [String: JSONValue]
    ) -> Data? {
        var output = fields
        output["hookEventName"] = .string(eventName)
        let encoder = JSONEncoder()
        // Sorted so tests can compare output to a literal.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(
            JSONValue.object(["hookSpecificOutput": .object(output)])
        )
    }
}

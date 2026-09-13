import Foundation

/// What a person may do with one request over the connection held for it.
///
/// **Capability data about one request, declared where the connection is
/// held.** The vocabulary that holds a `PermissionRequest` open says what the
/// product will act on down it — a decision on both products, a question's
/// answers on Claude Code only — and every layer that carries an answer checks
/// it: the row offers only what is here (``AgentRequest/answerRow(showing:)``),
/// the store sends only what is here, and the boundary writes only what is
/// here (``HookReplyRegistry``). It is not a support level and ranks nothing;
/// `docs/product-support.md` §3 is where the coverage is stated.
///
/// A question's own constraints — its options, whether several may be taken,
/// whether words are an answer, whether a note may travel beside one — live on
/// the question (``AgentQuestion``), because they differ per question and this
/// does not.
nonisolated struct AnswerOperations: Sendable, Equatable, Hashable {
    /// Grant the request as it was asked.
    var grant = false
    /// Refuse it.
    var refuse = false
    /// Whether a refusal may carry what to do instead.
    var refusalCarriesText = false
    /// Answer the questions it asks, each within its own constraints.
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

    /// Nothing may be done here: the request is read here and answered in
    /// the product. Not spelled `none`, which on an optional parameter is
    /// Swift's `nil` and silently something else.
    nonisolated static let readingOnly = AnswerOperations()
    /// A decision, with a reason where it is a refusal — both products'
    /// `PermissionRequest`.
    nonisolated static let decision = AnswerOperations(
        grant: true, refuse: true, refusalCarriesText: true
    )
    /// The answers to a question set — Claude Code's `AskUserQuestion`.
    nonisolated static let questionAnswers = AnswerOperations(answersQuestions: true)

    nonisolated var isEmpty: Bool { self == .readingOnly }
    /// Whether a refusal both exists and takes words.
    nonisolated var refusalTakesText: Bool { refuse && refusalCarriesText }

    /// Whether this answer is one of the things the connection accepts.
    ///
    /// The shape only: whether a question's answers fit their questions is
    /// the encoder's to check, since it has the questions in hand.
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

/// What sending an answer proved, and no more than it proved.
///
/// **A boolean collapsed six facts into two words** (`docs/product-generalisation-plan.md`
/// package 4): a socket write that succeeded, a product that acknowledged
/// acting, a connection whose peer had already gone, a product that refused,
/// an operation the channel never carried, and a write that may or may not
/// have arrived all had to be `true` or `false`, and the row then said
/// *the product stopped waiting* for every one of the false ones. Each case
/// here names what the channel can honestly claim; a channel must never
/// report a stronger one than it can prove.
///
/// **The Hooks channel's best is ``sent``.** A hook's stdout is written to
/// and closed; nothing comes back to say the product read it. Measured, both
/// products act on what arrives there (`answer-in-notch.md` §14.2), but that
/// is a measurement about the products and not an acknowledgement on this
/// channel, so it is not ``accepted``.
///
/// No outcome moves the row's status: native evidence alone does that
/// (`answer-in-notch.md` §8.1), and no outcome lets an answer be sent again
/// on its own -- an ``uncertain`` write in particular must not be retried by
/// anything but a channel that can prove the retry is idempotent, and none
/// shipping can.
nonisolated enum AnswerOutcome: Sendable, Equatable {
    /// The product acknowledged acting on the answer. No shipping channel
    /// can prove this yet; it exists so that one which can is not made to
    /// say ``sent``.
    case accepted
    /// Every byte was written to the channel and the channel closed. Nothing
    /// proves the product read them; measured, it does.
    case sent
    /// The channel no longer holds a connection for this handle, so nothing
    /// was written. The row stays what it is, and says `Read`.
    case expired(AnswerExpiry)
    /// The product refused the answer and said why. Only a channel that
    /// hears back can report this.
    case rejected(String)
    /// The channel does not carry this operation for this request. Nothing
    /// was written and the handle is not spent -- the request may still be
    /// answered with what the channel does carry.
    case unsupportedOperation
    /// Some or none of the answer may have reached the product and nothing
    /// says which. The handle is spent: an answer that may have landed must
    /// not be sent twice.
    case uncertain

    /// Whether the answer is known to have left this app whole.
    nonisolated var answerArrived: Bool {
        switch self {
        case .accepted, .sent: true
        case .expired, .rejected, .unsupportedOperation, .uncertain: false
        }
    }
}

/// Why a channel had nothing to write an answer to.
nonisolated enum AnswerExpiry: Sendable, Equatable {
    /// The other end went away before the write: the product was answered
    /// in its own window and closed the hook process, or gave up waiting.
    case peerGone
    /// The window the product registered for an answer ran out while the
    /// connection was still held; the product has moved on without one.
    case timedOut
    /// The handle names nothing this channel holds: already spent, minted by
    /// another issuer, or released when the wait it belonged to cleared.
    case notHeld
}

/// What a person answered, in words no product owns.
///
/// The same shape on both products, because the *question* is the same on both
/// — what differs is which of these each will act on, and that is the
/// provider's business rather than the surface's.
///
/// Designed in [`answer-in-notch.md`](../../docs/answer-in-notch.md) §7 and §8.
nonisolated enum AgentAnswer: Sendable, Equatable {
    /// Grant it, and say nothing else.
    case grant
    /// Refuse it, carrying what to do instead where the person said so.
    ///
    /// The message is not a comment: measured against Claude Code 2.1.261 on
    /// 2026-09-05, it reaches the model as the refused tool's own error, so it
    /// is the difference between "no" and "no, write it there instead".
    case refuse(String?)
    /// The answers to a question set, in the order it was asked.
    case answers([AgentQuestionAnswer])
}

/// One question out of a set, answered.
///
/// **Typed, so that nothing is lost between the tick and the wire.** This
/// used to be the question's text and one string, with the chosen labels
/// already joined by `", "` — which made an option labelled `A, B` the same
/// answer as `A` and `B` both ticked, two options wearing one label the same
/// answer as each other, and a person typing a label the same answer as a
/// person choosing it. The store now hands over what was done: which options,
/// by their identity in the set, or what was typed. The product's encoder
/// performs the final conversion, in its own schema and with the question in
/// hand (``ClaudeCodeRequestAnswering``), so the join lives with the product
/// whose format it is.
nonisolated struct AgentQuestionAnswer: Sendable, Equatable {
    /// The question as it was asked: its position, its words, its options and
    /// its constraints, so an encoder needs nothing beside this.
    let question: AgentQuestion
    /// The options chosen, by their ``AgentQuestionOption/id``, in the order
    /// the product listed them. Empty where the person typed instead.
    let selectedOptionIDs: [Int]
    /// The person's own words, where nothing was chosen (§5.4).
    let text: String?
    /// A note against this one question, where the person added one.
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

    /// The options chosen, in the product's order; nil where any chosen
    /// position is not one this question offers.
    nonisolated var selectedOptions: [AgentQuestionOption]? {
        question.options(at: selectedOptionIDs)
    }

    /// Whether this answer fits its question: chosen options it offers, one
    /// of them unless several are allowed, words only where words are taken,
    /// a note only where one may travel, and something rather than nothing.
    ///
    /// The one check every encoder makes before composing anything, so a
    /// stale tick or a word on a choices-only question is refused rather than
    /// sent as a guess.
    nonisolated var fitsItsQuestion: Bool {
        guard let chosen = selectedOptions else { return false }
        if chosen.count > 1, !question.allowsSeveralAnswers { return false }
        let typed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !typed.isEmpty, !question.acceptsFreeText { return false }
        if let note, !note.isEmpty, !question.acceptsNote { return false }
        return !chosen.isEmpty || !typed.isEmpty
    }
}

/// The submission control the return key takes, or an option-selection intent.
/// Approval text moves the ground to refusal. Questions keep it on the
/// affirmative; their selected options are separate draft state until
/// submission.
nonisolated enum AnswerGround: Sendable, Equatable {
    /// `Approve`, `Accept`, or a question's `Next` or `Submit`.
    case affirmative
    /// `Deny` or `Send it back` — the answer that carries the text.
    case refusal
    /// One option of a question, by its identity in the payload.
    case option(Int)

    /// Questions keep the affirmative as the default; approvals carry text on
    /// refusal.
    ///
    /// **It takes the request and not the laid-out body**, and it never read
    /// one: the ground is decided by the shape the request asks in, which
    /// ``AgentRequest/answerRow(showing:)`` answers without measuring a
    /// character. The discarded `showing:` parameter it used to declare was
    /// filled in by ``MonitorStore/refreshAnswerGround()`` with
    /// ``MonitorStore/openRowBody``, so every keystroke ran a full text layout
    /// of the whole request body — `14 ms`, measured on Release — to hand it to
    /// a parameter spelled `_`.
    nonisolated static func `where`(
        _ request: AgentRequest?,
        carriesText: Bool
    ) -> AnswerGround {
        guard let shape = request?.answerRow() else { return .affirmative }
        if shape.refusal != nil {
            return carriesText ? .refusal : .affirmative
        }
        // Questions always answer through the affirmative. Selection is draft
        // state, not a default answer and never an act of submission.
        return .affirmative
    }
}

/// A key that reached the panel because nothing in it holds the caret.
///
/// **The condition is focus, not emptiness** (`answer-in-notch.md` §9.2). The
/// digits and the arrows used to be offered to the panel out of the field's own
/// `keyDown` and taken only while the field was empty, which is a rule about a
/// *string* standing in for a rule about *where the caret is* — and it broke in
/// exactly the case it was invented for: a person who clicked into the field to
/// type an answer beginning `1.` selected an option instead, and could not move
/// the caret with `←`. So the field keeps every key it holds while it holds the
/// caret, and these three are what the panel answers to when it does not.
nonisolated enum PanelKey: Sendable, Equatable {
    /// `⏎`: takes the answer the white ground is on.
    case submit
    /// `1`–`4`: the option at that position in the question showing.
    case option(Int)
    /// `←` and `→`: one question of the set, backwards or forwards.
    case step(Int)
}

/// What a person has put into one row and not yet sent.
///
/// Kept for the row's lifetime and no longer (`answer-in-notch.md` §10):
/// collapsing a row sends nothing and keeps what was typed, so reopening
/// resumes rather than starting again — and when the row goes, this goes with
/// it. It is never written to disk, like every other part of a request.
nonisolated struct AnswerProgress: Sendable, Equatable {
    /// Which question of a set the body is showing, from the top (§5.3).
    var questionIndex: Int = 0
    /// The furthest question of the set this row has drawn (§5.7).
    ///
    /// **The frontier, not a count of answers.** A set is walked forward by
    /// answering and backward by asking, so this is what tells `→` apart from
    /// `Next`: `→` may return to a question already reached and can never reach
    /// a new one, because reaching a new one is the whole of what `Next` means.
    var furthestQuestionReached: Int = 0
    /// What has been put into each question of the set, by position.
    ///
    /// **Kept per question rather than cleared on the way past** (§5.7).
    /// Advancing used to empty the field, the ticks and the expanded
    /// descriptions and record the answer as a string, which made the answer
    /// unrecoverable as *state*: coming back could only have offered an empty
    /// question wearing the number of one that had been answered. So the
    /// answer stops being a snapshot taken on the way past and becomes what
    /// the draft says at the moment the set leaves — which is the same value
    /// while nobody goes back, and the newer of two when somebody does.
    ///
    /// **A set is answered one question at a time and sent once** — `⏎` on
    /// question two draws question three and sends nothing — which is what
    /// makes the count on the caption line worth drawing: without it, an answer
    /// that appears to do nothing looks like a failure.
    private var perQuestion: [Int: Draft] = [:]
    /// The request these drafts answer, stripped of its connection
    /// (``AgentRequest/asked``): a replacement wearing the same id and another
    /// body starts empty, because a tick taken on one question set is not an
    /// answer to a different one.
    var request: AgentRequest?

    /// One question's own three pieces of unsent state.
    ///
    /// All three belong to a question rather than to the row, which is why they
    /// travel together: the ticks are answers to *this* question, the expanded
    /// descriptions are this question's options opened, and the text is what
    /// would replace both (§5.4).
    nonisolated struct Draft: Sendable, Equatable {
        /// The field's own text: a refusal's reason, or a question's answer.
        var text: String = ""
        /// Which options are ticked on this question (§5.5).
        var ticked: Set<Int> = []
        var expandedOptions: Set<Int> = []
    }

    nonisolated init(request: AgentRequest? = nil) {
        self.request = request
    }

    /// What was put into one question of the set, whether or not it answers it.
    nonisolated func draft(forQuestion index: Int) -> Draft {
        perQuestion[index] ?? Draft()
    }

    /// The question showing now, which is the only one anything draws.
    ///
    /// A form that is not a question is a set of one living at `0`, so a
    /// refusal's note goes through exactly this accessor and no form needs a
    /// second path.
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

/// What one row's preview line says once an answer has left it.
///
/// §8's states 02 and 03 in one object: *landed* and *not delivered* are both a
/// row that went back to `80` and said one thing on the line it already draws.
/// The ink is the preview's own — this app has no failure ink, and inventing
/// one for a transport error would make it louder than a Turn that genuinely
/// failed.
nonisolated struct AnswerNotice: Sendable, Equatable {
    let text: String
    /// What the row's preview said when this was written.
    ///
    /// The notice stands until the product says something newer, and this is how
    /// *newer* is recognised without a clock: the app's own sentence is the last
    /// word only until the Turn it answered produces one of its own.
    let previewWhenWritten: String?
}

/// How one product spells an answer on the hook output it is waiting for.
///
/// The write half of ``AgentHookVocabulary``, kept as a type of its own because
/// it is a different kind of knowledge: that one says what an arriving event
/// *means*, and this says what this product will *act on*. Both are per product
/// and neither is per surface — the panel hands over an ``AgentAnswer`` and
/// never sees a key name.
///
/// **`nil` is a real answer and the reason this is a protocol at all.** A
/// question is answerable on Claude Code, whose `allow` carries `updatedInput`,
/// and not on Codex, which documents that field *reserved* and fails the hook
/// closed if it is present. So one provider returns bytes where the other
/// returns nothing, and the row says what that row can do
/// ([`answer-in-notch.md`](../../docs/answer-in-notch.md) §11 rule 06).
///
/// `interrupt` is never written by either. On Codex it fails the hook closed;
/// on Claude Code it ends the Turn, which this app has never done.
nonisolated protocol RequestAnswering: Sendable {
    /// The bytes to write on the held connection, or `nil` where this product
    /// will not accept this answer.
    ///
    /// - Parameter input: the `tool_input` the request arrived with, needed
    ///   only to answer a question: the answers are delivered by handing the
    ///   tool back its **own** input with them merged in, so the tool then runs
    ///   and returns them rather than being refused.
    nonisolated func hookOutput(
        for answer: AgentAnswer,
        updating input: JSONValue?
    ) -> Data?
}

/// Claude Code's `PermissionRequest` output, including the half only it has.
///
/// Read from the CLI's own hook-output validation help on 2026-09-05 (2.1.261)
/// and then measured against it in a pty-driven session: an `allow` written six
/// seconds after the product had raised its own dialogue dismissed that
/// dialogue and let the tool run, and a `deny` with a `message` produced
/// `Denied by PermissionRequest hook` with the message delivered to the model
/// as the tool's error.
nonisolated struct ClaudeCodeRequestAnswering: RequestAnswering {
    /// The field `AskUserQuestion` reads its answers out of.
    ///
    /// Its own input schema describes it as *"User answers collected by the
    /// permission component"*, keyed by question text — so writing it back
    /// through `updatedInput` is the designed path rather than a trick, and the
    /// tool returns those answers instead of being blocked.
    static let answersKey = "answers"
    /// The per-question notes field beside it.
    static let annotationsKey = "annotations"

    nonisolated func hookOutput(
        for answer: AgentAnswer,
        updating input: JSONValue?
    ) -> Data? {
        switch answer {
        case .grant:
            return Self.encode(["behavior": .string("allow")])
        case let .refuse(message):
            return Self.encode(
                message.map { ["behavior": .string("deny"), "message": .string($0)] }
                    ?? ["behavior": .string("deny")]
            )
        case let .answers(answers):
            // Refusing to answer rather than answering into an input this app
            // did not see: `updatedInput` *replaces* the tool's input, so
            // sending a fabricated one would drop every field the tool was
            // called with.
            guard case let .object(fields)? = input else { return nil }
            // And refusing an answer that does not fit its question -- a tick
            // naming an option the question no longer offers, words on a
            // question that takes none -- rather than sending the part that
            // did fit: half an answer is a different answer.
            var spelled: [(String, String)] = []
            for answered in answers {
                guard answered.fitsItsQuestion, let text = Self.spelling(of: answered) else {
                    return nil
                }
                spelled.append((answered.question.text, text))
            }
            var updated = fields
            // **Keyed by the question's text, because that is this product's
            // own schema** -- `answers` is described as keyed by question text,
            // and the tool reads it back that way. So two questions asked in
            // the same words collapse to one key here, the later answer
            // winning: a limitation of the product's format, recorded rather
            // than papered over by inventing a key the tool would not read.
            updated[Self.answersKey] = .object(
                Dictionary(
                    spelled.map { ($0.0, JSONValue.string($0.1)) },
                    uniquingKeysWith: { _, last in last }
                )
            )
            let notes = answers.compactMap { answered -> (String, JSONValue)? in
                guard let note = answered.note, !note.isEmpty else { return nil }
                return (answered.question.text, .object(["notes": .string(note)]))
            }
            if !notes.isEmpty {
                updated[Self.annotationsKey] = .object(
                    Dictionary(notes, uniquingKeysWith: { _, last in last })
                )
            }
            return Self.encode([
                "behavior": .string("allow"),
                "updatedInput": .object(updated)
            ])
        }
    }

    /// One answer as this product's `answers` field spells it: the chosen
    /// labels joined with `", "` in the product's own order (§5.5), or the
    /// person's words where nothing was chosen (§5.4).
    ///
    /// **The join is this product's and lives here.** It is what the tool
    /// reads -- one string per question -- so an option labelled `A, B` and
    /// the pair `A` and `B` spell the same here by the product's own design;
    /// they are told apart everywhere before this line.
    nonisolated static func spelling(of answered: AgentQuestionAnswer) -> String? {
        guard let chosen = answered.selectedOptions else { return nil }
        if !chosen.isEmpty {
            return chosen.map(\.label).joined(separator: ", ")
        }
        let typed = answered.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return typed.isEmpty ? nil : typed
    }

    private static func encode(_ decision: [String: JSONValue]) -> Data? {
        AgentHookOutput.encode(
            eventName: "PermissionRequest",
            fields: ["decision": .object(decision)]
        )
    }
}

/// Codex's `permission-request.command.output`, which is the approval half only.
///
/// Read from `0.151.x`'s own schema: `hookSpecificOutput.decision` takes
/// `behavior` and `message`, and `interrupt`, `updatedInput` and
/// `updatedPermissions` are documented **reserved** — a `PermissionRequest`
/// hook *fails closed* if any of them is present. So a question is read on this
/// product and answered in it, and that is a fact about this product rather
/// than a deferral (§11 rule 06).
nonisolated struct CodexRequestAnswering: RequestAnswering {
    nonisolated func hookOutput(
        for answer: AgentAnswer,
        updating input: JSONValue?
    ) -> Data? {
        switch answer {
        case .grant:
            return Self.encode(["behavior": .string("allow")])
        case let .refuse(message):
            return Self.encode(
                message.map { ["behavior": .string("deny"), "message": .string($0)] }
                    ?? ["behavior": .string("deny")]
            )
        case .answers:
            // Not a gap to fill in later: sending `updatedInput` here does not
            // fail to answer, it fails the hook *closed*, which is worse than
            // saying nothing at all.
            return nil
        }
    }

    private static func encode(_ decision: [String: JSONValue]) -> Data? {
        AgentHookOutput.encode(
            eventName: "PermissionRequest",
            fields: ["decision": .object(decision)]
        )
    }
}

/// The envelope both products read a decision out of.
///
/// Identical on both — `hookSpecificOutput`, with the event named inside it —
/// so it is written once. What differs is only what may go in `fields`.
nonisolated enum AgentHookOutput {
    nonisolated static func encode(
        eventName: String,
        fields: [String: JSONValue]
    ) -> Data? {
        var output = fields
        output["hookEventName"] = .string(eventName)
        let encoder = JSONEncoder()
        // Sorted so that what this app writes is reproducible, which is what
        // makes a test able to compare it to a literal.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(
            JSONValue.object(["hookSpecificOutput": .object(output)])
        )
    }
}

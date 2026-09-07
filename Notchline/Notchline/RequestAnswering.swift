import Foundation

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
nonisolated struct AgentQuestionAnswer: Sendable, Equatable {
    /// The question as the product asked it, which is the key its own tool
    /// input is keyed by.
    let question: String
    /// What the person chose, or typed.
    let answer: String
    /// A note against this one question, where the person added one.
    let note: String?

    nonisolated init(question: String, answer: String, note: String? = nil) {
        self.question = question
        self.answer = answer
        self.note = note
    }
}

/// The submission control the return key takes, or an option-selection intent.
/// Approval text moves the ground to refusal. Questions keep it on Send;
/// their selected options are separate draft state until submission.
nonisolated enum AnswerGround: Sendable, Equatable {
    /// `Approve`, `Accept`, or a question's `Send`.
    case affirmative
    /// `Deny` or `Send it back` — the answer that carries the text.
    case refusal
    /// One option of a question, by its identity in the payload.
    case option(Int)

    /// Questions keep Send as the default; approvals carry text on refusal.
    nonisolated static func `where`(
        _ request: AgentRequest?,
        showing _: RequestBodyLayout? = nil,
        carriesText: Bool
    ) -> AnswerGround {
        guard let shape = request?.answerRow else { return .affirmative }
        if shape.refusal != nil {
            return carriesText ? .refusal : .affirmative
        }
        // Questions always submit through Send. Selection is draft state,
        // not a default answer and never an act of submission.
        return .affirmative
    }
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
    /// `Send`: `→` may return to a question already reached and can never reach
    /// a new one, because reaching a new one is the whole of what `Send` means.
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
    var requestID: String?

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

    nonisolated init(requestID: String? = nil) {
        self.requestID = requestID
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
            var updated = fields
            updated[Self.answersKey] = .object(
                Dictionary(
                    answers.map { ($0.question, JSONValue.string($0.answer)) },
                    uniquingKeysWith: { _, last in last }
                )
            )
            let notes = answers.compactMap { answered -> (String, JSONValue)? in
                guard let note = answered.note, !note.isEmpty else { return nil }
                return (answered.question, .object(["notes": .string(note)]))
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

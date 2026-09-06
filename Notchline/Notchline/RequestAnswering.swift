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

/// Which of a row's answers the white ground is on — and so which one `⏎`
/// takes.
///
/// **One value names both**, because they are the same thing: `answer-in-notch.md`
/// §6.1 is that the ground *is* the state, with no second selection model
/// underneath and no default-button concept beside it. So a click reports which
/// answer it landed on in the same words the ground reports where it is, and
/// ``MonitorStore/takeAnswer(_:)`` cannot tell the two apart — which is §6.6:
/// a click takes the answer it lands on whether or not the ground is there.
nonisolated enum AnswerGround: Sendable, Equatable {
    /// `Approve`, `Accept`, or a question's `Send`.
    case affirmative
    /// `Deny` or `Send it back` — the answer that carries the text.
    case refusal
    /// One option of a question, by its position in the list.
    case option(Int)

    /// Where the ground stands on this request, given whether anything has been
    /// typed.
    ///
    /// §6: it begins on the affirmative — or on the first option a question
    /// offers — and typing moves it to the answer that carries text, which is
    /// the refusal where the form has one and `Send` where it does not. With
    /// several answers allowed it starts on `Send` and never leaves, because the
    /// brightest object must not stop being what `⏎` does on the one form where
    /// a person is most likely to press it twice (§5.5).
    nonisolated static func `where`(
        _ request: AgentRequest?,
        showing body: RequestBodyLayout? = nil,
        carriesText: Bool
    ) -> AnswerGround {
        guard let shape = request?.answerRow else { return .affirmative }
        if shape.refusal != nil {
            return carriesText ? .refusal : .affirmative
        }
        // A question, whose one control carries the text — so typing moves the
        // ground onto it rather than away, and with it there is nowhere else
        // for the ground to be.
        guard !carriesText, let body, !body.options.isEmpty,
              !body.allowsSeveralAnswers else { return .affirmative }
        return .option(body.options[0].id)
    }
}

/// What a person has put into one row and not yet sent.
///
/// Kept for the row's lifetime and no longer (`answer-in-notch.md` §10):
/// collapsing a row sends nothing and keeps what was typed, so reopening
/// resumes rather than starting again — and when the row goes, this goes with
/// it. It is never written to disk, like every other part of a request.
nonisolated struct AnswerProgress: Sendable, Equatable {
    /// The field's own text: a refusal's reason, or a question's answer.
    var draft: String = ""
    /// Which question of a set the body is showing, from the top (§5.3).
    var questionIndex: Int = 0
    /// What has been answered so far, by position in the set.
    ///
    /// **A set is answered one question at a time and sent once** — `⏎` on
    /// question two draws question three and sends nothing — so this is what
    /// makes the count on the caption line worth drawing: without it, an answer
    /// that appears to do nothing looks like a failure.
    var answers: [Int: AgentQuestionAnswer] = [:]
    /// Which options are ticked on the question showing now (§5.5).
    ///
    /// Cleared with the field as the next question is drawn, because both
    /// belong to the question that was on screen rather than to the row.
    var ticked: Set<Int> = []
    /// Where an arrow key put the white ground, where one has (§6, §9.3).
    ///
    /// **`nil` means derived**, which is what it is until somebody moves it:
    /// the ground begins on the affirmative, or on the first option a question
    /// offers, and typing moves it to the answer that carries text. The arrows
    /// are the second force, and this is the whole of what they add — one
    /// optional value that, while it is set, is what the ground is. Typing
    /// clears it, so the two forces cannot disagree: the more recent act wins,
    /// and deleting the text puts the ground back where the form says it
    /// begins.
    var ground: AnswerGround?
}

/// One arrow, as the panel reads it.
///
/// Named rather than passed as a key code because what the four mean depends on
/// what is open (§6.2), and that decision belongs to the store rather than to
/// the view that felt the keystroke.
nonisolated enum PanelArrow: Sendable, Equatable {
    case up, down, left, right
}

/// How far the arrows have asked the open row's body to move, in lines.
///
/// **A running total rather than one press's delta, and that is a correction
/// made by measuring** (2026-09-06, Release). It was a delta with a serial
/// beside it, on the reasoning that two `↓` presses are the same delta and
/// would otherwise coalesce into one change. They coalesce anyway: SwiftUI
/// compares this value once per render pass, and four presses inside one pass
/// are one change — so four arrows moved the body a single line, and the count
/// under the fold fell from `+54` to `+53`. A total cannot lose the presses in
/// between, because the body applies **the difference from the total it last
/// saw** rather than whatever it was handed.
nonisolated struct BodyScrollNudge: Sendable, Equatable {
    /// Lines below the top the arrows have asked for, since this row opened.
    /// Negative is up, and it is clamped by the body against its own travel.
    var lines: CGFloat = 0
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

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

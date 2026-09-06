import Foundation

/// What one agent is asking a person, in the shapes a row can draw.
///
/// **A value, not a schema.** Everything the surface needs was decided inside
/// ``HookEventRepository``'s actor, at the moment the wait opened and while the
/// vocabulary, the event name and the tool name were all still in hand. The
/// panel receives a request it can only render, which is the UI-stays-passive
/// invariant (`AGENTS.md` §6) applied to the one payload this app had never
/// carried.
///
/// Deliberately **not `Codable`**: hook payloads never touch disk (ADR 0015),
/// and a type that cannot be encoded cannot be persisted by accident.
///
/// Designed in [`docs/answer-in-notch.md`](../../docs/answer-in-notch.md) §2.1,
/// which enumerates the four drawn forms and the one this app declines.
nonisolated struct AgentRequest: Identifiable, Sendable, Equatable {
    /// The wait this belongs to, as the product spelled it.
    ///
    /// On a `PermissionRequest` that is the **borrowed** id of the call still
    /// open, because neither product puts a `tool_use_id` on that event
    /// (measured on both, 2026-08-23). It is what the open row is keyed by, and
    /// what an answer will have to name when there is a way to send one.
    let id: String
    /// The tool as the product named it.
    ///
    /// For the accessible name (§13.3) and for naming the destination of a form
    /// this app declines to draw (§2.2). **Never drawn as a label on the body**:
    /// §4.6 is that this app does not annotate what it was handed.
    let toolName: String?
    let form: Form

    nonisolated enum Form: Sendable, Equatable {
        /// A command to grant — an ordinary approval on either product. §2.1
        /// form 01.
        case command(String)
        /// A document to accept — a plan, and anything else that hands over
        /// prose. §2.1 form 02.
        case document(String)
        /// A question with options, one to four of them. §2.1 form 03.
        case questions([AgentQuestion])
        /// A question with none, answered in the person's own words. §2.1 form
        /// 04.
        case question(String)
        /// A form this app declines to draw, carrying no body at all. §2.2.
        ///
        /// **Empty on purpose, and not a parse failure.** A parse failure is
        /// `nil` — no request, and the row opens nothing. This is a decision:
        /// an `Elicitation`'s fields are a third-party MCP server's own, chosen
        /// at run time, of arbitrary shape and validation, and a half-rendered
        /// form is a wrong answer submitted confidently. The row says where to
        /// answer it instead.
        case unsupported

        /// A short name for the projection, which compares forms and never
        /// bodies.
        nonisolated var name: String {
            switch self {
            case .command: "command"
            case .document: "document"
            case .questions: "questions"
            case .question: "question"
            case .unsupported: "unsupported"
            }
        }
    }

    /// Which of §4.2's two settings the body is drawn in.
    ///
    /// **Derived rather than stored.** §4.2 is that the setting is decided by
    /// which payload the request came from and *never* by how long it is — the
    /// recessed ground exists to mark machine text, so putting prose on it would
    /// make the mark mean nothing. A stored setting is one that could be set
    /// wrong; this one cannot be, because the case already carries the answer.
    nonisolated var setting: Setting {
        if case .command = form { return .machineText }
        return .prose
    }

    nonisolated enum Setting: Sendable, Equatable {
        /// SF Mono on the recessed ground: a string a machine will execute.
        case machineText
        /// The content width, no ground: sentences a person is meant to read.
        case prose
    }
}

/// One question out of a set, in the order the product asked them.
nonisolated struct AgentQuestion: Identifiable, Sendable, Equatable {
    /// Position in the set, which is what §5.2 draws as `2/3`.
    ///
    /// The payload carries no identifier of its own, and position is the
    /// identity the surface uses anyway: 63% of questions arrive in a call
    /// carrying more than one (measured across 86 questions in 55 calls), which
    /// is what makes the count a drawn element rather than an edge case.
    let id: Int
    /// At most sixteen characters, which the product's schema promises and this
    /// enforces.
    ///
    /// §5.2 leans on that bound to keep the header and the count clear of the
    /// badge on the caption line. A layout promise another product's schema
    /// makes is one this app keeps rather than assumes. `nil` where the product
    /// sends none — Codex does not.
    let header: String?
    let text: String
    let options: [AgentQuestionOption]
    /// Whether several options may be taken at once.
    ///
    /// §5.5: with this, the white ground starts on `Send` and never leaves it,
    /// because the brightest object on the row must not stop being what `⏎`
    /// does on the one form where a person is most likely to press it twice.
    let allowsSeveralAnswers: Bool
}

/// One labelled answer a question offers.
nonisolated struct AgentQuestionOption: Identifiable, Sendable, Equatable {
    let id: Int
    /// The product's own word for this answer, never a paraphrase of it.
    ///
    /// §2.3: nothing on this surface invents a word that a person's answer will
    /// be recorded under.
    let label: String
    let description: String?
}

/// Reads one product's `tool_input` into the shapes a row can draw.
///
/// Product-free on purpose: *which* payload becomes which form is a fact about
/// a product and lives on its ``AgentHookVocabulary``, while *how* a question
/// set or a command body is read out of one is the same work on both sides.
nonisolated enum AgentRequestReading {
    /// One request's arguments, exactly as they arrived, rendered once.
    ///
    /// **The whole object, not a field picked out of it.** Every tool has
    /// different arguments — `Bash` has `command`, `Edit` has three paths and
    /// two strings, an MCP tool has whatever it likes — so reading
    /// `tool_input.command` would cover `Bash` and leave every other approval
    /// with an empty body, and "the longest string" is a heuristic, which is the
    /// kind of thing §4.6 exists to refuse. `answer-in-notch.md` §14.4 narrows
    /// the PRD's ban to *the payload of a request the product is already blocked
    /// on* — the payload, not a field of it.
    ///
    /// **`sortedKeys` is load-bearing and not cosmetic.** ``JSONValue/object``
    /// is a Swift `Dictionary`, whose iteration order differs between instances
    /// holding equal values — so an unsorted rendering would produce a different
    /// string for the same request on a later read, and
    /// ``HookEventRepository/renderedProjection()`` would see a change and wake
    /// the panel for it.
    ///
    /// Rendered here, once, inside the actor, and never in a row builder: rows
    /// are rebuilt on every refresh, and a `String` made once is then shared by
    /// copy-on-write, so comparing two rebuilt rows compares a pointer rather
    /// than 128 KiB.
    nonisolated static func arguments(of toolInput: JSONValue) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(toolInput),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    /// The named string inside an object, where there is one worth drawing.
    ///
    /// Empty is treated as absent, so a caller can fall back to the arguments
    /// rather than open a row onto a blank body.
    nonisolated static func text(_ key: String, in toolInput: JSONValue) -> String? {
        guard case let .object(fields) = toolInput,
              case let .string(value)? = fields[key],
              !value.isEmpty else { return nil }
        return value
    }

    /// The question set inside a `tool_input`, where it holds one.
    ///
    /// **The count and the order are the product's**, and nothing here trims
    /// either: §2.3 forbids the surface omitting a product's own words, and the
    /// byte bound in ``HookPayloadDistiller/maximumRequestBytes`` already caps
    /// the whole set. A question with no text is dropped, because it is nothing
    /// a row could draw; a question with no options is kept, because that is
    /// form 04 and the field is the whole answer.
    nonisolated static func questions(in toolInput: JSONValue) -> [AgentQuestion]? {
        guard case let .object(fields) = toolInput,
              case let .array(raw)? = fields["questions"],
              !raw.isEmpty else { return nil }

        let questions = raw.enumerated().compactMap { index, entry -> AgentQuestion? in
            guard case let .object(question) = entry,
                  case let .string(text)? = question["question"],
                  !text.isEmpty else { return nil }
            var header: String?
            if case let .string(value)? = question["header"], !value.isEmpty {
                header = String(value.prefix(maximumHeaderCharacters))
            }
            var allowsSeveralAnswers = false
            if case let .bool(value)? = question["multiSelect"] {
                allowsSeveralAnswers = value
            }
            var options: [AgentQuestionOption] = []
            if case let .array(rawOptions)? = question["options"] {
                options = rawOptions.enumerated().compactMap { position, option in
                    guard case let .object(fields) = option,
                          case let .string(label)? = fields["label"],
                          !label.isEmpty else { return nil }
                    var description: String?
                    if case let .string(value)? = fields["description"], !value.isEmpty {
                        description = value
                    }
                    return AgentQuestionOption(
                        id: position,
                        label: label,
                        description: description
                    )
                }
            }
            return AgentQuestion(
                id: index,
                header: header,
                text: text,
                options: options,
                allowsSeveralAnswers: allowsSeveralAnswers
            )
        }
        return questions.isEmpty ? nil : questions
    }

    /// What a header may weigh, which is what the product's own schema promises.
    nonisolated static let maximumHeaderCharacters = 16
}

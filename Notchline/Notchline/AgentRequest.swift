import AppKit
import Foundation

/// What one agent is asking a person, in the shapes a row can draw.
///
/// **A value, not a schema.** The native boundary projects the body before submitting typed evidence.
/// ``MonitoringRepository`` attaches the established correlation identity
/// and handle while reducing the wait; it parses no native request schema. The
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

    /// The single line a row shows for a question it cannot offer to answer.
    ///
    /// **The last question, not the first.** Codex emits an async question set
    /// as one assistant message *per question* (measured 2026-09-06 in a
    /// rollout, and the same split appears in Desktop's own projection), so the
    /// newest thing the turn has said is the last of them — which is the rule
    /// the row's preview already follows for every other sentence. A set is
    /// never joined into one line here: inventing punctuation between two of a
    /// product's own sentences is exactly what §2.3 refuses.
    ///
    /// `nil` for every other form, including a question set that is answerable:
    /// that one is drawn in full by an opened row and needs no summary line.
    nonisolated var lastQuestionAsked: String? {
        guard case let .questions(questions) = form else { return nil }
        return questions.last?.text
    }
    /// Approval arguments projected at the hook boundary, before flattening.
    /// Empty for prose/questions and for manually constructed plain commands.
    /// The command string remains the compatibility reading, never parsed by UI.
    let argumentFields: [ApprovalArgument]
    /// The persistent rules the product offered to write alongside a grant.
    ///
    /// Empty on every request that was offered none -- which is the product's
    /// own signal to withhold the row, not a gap: an ask carries either
    /// `suggestions` or `suppressAlwaysAllowRule` and never both, so a
    /// suggestion this app cannot see is one its own dialogue does not draw
    /// either. Empty on Codex always, which reserves the field.
    ///
    /// **Read here and drawn nowhere**, on purpose. `answer-in-notch.md` §6.5
    /// declines to offer *Always* from this surface, and that decision stands;
    /// what changed on 2026-09-06 is only that the fact reaches the row instead
    /// of being stepped over one layer before the decode. Whoever draws it will
    /// find the rule already parsed and the connection already held.
    let offeredRules: [PermissionRuleOffer]
    /// Whether the product offered to stop asking this in future.
    ///
    /// The one reading this surface takes from ``offeredRules`` today. It is
    /// deliberately not on ``answerRow``: a row that named a third answer it
    /// cannot send would be §11 rule 03's promise made quietly.
    nonisolated var offersPersistentRule: Bool { !offeredRules.isEmpty }
    /// Whether this request can be answered **here**, or only read here.
    ///
    /// `answer-in-notch.md` §11 rule 06: the two halves are per product and per
    /// shape, and *the row says what that row can do* — a row that can only be
    /// read beside one that can be answered is an ordinary mixed list, not a
    /// special case. So this is a fact about one request rather than a setting,
    /// and the vocabulary that read the request is what knows it.
    ///
    /// **Derived from ``answerHandle``, and it cannot be set independently.** A
    /// request is answerable exactly when a connection is being held open for
    /// it — not when its product *could* accept an answer, and not when its
    /// status happens to be `Approval needed`. Offering an affirmative the app
    /// cannot deliver is a promise made quietly (§11 rule 03), so the one fact
    /// that decides it is the one that would carry the answer.
    nonisolated var canBeAnswered: Bool { answerHandle != nil && form.permits(operations) }

    /// What an answer on the connection held for this request may do
    /// (``AnswerOperations``).
    ///
    /// **Declared by the boundary that holds the connection, never inferred
    /// from the form.** A question drawn over a Codex `PermissionRequest`
    /// connection is a readable form on a channel that accepts only a
    /// decision, and before this existed it was offered `Submit` and then
    /// reported *not sent*. Now the form and the operations have to agree
    /// before anything is offered: ``canBeAnswered`` asks ``Form/permits(_:)``,
    /// and a form the channel cannot answer is read here and answered in the
    /// product, whatever is held. A request built without a declaration takes
    /// its form's own operations, which is what every fixture and every
    /// request read off a `PreToolUse` — which holds no connection — carries
    /// until the event that does hold one says otherwise.
    let operations: AnswerOperations

    /// The way back to the connection this request arrived on, while it is
    /// still held (``AnswerHandle``).
    ///
    /// `nil` on every request that reached this app down a connection already
    /// closed — every product surface whose approval does not arrive as the
    /// registered answering event, and every request at all until the row can
    /// send one. The row then says `Read`, which is true.
    ///
    /// Not drawn and not compared by the change projection: it is how an answer
    /// finds its way back, and the surface's business with it is only whether
    /// there is one.
    let answerHandle: AnswerHandle?

    nonisolated init(
        id: String,
        toolName: String?,
        form: Form,
        argumentFields: [ApprovalArgument] = [],
        offeredRules: [PermissionRuleOffer] = [],
        answerHandle: AnswerHandle? = nil,
        operations: AnswerOperations? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.form = form
        self.argumentFields = argumentFields
        self.offeredRules = offeredRules
        self.answerHandle = answerHandle
        self.operations = operations ?? form.defaultOperations
    }

    /// The same request, filed against the connection it arrived on.
    ///
    /// The vocabulary reads the request out of the payload and knows nothing
    /// about descriptors; the reducer holds both. Rebuilding here rather than
    /// making the field `var` keeps the type a value the surface can only read.
    ///
    /// Keeps the operations this request already carries, for the paths that
    /// only withdraw a handle; the connection that declares them files the
    /// request through ``answerable(on:permitting:)``.
    nonisolated func answerable(on answerHandle: AnswerHandle?) -> AgentRequest {
        answerable(on: answerHandle, permitting: operations)
    }

    /// The same request, filed against a connection and what that connection
    /// was declared to accept.
    nonisolated func answerable(
        on answerHandle: AnswerHandle?,
        permitting operations: AnswerOperations
    ) -> AgentRequest {
        AgentRequest(
            id: id,
            toolName: toolName,
            form: form,
            argumentFields: argumentFields,
            offeredRules: offeredRules,
            answerHandle: answerHandle,
            operations: operations
        )
    }

    /// The request with nothing on it that changes as its connection does.
    ///
    /// What a draft is kept against (``AnswerProgress``): the same id wearing
    /// a different body — other options, another question — is another
    /// request, and a tick taken on the old one must not travel onto it.
    nonisolated var asked: AgentRequest {
        answerable(on: nil, permitting: .readingOnly)
    }

    /// Bind a boundary-projected body to the correlation identity established
    /// by the reducer. Borrowed hook approvals learn that identity after decode.
    nonisolated func identified(by id: String) -> AgentRequest {
        AgentRequest(
            id: id, toolName: toolName, form: form,
            argumentFields: argumentFields, offeredRules: offeredRules,
            answerHandle: answerHandle, operations: operations
        )
    }

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

        /// The operations a request of this form is answered by, for a
        /// request built with no declaration.
        nonisolated var defaultOperations: AnswerOperations {
            switch self {
            case .command, .document: .decision
            case .questions, .question: .questionAnswers
            case .unsupported: .readingOnly
            }
        }

        /// Whether these operations answer this form at all.
        ///
        /// A decision form needs a grant to draw an affirmative on; a question
        /// form needs its answers taken. A refusal alone draws nothing, because
        /// the affirmative ground is the return key made visible and a row
        /// with nothing for the return key to do offers nothing (§11 rule 03).
        nonisolated func permits(_ operations: AnswerOperations) -> Bool {
            switch self {
            case .command, .document: operations.grant
            case .questions, .question: operations.answersQuestions
            case .unsupported: false
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

    /// The set this request asks, however many questions that turns out to be.
    ///
    /// **One shape for both question forms.** A question with nothing to pick is
    /// a set of one whose options are empty, which is what lets §5.3's advance,
    /// the count on the caption line and the answer that goes back be written
    /// once rather than twice — and form 04 is then the ordinary case of a set
    /// with one member rather than a case of its own.
    ///
    /// Empty on every form that is not a question, because nothing there is
    /// answered by choosing.
    nonisolated var askedQuestions: [AgentQuestion] {
        switch form {
        case let .questions(questions):
            questions
        case let .question(text):
            [
                AgentQuestion(
                    id: 0,
                    header: nil,
                    text: text,
                    options: [],
                    allowsSeveralAnswers: false
                )
            ]
        case .command, .document, .unsupported:
            []
        }
    }

    /// What this request's answer row draws, or `nil` where it can only be read.
    ///
    /// **The words are the form's, and they are not interchangeable.** A plan is
    /// `Accept` / `Send it back` and a command is `Approve` / `Deny`, because
    /// what each one grants is a different kind of thing: a command runs once,
    /// and a plan is a piece of work agreed to. §4.3 is the other half of that —
    /// accepting a plan here accepts it into whatever mode the session already
    /// has, and the row says nothing about a mode it did not set.
    ///
    /// `nil` on ``Form/unsupported`` and on every request no connection is being
    /// held for, which is §11's reading form: one control stands where three
    /// would, and no white ground is drawn anywhere.
    ///
    /// **A question's affirmative depends on where in the set it stands**, which
    /// is why this takes the position ``RequestBodyLayout/laidOut(_:showing:)``
    /// takes: on every question but the last it is `Next`, and on the last it is
    /// `Submit` (§5.8). Approvals have no set to be anywhere in and ignore it.
    ///
    /// - Parameter question: which question of the set is on screen, from the
    ///   top. The default reads the words at the first, which is what every
    ///   caller wanting only the refusal or the notices needs.
    nonisolated func answerRow(showing question: Int = 0) -> AnswerRowShape? {
        guard canBeAnswered else { return nil }
        switch form {
        case .command:
            return AnswerRowShape(
                affirmative: "Approve",
                refusal: operations.refuse ? "Deny" : nil,
                placeholder: operations.refusalTakesText ? "what to do instead…" : nil,
                affirmativeNotice: "Approved",
                refusalNotice: "Denied"
            )
        case .document:
            return AnswerRowShape(
                affirmative: "Accept",
                refusal: operations.refuse ? "Send it back" : nil,
                placeholder: operations.refusalTakesText ? "or say what to change…" : nil,
                affirmativeNotice: "Accepted",
                refusalNotice: "Sent back"
            )
        case .questions, .question:
            // **One answer, and the field takes the space** (§7). A question has
            // no refusal to carry the text, because the text *is* the answer —
            // which is also why typing moves the ground here rather than away.
            //
            // **And the word says which of the two things it does** (§5.8).
            // `Send` said the same thing on question two of three, where it
            // draws the next one, as on question three, where the set leaves —
            // so the one control that both advances and submits admitted to
            // neither. It is `Next` while there is a question after this one
            // and `Submit` on the last, including a set of one: a vocabulary
            // that appears only on long sets is one nobody learns to read,
            // which is §5.2's argument for drawing `1/1`.
            let asked = askedQuestions
            let isLast = question >= asked.count - 1
            let showing = asked.indices.contains(question) ? asked[question] : asked.first
            return AnswerRowShape(
                affirmative: isLast ? "Submit" : "Next",
                refusal: nil,
                // A question that takes no words of its own draws no field:
                // the options are the whole answer, and a field over them
                // would be a promise the product did not make.
                placeholder: showing?.acceptsFreeText == true ? "your answer…" : nil,
                affirmativeNotice: "Answered",
                refusalNotice: "Answered"
            )
        case .unsupported:
            return nil
        }
    }
}

/// One argument with its name and value kept separate. Roles select typography,
/// never a safety judgement. Unknown fields remain visible, in source spelling.
nonisolated struct ApprovalArgument: Identifiable, Sendable, Equatable {
    let id: String
    let label: String
    let value: String
    let role: Role

    nonisolated enum Role: Sendable, Equatable {
        case prose, code, resource, data
    }
}

/// The three objects at the foot of an open row, in this request's own words.
///
/// **Derived from the form, like ``AgentRequest/setting``, and for the same
/// reason**: a stored set of labels is one that could be set wrong, and the case
/// already carries the answer. A shape with no ``refusal`` is §7's one-answer
/// form — the field takes the space the refusal would have had, and nothing
/// moves.
nonisolated struct AnswerRowShape: Sendable, Equatable {
    /// What the white ground begins on, and what `⏎` does until something is
    /// typed (§6).
    let affirmative: String
    /// The answer that carries the text, where the form has one.
    let refusal: String?
    /// What the empty field says it is for, or nil where the row draws none.
    ///
    /// Its own words per form: a refusal's field asks what to do instead, and a
    /// question's asks for the answer. Absent on a refusal the product takes
    /// no words with, and on a question answered by its options alone.
    let placeholder: String?

    /// What the row's preview line says once each of them has been sent (§8
    /// state 02).
    ///
    /// Past tense, and one word where one will do: the row *is* the
    /// confirmation, so a sentence explaining what a person just did would be
    /// read once and then be in the way. Carried rather than derived from the
    /// labels above, because "the past tense of `Send it back`" is a rule about
    /// English rather than about this surface.
    let affirmativeNotice: String
    let refusalNotice: String
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
    /// §5.5: with this, the white ground starts on the affirmative and never
    /// leaves it, because the brightest object on the row must not stop being
    /// what `⏎` does on the one form where a person is most likely to press it
    /// twice.
    let allowsSeveralAnswers: Bool
    /// The question's identifier as the product spelled it, where it spelled
    /// one: Codex's `request_user_input` carries an `id` per question, and
    /// Claude Code's `AskUserQuestion` keys its answers by the question's
    /// text and carries none. ``id`` stays the position, which is what the
    /// surface draws and the keys select by; this is what a product encoder
    /// that answers by identifier reads instead of the text.
    let nativeID: String?
    /// Whether the person's own words are an answer to this question.
    ///
    /// Both shipping products take them — `AskUserQuestion`'s own dialogue
    /// offers *Other*, and Codex's schema says options are suggestions — so
    /// this is true on both, and the field is drawn. A question answered only
    /// by choosing draws no field and refuses text at every layer that
    /// carries an answer.
    let acceptsFreeText: Bool
    /// Whether a note may travel beside this question's answer.
    ///
    /// Claude Code's `annotations` field, keyed like its answers; nothing on
    /// this surface composes one yet, and an encoder refuses one where the
    /// product has nowhere to put it.
    let acceptsNote: Bool

    nonisolated init(
        id: Int,
        header: String?,
        text: String,
        options: [AgentQuestionOption],
        allowsSeveralAnswers: Bool,
        nativeID: String? = nil,
        acceptsFreeText: Bool = true,
        acceptsNote: Bool = false
    ) {
        self.id = id
        self.header = header
        self.text = text
        self.options = options
        self.allowsSeveralAnswers = allowsSeveralAnswers
        self.nativeID = nativeID
        self.acceptsFreeText = acceptsFreeText
        self.acceptsNote = acceptsNote
    }

    /// The options these positions name, in the order the product listed
    /// them; nil where any position names none.
    ///
    /// Product order rather than selection order (§5.5), and nil rather than
    /// the ones that matched: an answer naming an option this question does
    /// not offer is a stale answer, and half of one is not the person's.
    nonisolated func options(at ids: [Int]) -> [AgentQuestionOption]? {
        let wanted = Set(ids)
        let found = options.filter { wanted.contains($0.id) }
        guard Set(found.map(\.id)) == wanted else { return nil }
        return found
    }
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
    /// The option's identifier as the product spelled it, where it spelled
    /// one. Neither shipping product does; see ``AgentQuestion/nativeID``.
    let nativeID: String?

    nonisolated init(id: Int, label: String, description: String?, nativeID: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
        self.nativeID = nativeID
    }
}

/// One persistent rule the product offered to write if this were granted.
///
/// A transcription of Claude Code's `PermissionUpdate`, read from 2.1.263's own
/// zod definitions on 2026-09-06. The same type appears twice in that product:
/// as `permission_suggestions` on the `PermissionRequest` a hook receives, and
/// as `updatedPermissions` on the `allow` decision a hook may write back — so
/// what arrives is exactly what would have to be sent.
///
/// **Parsed, and drawn nowhere.** `answer-in-notch.md` §6.5 declines to offer
/// *Always* from this surface. This is here so that the fact reaches the row
/// rather than being stepped over one layer before the decode, and so that
/// whoever draws it composes a label rather than re-opening the transport.
///
/// **Not what would be sent.** A drawn half writes the suggestion back
/// **verbatim from ``HookPayload/permissionSuggestions``**, never re-encoded
/// from this: a union member added to that product and not to this type would
/// round-trip into a rule that is not the one it offered. This is for reading;
/// those bytes are for answering.
nonisolated struct PermissionRuleOffer: Sendable, Equatable {
    /// Where the product would put it: `userSettings`, `projectSettings`,
    /// `localSettings`, `session` or `cliArg`.
    ///
    /// Kept as the product's own word rather than mapped onto a case of this
    /// app's own. Only the first three are persisted to a file; `session` lasts
    /// as long as the session does. A label that says where a rule lands is
    /// saying something about the user's disk, so it says the product's word
    /// for it (§2.3).
    let destination: String
    let update: Update

    /// The six shapes the union takes.
    ///
    /// A member this app does not recognise makes the whole offer `nil` rather
    /// than a partial one: half a permission update is a different permission
    /// update, and the fail-closed direction here is to know nothing was
    /// offered rather than to know the wrong thing (`AGENTS.md` §6.2).
    nonisolated enum Update: Sendable, Equatable {
        case addRules(behavior: String, [Rule])
        case replaceRules(behavior: String, [Rule])
        case removeRules(behavior: String, [Rule])
        case setMode(String)
        case addDirectories([String])
        case removeDirectories([String])
    }

    /// One rule, in the product's two fields.
    ///
    /// `ruleContent` is absent on a whole-tool rule, which is the case the
    /// product's own `suppressAlwaysAllowRule` exists to keep out of a dialogue
    /// — so an offer carrying one is a thing to notice rather than to draw.
    nonisolated struct Rule: Sendable, Equatable {
        let toolName: String
        let ruleContent: String?
    }
}

/// Reads one product's `tool_input` into the shapes a row can draw.
///
/// Product-free on purpose: *which* payload becomes which form is a fact about
/// a product and lives on its ``AgentHookVocabulary``, while *how* a question
/// set or a command body is read out of one is the same work on both sides.
nonisolated enum AgentRequestReading {
    /// Preserve field boundaries once, while the payload is still structured.
    /// Known textual keys choose presentation only; every unknown key survives.
    /// Containers keep JSON structure (including empty arrays/objects and null).
    nonisolated static func approvalFields(in input: JSONValue) -> [ApprovalArgument] {
        // A bare string in an approval is the command itself. Do not turn it
        // into a generic prose field merely because it has no argument key.
        let fields: [String: JSONValue]
        if case .string = input {
            fields = ["command": input]
        } else {
            fields = input.objectValue ?? ["value": input]
        }
        return fields.keys.sorted().map { key in
            let value = fields[key]!
            let role: ApprovalArgument.Role
            let rendered: String
            if case let .string(text) = value {
                rendered = text.isEmpty ? "\"\"" : text
                switch key {
                case "command", "cmd", "patch", "diff", "old_string", "new_string", "content", "code":
                    role = .code
                case "url", "uri", "path", "file_path", "cwd", "workdir":
                    role = .resource
                default:
                    role = .prose
                }
            } else {
                role = .data
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                // JSONValue came from valid JSON; non-finite manually supplied
                // numbers still have an explicit reading rather than vanishing.
                rendered = (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
                    ?? scalar(value) ?? "null"
            }
            let label = switch key {
            case "url": "URL"
            case "uri": "URI"
            case "cwd": "Working directory"
            default: key.replacingOccurrences(of: "_", with: " ").capitalized
            }
            return ApprovalArgument(id: key, label: label, value: rendered, role: role)
        }
    }

    /// Compatibility reading for the command form and its plain-text callers.
    /// Structured approval rendering uses `approvalFields(in:)` instead. Both
    /// projections are made at the boundary, in deterministic key order.
    nonisolated static func arguments(of toolInput: JSONValue) -> String? {
        guard case let .object(fields) = toolInput else {
            return scalar(toolInput)
        }
        let named = fields.keys.sorted()
        guard !named.isEmpty else { return "{}" }
        // **A lone string is drawn bare.** Most tools have one argument that
        // matters, and wrapping `rm -rf build` in a name it already implies is
        // noise a reader has to look past at exactly the wrong moment.
        if named.count == 1, let only = named.first, let value = scalar(fields[only]) {
            return value.isEmpty ? "\"\"" : value
        }
        var lines: [String] = []
        for key in named {
            guard let raw = scalar(fields[key]) else { continue }
            let value = raw.isEmpty ? "\"\"" : raw
            let broken = value.split(separator: "\n", omittingEmptySubsequences: false)
            if broken.count == 1 {
                lines.append("\(key)  \(value)")
            } else {
                // A multi-line value keeps its own breaks and is indented under
                // its name, so a patch still reads as a patch.
                lines.append("\(key)")
                lines.append(contentsOf: broken.map { "  " + $0 })
            }
        }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    /// One value for the compatibility reading, with no JSON string escapes.
    ///
    /// **Not `JSONEncoder`,** which is what this was first written as. It draws
    /// the braces, the quotes and the escapes as well as the command — so a
    /// command containing a quote arrived as `\"`, and every approval opened
    /// onto its own envelope before it opened onto its request. §4.6 forbids the
    /// app annotating what it was handed; it does not oblige it to draw the
    /// wrapper the transport happened to use. Nothing is omitted: every field is
    /// still here, in a fixed order, with the person's own whitespace intact.
    private nonisolated static func scalar(_ value: JSONValue?) -> String? {
        switch value {
        case let .string(text): text
        case let .number(number):
            number == number.rounded() && abs(number) < 1e15
                ? String(Int(number))
                : String(number)
        case let .bool(flag): flag ? "true" : "false"
        case .null: "null"
        case let .array(items):
            items.isEmpty ? "[]" : items.compactMap { scalar($0) }.joined(separator: ", ")
        case let .object(fields):
            fields.isEmpty ? "{}" : fields.keys.sorted()
                .compactMap { key in scalar(fields[key]).map { "\(key)  \($0)" } }
                .joined(separator: "\n")
        case nil: nil
        }
    }

    /// The persistent rules a `PermissionRequest` offered, where it offered any.
    ///
    /// Empty rather than `nil` on absence, because absence is a *statement*
    /// here: the product sends either `suggestions` or `suppressAlwaysAllowRule`
    /// and never both, so nothing arriving means the product's own dialogue
    /// withholds the row too. There is no flag to consult — the hook payload
    /// carries neither `suppress_always_allow_rule` nor `default_to_no`, which
    /// are on the SDK's `can_use_tool` request only.
    ///
    /// **One unreadable member empties the whole list.** The members are
    /// alternatives within one offer, and a list of the ones that happened to
    /// parse would describe a grant narrower than the one on offer while
    /// looking complete. Knowing nothing was offered is the fail-closed answer;
    /// knowing part of it is not.
    nonisolated static func offeredRules(in suggestions: JSONValue?) -> [PermissionRuleOffer] {
        guard case let .array(raw)? = suggestions, !raw.isEmpty else { return [] }
        var offers: [PermissionRuleOffer] = []
        for entry in raw {
            guard case let .object(fields) = entry,
                  case let .string(type)? = fields["type"],
                  case let .string(destination)? = fields["destination"],
                  !destination.isEmpty else { return [] }
            let behavior: String? = if case let .string(value)? = fields["behavior"] {
                value
            } else {
                nil
            }
            let update: PermissionRuleOffer.Update? = switch type {
            case "addRules":
                behavior.map { .addRules(behavior: $0, rules(in: fields["rules"])) }
            case "replaceRules":
                behavior.map { .replaceRules(behavior: $0, rules(in: fields["rules"])) }
            case "removeRules":
                behavior.map { .removeRules(behavior: $0, rules(in: fields["rules"])) }
            case "setMode":
                if case let .string(mode)? = fields["mode"] { .setMode(mode) } else { nil }
            case "addDirectories":
                .addDirectories(strings(in: fields["directories"]))
            case "removeDirectories":
                .removeDirectories(strings(in: fields["directories"]))
            default:
                nil
            }
            guard let update else { return [] }
            offers.append(
                PermissionRuleOffer(destination: destination, update: update)
            )
        }
        return offers
    }

    private nonisolated static func rules(in value: JSONValue?) -> [PermissionRuleOffer.Rule] {
        guard case let .array(raw)? = value else { return [] }
        return raw.compactMap { entry in
            guard case let .object(fields) = entry,
                  case let .string(toolName)? = fields["toolName"],
                  !toolName.isEmpty else { return nil }
            var content: String?
            if case let .string(value)? = fields["ruleContent"], !value.isEmpty {
                content = value
            }
            return PermissionRuleOffer.Rule(toolName: toolName, ruleContent: content)
        }
    }

    private nonisolated static func strings(in value: JSONValue?) -> [String] {
        guard case let .array(raw)? = value else { return [] }
        return raw.compactMap { entry in
            guard case let .string(text) = entry, !text.isEmpty else { return nil }
            return text
        }
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
    ///
    /// **The question's text arrives under two names**, and reading only the
    /// first is what hid Codex's async question from this app until 2026-09-08.
    /// `AskUserQuestion` and Codex's blocking `request_user_input` both send
    /// `question`; `request_user_input_async` sends `title`, and its schema in
    /// CLI `0.153.4` gives it the same `options` array as the other two —
    /// *"Suggested answers, in display order… Omit options for a
    /// free-text-only question"*. One field, two spellings, so both are read
    /// and `question` wins where a payload somehow carries both.
    ///
    /// - Parameter acceptingNotes: whether this product takes a note beside
    ///   each answer — Claude Code's `annotations`. Codex's encoder has nowhere
    ///   to put one, so its questions say so.
    nonisolated static func questions(
        in toolInput: JSONValue,
        acceptingNotes: Bool = false
    ) -> [AgentQuestion]? {
        guard case let .object(fields) = toolInput,
              case let .array(raw)? = fields["questions"],
              !raw.isEmpty else { return nil }

        let questions = raw.enumerated().compactMap { index, entry -> AgentQuestion? in
            guard case let .object(question) = entry else { return nil }
            let spelled: String? = switch (question["question"], question["title"]) {
            case let (.string(value)?, _) where !value.isEmpty: value
            case let (_, .string(value)?) where !value.isEmpty: value
            default: nil
            }
            guard let text = spelled else { return nil }
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
            // Codex names each question; Claude Code does not. Read as the
            // product spelled it, whichever scalar it used.
            let nativeID: String? = switch question["id"] {
            case let .string(value)? where !value.isEmpty: value
            case let .number(value)?: value == value.rounded() ? String(Int(value)) : String(value)
            default: nil
            }
            return AgentQuestion(
                id: index,
                header: header,
                text: text,
                options: options,
                allowsSeveralAnswers: allowsSeveralAnswers,
                nativeID: nativeID,
                acceptsNote: acceptingNotes
            )
        }
        return questions.isEmpty ? nil : questions
    }

    /// What a header may weigh, which is what the product's own schema promises.
    nonisolated static let maximumHeaderCharacters = 16

    /// One body's text, broken into the lines the row will draw.
    ///
    /// **Wrapped here rather than by the text system, and the reason is
    /// agreement.** The panel is sized from a computed height and the row is
    /// drawn from the same text; if the two wrapped differently the row would
    /// be a line taller or shorter than the space made for it, and
    /// `answer-in-notch.md` §4.4's count of what is below the fold would be a
    /// lie. Measuring and drawing the *same array of lines* makes disagreement
    /// impossible rather than unlikely.
    ///
    /// §4.5, in three clauses:
    ///
    /// - **Line breaks are the ones the product sent.** Whitespace is never
    ///   collapsed and order is never changed.
    /// - **A continuation carries its own line's indent plus two spaces**, so a
    ///   wrap is never read as a new argument — which on a shell command is the
    ///   difference between one command and two.
    /// - **A token with nowhere to break is broken at the edge** rather than
    ///   dropped or allowed to overflow.
    nonisolated static func wrapped(
        _ text: String,
        to width: CGFloat,
        font: NSFont,
        indentContinuations: Bool = true
    ) -> [String] {
        guard width > 0 else { return [text] }
        var lines: [String] = []
        // `omittingEmptySubsequences: false` because a blank line in a plan is
        // a paragraph break the person is meant to see.
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let source = String(line)
            guard measure(source, font) > width else {
                lines.append(source)
                continue
            }
            let indent = indentContinuations
                ? String(source.prefix { $0 == " " || $0 == "\t" }) + "  " : ""
            var remainder = Substring(source)
            var isContinuation = false
            while !remainder.isEmpty {
                let prefix = isContinuation ? indent : ""
                let taken = fit(remainder, within: width, prefix: prefix, font: font)
                lines.append(prefix + taken)
                // `taken` already includes the space it broke at, where it
                // broke at one, so nothing else is consumed here -- the
                // person's own whitespace is never collapsed (§4.5).
                remainder = remainder.dropFirst(taken.count)
                isContinuation = true
            }
        }
        return lines.isEmpty ? [""] : lines
    }

    /// The longest head of `remainder` that fits, broken at a space where there
    /// is one and at the edge where there is not.
    ///
    /// **The boundary is bisected, not walked.** This measured every prefix in
    /// turn -- one full text layout per character, over a string that grows by
    /// a character each time -- which made wrapping quadratic in the length of
    /// a line and put a realistic approval's body at `14 ms`. A prefix only
    /// gets wider as it gets longer, so the first length that overflows can be
    /// bracketed in `log n` measurements instead of `n`; the break itself is
    /// then a scan for the last space at or before it, which measures nothing.
    /// Same lines out — byte-identical across `910` cases over five fonts,
    /// seven widths, both indent modes and a corpus of Unicode, emoji, tabs,
    /// URLs and unbreakable tokens — and that four-option body falls to
    /// `2.8 ms`. `aWrappedLineIsTheLongestOneThatFitsAndNeverOverflows` pins
    /// the property this rests on: the line fits, and one more character of
    /// what follows would not have.
    private nonisolated static func fit(
        _ remainder: Substring,
        within width: CGFloat,
        prefix: String,
        font: NSFont
    ) -> String {
        let characters = Array(remainder)
        // `fits` is a length known to fit -- the empty head always does -- and
        // `overflows` one known not to, exclusive. `count + 1` is not measured
        // and is not meant to be: it is the sentinel that lets the whole line
        // be the answer.
        var fits = 0
        var overflows = characters.count + 1
        while fits + 1 < overflows {
            let candidate = (fits + overflows) / 2
            if measure(prefix + String(characters[..<candidate]), font) > width {
                overflows = candidate
            } else {
                fits = candidate
            }
        }
        guard fits > 0 else {
            // Nothing fits at all -- a single glyph wider than the container.
            // Take one character so the loop always makes progress.
            return String(remainder.prefix(1))
        }
        // Broken at a space only where something is actually left over: a head
        // that reaches the end of the line has nowhere better to break.
        if fits < characters.count,
           let lastSpace = characters[..<fits].lastIndex(of: " ") {
            return String(characters[...lastSpace])
        }
        return String(characters[..<fits])
    }

    private nonisolated static func measure(_ text: String, _ font: NSFont) -> CGFloat {
        (text as NSString)
            .size(withAttributes: [.font: font])
            .width
    }
}

/// Everything an open row draws between its title and its answer row, laid out
/// once.
///
/// **The panel's height and the row's drawing come from the same value**, which
/// is what makes `answer-in-notch.md` §4.4's count of what is under the fold
/// true rather than approximately true: the lines counted here are the lines
/// drawn, character for character.
nonisolated struct RequestBodyLayout: Sendable, Equatable {
    /// §4.2's setting, which decides the font, the ground and the line height.
    let setting: AgentRequest.Setting
    /// The body's text, already wrapped to the width it will be drawn at.
    let lines: [String]
    /// The options under it, on a question. Empty on every other form.
    let options: [AgentQuestionOption]
    /// The question's own header, for the caption line's trailing side.
    let header: String?
    /// Which question of the set this is, one-based, and how many there are.
    ///
    /// **Every question draws it, `1/1` included** (§5.2): a count that appears
    /// only sometimes is a count nobody learns to read. `nil` on every form that
    /// is not a question.
    let position: Position?
    /// Whether ticking several is allowed (§5.5).
    let allowsSeveralAnswers: Bool
    var fields: [Field] = []
    var optionLayouts: [Option] = []
    var requestID: String = ""

    var maximumHeight: CGFloat {
        options.isEmpty ? PanelMetrics.requestBodyMaximumHeight : PanelMetrics.questionBodyMaximumHeight
    }

    nonisolated struct Option: Identifiable, Sendable, Equatable {
        let option: AgentQuestionOption
        let titleLines: [String]
        let descriptionLines: [String]
        let collapsedLines: [String]
        let isExpanded: Bool
        var id: Int { option.id }
        var canExpand: Bool { descriptionLines.count > 2 }
        var visibleDescription: [String] { isExpanded ? descriptionLines : collapsedLines }
        var titleHeight: CGFloat { CGFloat(titleLines.count) * PanelMetrics.optionTitleLineHeight }
        var descriptionTop: CGFloat { PanelMetrics.optionInset + titleHeight + 3 }
        var height: CGFloat {
            PanelMetrics.optionInset * 2 + titleHeight
                + (descriptionLines.isEmpty ? 0 : 3 + CGFloat(visibleDescription.count) * PanelMetrics.optionDescriptionLineHeight)
                + (canExpand ? PanelMetrics.optionDisclosureHeight : 0)
        }

        static func laidOut(_ option: AgentQuestionOption, width: CGFloat, expanded: Bool) -> Option {
            let textWidth = max(1, width - PanelMetrics.optionInset * 2 - PanelMetrics.optionHandleWidth)
            let title = AgentRequestReading.wrapped(option.label, to: textWidth, font: PanelMetrics.optionTitleFont, indentContinuations: false)
            let description = option.description.map {
                AgentRequestReading.wrapped($0, to: textWidth, font: PanelMetrics.optionDescriptionFont, indentContinuations: false)
            } ?? []
            var collapsed = Array(description.prefix(2))
            if description.count > 2, var tail = collapsed.last {
                while !tail.isEmpty && ((tail + "…") as NSString).size(withAttributes: [.font: PanelMetrics.optionDescriptionFont]).width > textWidth {
                    tail.removeLast()
                }
                collapsed[collapsed.count - 1] = tail + "…"
            }
            return Option(option: option, titleLines: title, descriptionLines: description, collapsedLines: collapsed, isExpanded: expanded)
        }
    }

    nonisolated struct Field: Identifiable, Sendable, Equatable {
        let argument: ApprovalArgument
        let labelLines: [String]
        let lines: [String]
        var id: String { argument.id }
        var isCode: Bool { argument.role == .code || argument.role == .data }
        var lineHeight: CGFloat { isCode ? 18 : 19 }
        var textTop: CGFloat {
            CGFloat(labelLines.count) * PanelMetrics.argumentLabelHeight
                + PanelMetrics.argumentLabelSpacing
                + (isCode ? PanelMetrics.machineTextVerticalInset : 0)
        }
        var height: CGFloat {
            textTop + CGFloat(lines.count) * lineHeight
                + (isCode ? PanelMetrics.machineTextVerticalInset : 0)
        }
    }

    nonisolated struct Position: Sendable, Equatable {
        let index: Int
        let count: Int
        nonisolated var drawn: String { "\(index)/\(count)" }
    }

    /// What the whole body weighs, before the viewport's cap is applied.
    nonisolated var contentHeight: CGFloat {
        if !fields.isEmpty {
            return fields.reduce(0) { $0 + $1.height }
                + CGFloat(fields.count - 1) * PanelMetrics.argumentSpacing
                + PanelMetrics.argumentBodyInset * 2
        }
        let text = CGFloat(lines.count) * PanelMetrics.requestLineHeight(for: setting)
        let ground = setting == .machineText
            ? PanelMetrics.machineTextVerticalInset * 2
            : 0
        let list = options.isEmpty
            ? 0
            : PanelMetrics.optionListSpacing
                + optionLayouts.reduce(0) { $0 + $1.height }
                + CGFloat(max(0, optionLayouts.count - 1)) * PanelMetrics.optionSpacing
        return text + ground + list
    }

    /// What the row will actually give it (§4.1), and what is left over.
    nonisolated var drawnHeight: CGFloat {
        min(contentHeight, maximumHeight)
    }

    /// Where the body's own text starts, which is not always the top.
    ///
    /// Machine text sits on a recessed ground with
    /// ``PanelMetrics/machineTextVerticalInset`` above its first line; prose
    /// starts at zero. The drawing and ``linesBelowTheFold(scrolledBy:)`` both
    /// measure from here, so neither can put a line where the other did not.
    nonisolated var textTop: CGFloat {
        setting == .machineText ? PanelMetrics.machineTextVerticalInset : 0
    }

    /// Where each field's own top sits in the body, top-down.
    ///
    /// One arithmetic for the two readers that need it — the count under the
    /// fold, and the drawing that skips what is nowhere near the viewport.
    nonisolated var fieldTops: [CGFloat] {
        var tops: [CGFloat] = []
        tops.reserveCapacity(fields.count)
        var top = PanelMetrics.argumentBodyInset
        for field in fields {
            tops.append(top)
            top += field.height + PanelMetrics.argumentSpacing
        }
        return tops
    }

    /// Which of a run of `count` equal lines, stacked down from `top`, a
    /// vertical window actually reaches.
    ///
    /// **The whole of §4.7's windowing**, and the reason it is arithmetic on
    /// the layout rather than a rule inside the view: a body is bounded by the
    /// panel (§4.1) and a payload is not — the hook boundary allows `128 KB`,
    /// which is upwards of fifteen hundred wrapped lines behind a viewport that
    /// can show eight. Drawing all of them built a `Text` per line and made
    /// every frame of a scroll walk the lot.
    ///
    /// Inclusive at both edges by construction: `floor` on the way in and
    /// `ceil` on the way out, so a line the window only half reaches is drawn
    /// rather than clipped away. `nil` is the whole run, which is what a view
    /// with no viewport over it — a measurement, a snapshot — asks for.
    nonisolated static func visibleLines(
        of count: Int,
        at lineHeight: CGFloat,
        from top: CGFloat,
        within window: ClosedRange<CGFloat>?
    ) -> Range<Int> {
        guard let window, lineHeight > 0, count > 0 else { return 0..<count }
        let first = (window.lowerBound - top) / lineHeight
        let last = (window.upperBound - top) / lineHeight
        // `first` can be enormous or hugely negative on a body far from the
        // window; clamping before the `Int` conversion is what keeps that from
        // trapping rather than merely being wrong.
        let lower = Int(min(max(first.rounded(.down), 0), CGFloat(count)))
        let upper = Int(min(max(last.rounded(.up), 0), CGFloat(count)))
        return lower..<max(lower, upper)
    }

    /// The slice of the body worth drawing lines for, at this offset (§4.7).
    ///
    /// **A slab that moves in steps, not a viewport that slides.** The viewport
    /// itself is the obvious window and it is the wrong one: it changes every
    /// time the body moves by a line, and each change rebuilds the body and
    /// re-rasterises it. Measured on Release — a four-option question went from
    /// `0.32` s to `0.50` s over `240` wheel events, and a sixty-line command
    /// from `0.55` to `0.67`, while the long bodies this exists for were still
    /// three times better either way. Paying for the rare body out of the
    /// common one is the wrong way round.
    ///
    /// So the slab is a fixed sixteen viewports, snapped to eight, and it moves
    /// about once per eight viewports of travel rather than once per line. Two
    /// things fall out of that rather than being decided:
    ///
    /// - **A body shorter than the slab is never windowed at all** — `nil`,
    ///   draw everything — which is every question and every command of a
    ///   hundred-odd lines. Those draw exactly what they always drew.
    /// - **The viewport is always well inside the slab.** A step is eight
    ///   viewports and the slab reaches half a step past it either way, so
    ///   there is no offset at which the row can be looking at ground the body
    ///   did not draw. `theDrawnSlabAlwaysContainsTheViewport` sweeps every
    ///   offset a body can reach and asserts exactly that.
    nonisolated func drawnWindow(scrolledBy offset: CGFloat) -> ClosedRange<CGFloat>? {
        let step = drawnHeight * 8
        guard step > 0, contentHeight > step * 2 else { return nil }
        let anchor = (offset / step).rounded(.down) * step
        return (anchor - step / 2)...(anchor + step * 3 / 2)
    }

    /// How many lines sit below the fold, for §4.4's count.
    ///
    /// **Lines rather than bytes** (§15 q04): a byte count is precise and
    /// unreadable, where a line count matches what the reader is looking at and
    /// is the unit in which a hidden clause hides. Zero once the last line is on
    /// screen, which is what makes the count clear itself rather than sit there
    /// naming something unreachable.
    nonisolated func linesBelowTheFold(scrolledBy offset: CGFloat) -> Int {
        if !fields.isEmpty {
            let fold = offset + maximumHeight
            var hidden = 0
            for (field, top) in zip(fields, fieldTops) {
                for index in field.labelLines.indices {
                    if top + CGFloat(index + 1) * PanelMetrics.argumentLabelHeight > fold {
                        hidden += 1
                    }
                }
                for index in field.lines.indices {
                    if top + field.textTop + CGFloat(index + 1) * field.lineHeight > fold {
                        hidden += 1
                    }
                }
            }
            return hidden
        }
        if !optionLayouts.isEmpty {
            let fold = offset + maximumHeight
            let lineHeight = PanelMetrics.requestLineHeight(for: setting)
            var hidden = lines.indices.filter { CGFloat($0 + 1) * lineHeight > fold }.count
            var top = CGFloat(lines.count) * lineHeight + PanelMetrics.optionListSpacing
            for option in optionLayouts {
                hidden += option.titleLines.indices.filter {
                    top + PanelMetrics.optionInset + CGFloat($0 + 1) * PanelMetrics.optionTitleLineHeight > fold
                }.count
                hidden += option.visibleDescription.indices.filter {
                    top + option.descriptionTop + CGFloat($0 + 1) * PanelMetrics.optionDescriptionLineHeight > fold
                }.count
                if option.canExpand && top + option.height - PanelMetrics.optionInset > fold { hidden += 1 }
                top += option.height + PanelMetrics.optionSpacing
            }
            return hidden
        }
        let lineHeight = PanelMetrics.requestLineHeight(for: setting)
        guard lineHeight > 0 else { return 0 }
        let hidden = contentHeight - offset - maximumHeight
        guard hidden > 0 else { return 0 }
        return Int(ceil(hidden / lineHeight))
    }

    /// Lays out one request's body at the width the row draws it in.
    ///
    /// `question` selects which of a set is shown, because a set is answered one
    /// at a time and the count says so (§5.2, §5.3). In the reading form only
    /// the first is reachable, and the count is what tells a reader there are
    /// more — which is exactly what §11's single control is for.
    nonisolated static func laidOut(
        _ request: AgentRequest,
        showing question: Int = 0,
        expandedOptions: Set<Int> = [],
        width: CGFloat = PanelMetrics.requestBodyWidth
    ) -> RequestBodyLayout? {
        // A lone command keeps the original unlabelled code box. Additional
        // arguments still need their labels so the command and its explanation
        // remain separate and no permission parameter disappears.
        let isPlainCommand = request.argumentFields.count == 1
            && request.argumentFields[0].role == .code
            && ["command", "cmd"].contains(request.argumentFields[0].id)
        if !request.argumentFields.isEmpty, !isPlainCommand, case .command = request.form {
            let fields = request.argumentFields.map { argument in
                let isCode = argument.role == .code || argument.role == .data
                return Field(
                    argument: argument,
                    labelLines: AgentRequestReading.wrapped(
                        argument.label, to: width, font: PanelMetrics.argumentLabelFont,
                        indentContinuations: false
                    ),
                    lines: AgentRequestReading.wrapped(
                        argument.value,
                        to: width - (isCode ? PanelMetrics.machineTextHorizontalInset * 2 : 0),
                        font: isCode ? PanelMetrics.machineTextFont : PanelMetrics.proseFont,
                        indentContinuations: isCode
                    )
                )
            }
            return RequestBodyLayout(
                setting: .prose, lines: [], options: [], header: nil,
                position: nil, allowsSeveralAnswers: false, fields: fields
            )
        }
        switch request.form {
        case let .command(text):
            return RequestBodyLayout(
                setting: .machineText,
                lines: AgentRequestReading.wrapped(
                    text,
                    to: width - PanelMetrics.machineTextHorizontalInset * 2,
                    font: PanelMetrics.machineTextFont
                ),
                options: [],
                header: nil,
                position: nil,
                allowsSeveralAnswers: false
            )
        case let .document(text), let .question(text):
            return RequestBodyLayout(
                setting: .prose,
                lines: AgentRequestReading.wrapped(
                    text,
                    to: width,
                    font: PanelMetrics.proseFont,
                    // §4.5: the continuation indent is machine text's, and a
                    // paragraph that wraps is not a second argument. Prose took
                    // it by default and every wrapped line of a plan, a
                    // restatement or a question drew two spaces in from the one
                    // above it.
                    indentContinuations: false
                ),
                options: [],
                header: nil,
                position: nil,
                allowsSeveralAnswers: false
            )
        case let .questions(questions):
            guard !questions.isEmpty else { return nil }
            let index = min(max(question, 0), questions.count - 1)
            let asked = questions[index]
            return RequestBodyLayout(
                setting: .prose,
                lines: AgentRequestReading.wrapped(
                    asked.text,
                    to: width,
                    font: PanelMetrics.proseFont,
                    indentContinuations: false
                ),
                options: asked.options,
                header: asked.header,
                position: Position(index: index + 1, count: questions.count),
                allowsSeveralAnswers: asked.allowsSeveralAnswers,
                optionLayouts: asked.options.map {
                    Option.laidOut($0, width: width, expanded: expandedOptions.contains($0.id))
                },
                requestID: request.id
            )
        case .unsupported:
            // No body at all: the row says where to answer and nothing else.
            return nil
        }
    }
}

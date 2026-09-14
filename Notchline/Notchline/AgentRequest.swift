import AppKit
import Foundation

/// What one agent is asking a person, in the shapes a row can draw.
///
/// A value, not a schema: the native boundary projects the body and ``MonitoringRepository``
/// attaches identity and handle, so the panel only renders it (`AGENTS.md` §6). Not `Codable`:
/// hook payloads never touch disk (ADR 0015). See `docs/answer-in-notch.md` §2.1.
nonisolated struct AgentRequest: Identifiable, Sendable, Equatable {
    /// The wait this belongs to, as the product spelled it. On a `PermissionRequest` it is the
    /// borrowed id of the call still open: neither product puts a `tool_use_id` there (measured
    /// on both, 2026-08-23). The open row and an answer are keyed by it.
    let id: String
    /// The reducer's request occurrence, independent of native IDs and handles.
    /// Product isolation comes from the repository epoch and the containing row.
    private(set) var identity: Identity? = nil

    nonisolated struct Identity: Sendable, Equatable, Hashable {
        let epoch: MonitoringEpoch
        let threadID: String
        let turnID: String?
        let producerID: String?
        let requestID: String
        let nativeRevision: String?
        var occurrence = UUID()
    }

    /// Repeated observations and channel changes retain an occurrence. A body
    /// revision or a newly opened wait receives a fresh one, even if native IDs
    /// and visible words have been reused.
    nonisolated func scoped(_ identity: Identity, preserving previous: AgentRequest?) -> AgentRequest {
        var result = self
        result.identity = identity
        if let previous, let old = previous.identity {
            var candidate = identity
            candidate.occurrence = old.occurrence
            result.identity = candidate
            if result.asked == previous.asked { return result }
        }
        result.identity = identity
        return result
    }
    /// The tool as the product named it: for the accessible name (§13.3) and for naming a
    /// declined form's destination (§2.2). Never drawn on the body (§4.6).
    let toolName: String?
    let form: Form

    /// The single line a row shows for a question it cannot offer to answer: the last question,
    /// since Codex emits an async question set as one assistant message per question (measured
    /// 2026-09-06). Never joined (§2.3). `nil` for every other form, including an answerable set.
    nonisolated var lastQuestionAsked: String? {
        guard case let .questions(questions) = form else { return nil }
        return questions.last?.text
    }
    /// Approval arguments projected at the hook boundary, before flattening.
    /// Empty for prose/questions and for manually constructed plain commands.
    /// The command string remains the compatibility reading, never parsed by UI.
    let argumentFields: [ApprovalArgument]
    /// The persistent rules the product offered to write alongside a grant. Empty means the
    /// product withholds the row (an ask carries `suggestions` or `suppressAlwaysAllowRule`, never
    /// both); always empty on Codex. Read but not drawn: `answer-in-notch.md` §6.5.
    let offeredRules: [PermissionRuleOffer]
    /// Whether the product offered to stop asking this in future. Not on ``answerRow``: naming a
    /// third answer it cannot send breaks §11 rule 03.
    nonisolated var offersPersistentRule: Bool { !offeredRules.isEmpty }
    /// Whether this request can be answered here, or only read (`answer-in-notch.md` §11 rule 06).
    /// Derived from ``answerHandle``: answerable only while a connection is held for it, never from
    /// the product or status alone (§11 rule 03).
    nonisolated var canBeAnswered: Bool { answerHandle != nil && form.permits(operations) }

    /// What an answer on the held connection may do (``AnswerOperations``). Declared by the
    /// boundary holding the connection, never inferred from the form: a question over a Codex
    /// `PermissionRequest` connection accepts only a decision. Undeclared, the form's own operations.
    let operations: AnswerOperations

    /// The way back to the connection this request arrived on, while held (``AnswerHandle``);
    /// `nil` once closed, and the row says `Read`. Not drawn or compared by the change projection.
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

    /// The same request, filed against the connection it arrived on, keeping its operations. A
    /// connection that declares operations uses ``answerable(on:permitting:)``.
    nonisolated func answerable(on answerHandle: AnswerHandle?) -> AgentRequest {
        answerable(on: answerHandle, permitting: operations)
    }

    /// The same request, filed against a connection and what that connection
    /// was declared to accept.
    nonisolated func answerable(
        on answerHandle: AnswerHandle?,
        permitting operations: AnswerOperations
    ) -> AgentRequest {
        var result = AgentRequest(
            id: id,
            toolName: toolName,
            form: form,
            argumentFields: argumentFields,
            offeredRules: offeredRules,
            answerHandle: answerHandle,
            operations: operations
        )
        result.identity = identity
        return result
    }

    /// The request without anything that changes with its connection. Drafts (``AnswerProgress``)
    /// are kept against it, so a different body under the same id is another request.
    nonisolated var asked: AgentRequest {
        answerable(on: nil, permitting: .readingOnly)
    }

    /// Bind a boundary-projected body to the correlation identity established
    /// by the reducer. Borrowed hook approvals learn that identity after decode.
    nonisolated func identified(by id: String) -> AgentRequest {
        var result = AgentRequest(
            id: id, toolName: toolName, form: form,
            argumentFields: argumentFields, offeredRules: offeredRules,
            answerHandle: answerHandle, operations: operations
        )
        result.identity = identity
        return result
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
        /// A form this app declines to draw, carrying no body (§2.2). Not a parse failure (that is
        /// `nil`): an `Elicitation`'s fields are a third-party MCP server's, of arbitrary shape.
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

        /// Whether these operations answer this form: a decision needs a grant, a question needs its
        /// answers taken. A refusal alone draws nothing (§11 rule 03).
        nonisolated func permits(_ operations: AnswerOperations) -> Bool {
            switch self {
            case .command, .document: operations.grant
            case .questions, .question: operations.answersQuestions
            case .unsupported: false
            }
        }
    }

    /// Which of §4.2's two settings the body is drawn in; derived from the form, never the length.
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

    /// The questions this request asks. A question with nothing to pick is a set of one with no
    /// options (form 04). Empty on every form that is not a question.
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

    /// What this request's answer row draws, or `nil` where it can only be read (§11). The words
    /// are the form's; a question's affirmative depends on `question`'s place in the set (§5.8).
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
            // One answer; the field takes the space (§7). `Next`, then `Submit` on the last (§5.8).
            let asked = askedQuestions
            let isLast = question >= asked.count - 1
            let showing = asked.indices.contains(question) ? asked[question] : asked.first
            return AnswerRowShape(
                affirmative: isLast ? "Submit" : "Next",
                refusal: nil,
                // A question that takes no words of its own draws no field.
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

/// The three objects at the foot of an open row, derived from the form. A shape with no
/// ``refusal`` is §7's one-answer form.
nonisolated struct AnswerRowShape: Sendable, Equatable {
    /// What the white ground begins on, and what `⏎` does until something is typed (§6).
    let affirmative: String
    /// The answer that carries the text, where the form has one.
    let refusal: String?
    /// What the empty field says it is for, or nil where the row draws none.
    let placeholder: String?

    /// What the row's preview line says once each answer has been sent (§8 state 02).
    let affirmativeNotice: String
    let refusalNotice: String
}

/// One question out of a set, in the order the product asked them.
nonisolated struct AgentQuestion: Identifiable, Sendable, Equatable {
    /// Position in the set, drawn as `2/3` (§5.2); the payload carries no identifier of its own.
    let id: Int
    /// At most sixteen characters, enforced here for §5.2's caption line. `nil` from Codex.
    let header: String?
    let text: String
    let options: [AgentQuestionOption]
    /// Whether several options may be taken at once; the white ground then stays on the
    /// affirmative (§5.5).
    let allowsSeveralAnswers: Bool
    /// Codex's per-question `id`, for encoders that answer by identifier; Claude Code's
    /// `AskUserQuestion` keys answers by text and carries none.
    let nativeID: String?
    /// Whether the person's own words answer this question; when false, no field is drawn and text
    /// is refused at every layer.
    let acceptsFreeText: Bool
    /// Whether a note may travel beside this answer (Claude Code's `annotations`). Nothing composes
    /// one yet; an encoder refuses one where the product has nowhere to put it.
    let acceptsNote: Bool
    /// Source-projected selection and text limits for a reading-only form.
    let readingHint: String?

    nonisolated init(
        id: Int,
        header: String?,
        text: String,
        options: [AgentQuestionOption],
        allowsSeveralAnswers: Bool,
        nativeID: String? = nil,
        acceptsFreeText: Bool = true,
        acceptsNote: Bool = false,
        readingHint: String? = nil
    ) {
        self.id = id
        self.header = header
        self.text = text
        self.options = options
        self.allowsSeveralAnswers = allowsSeveralAnswers
        self.nativeID = nativeID
        self.acceptsFreeText = acceptsFreeText
        self.acceptsNote = acceptsNote
        self.readingHint = readingHint
    }

    /// The options these positions name, in product order (§5.5); nil if any position names none,
    /// since a partial match is a stale answer.
    nonisolated func options(at ids: [Int]) -> [AgentQuestionOption]? {
        let wanted = Set(ids)
        let found = options.filter { wanted.contains($0.id) }
        guard Set(found.map(\.id)) == wanted else { return nil }
        return found
    }
}

nonisolated struct AgentQuestionOption: Identifiable, Sendable, Equatable {
    let id: Int
    /// The product's own word for this answer, never a paraphrase (§2.3).
    let label: String
    let description: String?
    /// The option's identifier as the product spelled it; neither shipping product sends one.
    let nativeID: String?

    nonisolated init(id: Int, label: String, description: String?, nativeID: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
        self.nativeID = nativeID
    }
}

/// One persistent rule the product offered to write if this were granted: Claude Code's
/// `PermissionUpdate` (2.1.263, 2026-09-06). Drawn nowhere (`answer-in-notch.md` §6.5).
/// Read-only: an answer sends ``HookPayload/permissionSuggestions`` verbatim, not this.
nonisolated struct PermissionRuleOffer: Sendable, Equatable {
    /// The product's word for where it lands: `userSettings`, `projectSettings`, `localSettings`
    /// (persisted to a file), `session` or `cliArg` (§2.3).
    let destination: String
    let update: Update

    /// The six shapes the union takes. An unrecognised member makes the whole offer `nil`
    /// (fail closed, `AGENTS.md` §6.2).
    nonisolated enum Update: Sendable, Equatable {
        case addRules(behavior: String, [Rule])
        case replaceRules(behavior: String, [Rule])
        case removeRules(behavior: String, [Rule])
        case setMode(String)
        case addDirectories([String])
        case removeDirectories([String])
    }

    /// One rule. `ruleContent` is absent on a whole-tool rule, which the product's
    /// `suppressAlwaysAllowRule` keeps out of its dialogue.
    nonisolated struct Rule: Sendable, Equatable {
        let toolName: String
        let ruleContent: String?
    }
}

/// Reads one product's `tool_input` into the shapes a row can draw. Product-free: which
/// payload becomes which form lives on ``AgentHookVocabulary``.
nonisolated enum AgentRequestReading {
    /// Known keys choose presentation only; every unknown key and JSON container survives.
    nonisolated static func approvalFields(in input: JSONValue) -> [ApprovalArgument] {
        // A bare string is the command itself, not a generic prose field.
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
                // Non-finite manually supplied numbers still get a reading rather than vanishing.
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

    /// Compatibility reading for the command form; structured approvals use `approvalFields(in:)`.
    nonisolated static func arguments(of toolInput: JSONValue) -> String? {
        guard case let .object(fields) = toolInput else {
            return scalar(toolInput)
        }
        let named = fields.keys.sorted()
        guard !named.isEmpty else { return "{}" }
        // A lone string is drawn bare, without its argument name.
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
                // A multi-line value keeps its breaks, indented under its name.
                lines.append("\(key)")
                lines.append(contentsOf: broken.map { "  " + $0 })
            }
        }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    /// One value without JSON quotes or escapes; `JSONEncoder` drew `\"` into commands.
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

    /// The persistent rules a `PermissionRequest` offered; empty when none (the product sends
    /// `suggestions` or `suppressAlwaysAllowRule`, never both). One unreadable member empties the
    /// whole list (fail closed).
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

    /// The named string inside an object; empty counts as absent.
    nonisolated static func text(_ key: String, in toolInput: JSONValue) -> String? {
        guard case let .object(fields) = toolInput,
              case let .string(value)? = fields[key],
              !value.isEmpty else { return nil }
        return value
    }

    /// The question set inside a `tool_input`, untrimmed (§2.3). Questions without text are
    /// dropped; without options are kept (form 04). The text arrives as `question` or, from
    /// `request_user_input_async` (CLI `0.153.4`), `title`; `question` wins.
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
            // Codex names each question; Claude Code does not.
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

    nonisolated static let maximumHeaderCharacters = 16

    /// One body's text, broken into the lines the row will draw (§4.5). Wrapped here so the
    /// panel height and the drawing use the same lines (`answer-in-notch.md` §4.4).
    nonisolated static func wrapped(
        _ text: String,
        to width: CGFloat,
        font: NSFont,
        indentContinuations: Bool = true
    ) -> [String] {
        guard width > 0 else { return [text] }
        var lines: [String] = []
        // A blank line in a plan is a paragraph break the person should see.
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
                // `taken` already includes the space it broke at; whitespace is never collapsed (§4.5).
                remainder = remainder.dropFirst(taken.count)
                isContinuation = true
            }
        }
        return lines.isEmpty ? [""] : lines
    }

    /// The longest head of `remainder` that fits, broken at a space where there is one. Bisected:
    /// a linear scan was quadratic (14 ms vs 2.8 ms on a realistic approval).
    private nonisolated static func fit(
        _ remainder: Substring,
        within width: CGFloat,
        prefix: String,
        font: NSFont
    ) -> String {
        let characters = Array(remainder)
        // `count + 1` is an unmeasured sentinel so the whole line can be the answer.
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
            // A single glyph wider than the container: take one character so the loop progresses.
            return String(remainder.prefix(1))
        }
        // Break at a space only where something is left over.
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

/// An open row's body, laid out once so panel height and drawing agree (§4.4).
nonisolated struct RequestBodyLayout: Sendable, Equatable {
    /// §4.2's setting: font, ground and line height.
    let setting: AgentRequest.Setting
    /// The body's text, wrapped to its drawn width.
    let lines: [String]
    /// The options under it, on a question. Empty on every other form.
    let options: [AgentQuestionOption]
    let header: String?
    /// One-based position and count, drawn on every question, `1/1` included (§5.2).
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

    /// The body's height before the viewport cap.
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

    /// Where the body's text starts; shared by the drawing and ``linesBelowTheFold(scrolledBy:)``.
    nonisolated var textTop: CGFloat {
        setting == .machineText ? PanelMetrics.machineTextVerticalInset : 0
    }

    /// Each field's top in the body, shared by the fold count and the windowed drawing.
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

    /// Which of `count` lines stacked from `top` a window reaches (§4.7); a `128 KB` payload is
    /// ~1,500 lines. Inclusive at both edges; a `nil` window is the whole run.
    nonisolated static func visibleLines(
        of count: Int,
        at lineHeight: CGFloat,
        from top: CGFloat,
        within window: ClosedRange<CGFloat>?
    ) -> Range<Int> {
        guard let window, lineHeight > 0, count > 0 else { return 0..<count }
        let first = (window.lowerBound - top) / lineHeight
        let last = (window.upperBound - top) / lineHeight
        // Clamp before the `Int` conversion so a body far from the window cannot trap.
        let lower = Int(min(max(first.rounded(.down), 0), CGFloat(count)))
        let upper = Int(min(max(last.rounded(.up), 0), CGFloat(count)))
        return lower..<max(lower, upper)
    }

    /// The slice of the body worth drawing lines for, at this offset (§4.7).
    ///
    /// A slab of sixteen viewports snapped to eight: windowing on the viewport rebuilt per line
    /// and slowed short bodies (0.32 s to 0.50 s over 240 wheel events, Release). A body shorter
    /// than the slab is never windowed (`nil`).
    nonisolated func drawnWindow(scrolledBy offset: CGFloat) -> ClosedRange<CGFloat>? {
        let step = drawnHeight * 8
        guard step > 0, contentHeight > step * 2 else { return nil }
        let anchor = (offset / step).rounded(.down) * step
        return (anchor - step / 2)...(anchor + step * 3 / 2)
    }

    /// Lines below the fold, for §4.4's count (lines, not bytes: §15 q04); zero once the last
    /// line is on screen.
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

    /// Lays out one request's body at the row's width. `question` selects which of a set is shown
    /// (§5.2, §5.3); reading-only sets may browse every question.
    nonisolated static func laidOut(
        _ request: AgentRequest,
        showing question: Int = 0,
        expandedOptions: Set<Int> = [],
        width: CGFloat = PanelMetrics.requestBodyWidth
    ) -> RequestBodyLayout? {
        // A lone command keeps the unlabelled code box; with more arguments every field is labelled.
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
                    // §4.5: only machine text indents continuations.
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
                    [asked.text, asked.readingHint].compactMap { $0 }.joined(separator: "\n\n"),
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
            // No body: the row only says where to answer.
            return nil
        }
    }
}

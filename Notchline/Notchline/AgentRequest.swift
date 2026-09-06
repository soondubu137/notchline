import AppKit
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
    /// Whether this request can be answered **here**, or only read here.
    ///
    /// `answer-in-notch.md` §11 rule 06: the two halves are per product and per
    /// shape, and *the row says what that row can do* — a row that can only be
    /// read beside one that can be answered is an ordinary mixed list, not a
    /// special case. So this is a fact about one request rather than a setting,
    /// and the vocabulary that read the request is what knows it.
    ///
    /// **False everywhere today**, because no write path is built yet (§14.2).
    /// That is why the mark says `Read` rather than `Answer` under the pointer:
    /// the affirmative ground is the return key made visible, and offering one
    /// the app cannot deliver is a promise made quietly (§11 rule 03).
    let canBeAnswered: Bool

    nonisolated init(
        id: String,
        toolName: String?,
        form: Form,
        canBeAnswered: Bool = false
    ) {
        self.id = id
        self.toolName = toolName
        self.form = form
        self.canBeAnswered = canBeAnswered
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
    /// **The fixed order is load-bearing and not cosmetic.** ``JSONValue/object``
    /// is a Swift `Dictionary`, whose iteration order differs between instances
    /// holding equal values — so rendering in whatever order the dictionary
    /// offered would produce a different string for the same request on a later
    /// read, and ``HookEventRepository/renderedProjection()`` would see a change
    /// and wake the panel for it. Sorting by name is what makes a request that
    /// has not changed read as one that has not changed.
    ///
    /// Rendered here, once, inside the actor, and never in a row builder: rows
    /// are rebuilt on every refresh, and a `String` made once is then shared by
    /// copy-on-write, so comparing two rebuilt rows compares a pointer rather
    /// than 128 KiB.
    nonisolated static func arguments(of toolInput: JSONValue) -> String? {
        guard case let .object(fields) = toolInput else {
            return scalar(toolInput)
        }
        let named = fields.keys.sorted()
        // **A lone string is drawn bare.** Most tools have one argument that
        // matters, and wrapping `rm -rf build` in a name it already implies is
        // noise a reader has to look past at exactly the wrong moment.
        if named.count == 1, let only = named.first, let value = scalar(fields[only]) {
            return value.isEmpty ? nil : value
        }
        var lines: [String] = []
        for key in named {
            guard let value = scalar(fields[key]), !value.isEmpty else { continue }
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

    /// One value as the row would read it, with no JSON around it.
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
            items.compactMap { scalar($0) }.joined(separator: ", ")
        case let .object(fields):
            fields.keys.sorted()
                .compactMap { key in scalar(fields[key]).map { "\(key)  \($0)" } }
                .joined(separator: "\n")
        case nil: nil
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
        font: NSFont
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
            let indent = String(source.prefix { $0 == " " || $0 == "\t" }) + "  "
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
    private nonisolated static func fit(
        _ remainder: Substring,
        within width: CGFloat,
        prefix: String,
        font: NSFont
    ) -> String {
        var fitting = ""
        var lastBreak: String?
        var current = ""
        for character in remainder {
            current.append(character)
            if measure(prefix + current, font) > width { break }
            fitting = current
            if character == " " { lastBreak = current }
        }
        if fitting.isEmpty {
            // Nothing fits at all -- a single glyph wider than the container.
            // Take one character so the loop always makes progress.
            return String(remainder.prefix(1))
        }
        if fitting.count < remainder.count, let lastBreak, !lastBreak.isEmpty {
            return lastBreak
        }
        return fitting
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

    nonisolated struct Position: Sendable, Equatable {
        let index: Int
        let count: Int
        nonisolated var drawn: String { "\(index)/\(count)" }
    }

    /// What the whole body weighs, before the viewport's cap is applied.
    nonisolated var contentHeight: CGFloat {
        let text = CGFloat(lines.count) * PanelMetrics.requestLineHeight(for: setting)
        let ground = setting == .machineText
            ? PanelMetrics.machineTextVerticalInset * 2
            : 0
        let list = options.isEmpty
            ? 0
            : PanelMetrics.optionListSpacing
                + CGFloat(options.count) * PanelMetrics.optionRowHeight
        return text + ground + list
    }

    /// What the row will actually give it (§4.1), and what is left over.
    nonisolated var drawnHeight: CGFloat {
        min(contentHeight, PanelMetrics.requestBodyMaximumHeight)
    }

    /// How many lines sit below the fold, for §4.4's count.
    ///
    /// **Lines rather than bytes** (§15 q04): a byte count is precise and
    /// unreadable, where a line count matches what the reader is looking at and
    /// is the unit in which a hidden clause hides. Zero once the last line is on
    /// screen, which is what makes the count clear itself rather than sit there
    /// naming something unreachable.
    nonisolated func linesBelowTheFold(scrolledBy offset: CGFloat) -> Int {
        let lineHeight = PanelMetrics.requestLineHeight(for: setting)
        guard lineHeight > 0 else { return 0 }
        let hidden = contentHeight - offset - PanelMetrics.requestBodyMaximumHeight
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
        width: CGFloat = PanelMetrics.requestBodyWidth
    ) -> RequestBodyLayout? {
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
                    font: PanelMetrics.proseFont
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
                    font: PanelMetrics.proseFont
                ),
                options: asked.options,
                header: asked.header,
                position: Position(index: index + 1, count: questions.count),
                allowsSeveralAnswers: asked.allowsSeveralAnswers
            )
        case .unsupported:
            // No body at all: the row says where to answer and nothing else.
            return nil
        }
    }
}

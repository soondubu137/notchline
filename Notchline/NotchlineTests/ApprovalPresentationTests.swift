import AppKit
import SwiftUI
import Testing
@testable import Notchline

struct ApprovalPresentationTests {
    @Test @MainActor
    func approvalFieldsReachBothProductsAndSurviveTicketChanges() throws {
        let input = JSONValue.object([
            "prompt": .string("Read the page title.\nKeep the wording."),
            "url": .string("https://example.com/a?one=1&two=2")
        ])
        let vocabularies: [any AgentHookVocabulary] = [ClaudeCodeHookVocabulary(), CodexHookVocabulary()]
        for vocabulary in vocabularies {
            let request = try #require(vocabulary.request(
                forEvent: "PermissionRequest", toolName: "WebFetch", toolInput: input,
                permissionSuggestions: nil, openedBy: "call-1"
            ))
            #expect(request.argumentFields.map(\.id) == ["prompt", "url"])
            #expect(request.argumentFields.map(\.role) == [.prose, .resource])
            #expect(request.argumentFields[0].value == "Read the page title.\nKeep the wording.")
            #expect(request.argumentFields[1].value == "https://example.com/a?one=1&two=2")
            #expect(request.answerable(on: nil).argumentFields == request.argumentFields)
            let layout = try #require(RequestBodyLayout.laidOut(request))
            #expect(layout.fields.count == 2)
            #expect(layout.fields.allSatisfy { !$0.isCode })
            #expect(layout.lines.isEmpty, "the flattened compatibility reading is never also drawn")
        }
    }

    @Test @MainActor
    func loneCommandsKeepTheOriginalMonospacedBox() throws {
        let command = "printf '%s\\n' \"$HOME\"\necho done"
        for input: JSONValue in [.object(["command": .string(command)]), .object(["cmd": .string(command)]), .string(command)] {
            for vocabulary: any AgentHookVocabulary in [ClaudeCodeHookVocabulary(), CodexHookVocabulary()] {
                let request = try #require(vocabulary.request(
                    forEvent: "PermissionRequest", toolName: "Bash", toolInput: input,
                    permissionSuggestions: nil, openedBy: "call"
                ))
                let layout = try #require(RequestBodyLayout.laidOut(request))
                #expect(layout.setting == .machineText)
                #expect(layout.fields.isEmpty, "a lone command needs no field heading")
                #expect(layout.lines == command.components(separatedBy: "\n"))
                #expect(layout.contentHeight == 36 + PanelMetrics.machineTextVerticalInset * 2)
            }
        }
    }

    @Test @MainActor
    func emptyValuesStillOpenAnHonestReading() throws {
        for input: JSONValue in [.object(["options": .array([])]), .object(["prompt": .string("")]), .object([:]), .null] {
            let request = try #require(ClaudeCodeHookVocabulary().request(
                forEvent: "PermissionRequest", toolName: "Tool", toolInput: input,
                permissionSuggestions: nil, openedBy: "call"
            ))
            #expect(RequestBodyLayout.laidOut(request) != nil)
        }
    }

    @Test
    func nestedAndEmptyArgumentsKeepTheirTypesAndStableOrder() throws {
        let nested = JSONValue.object([
            "list": .array([.string("a,b"), .null, .object([:])]),
            "flag": .bool(false), "empty": .array([])
        ])
        let fields = AgentRequestReading.approvalFields(in: .object([
            "options": nested, "empty_text": .string(""), "timeout": .number(0)
        ]))
        #expect(fields.map(\.id) == ["empty_text", "options", "timeout"])
        #expect(fields[0].value == "\"\"")
        #expect(fields[2].value == "0")
        #expect(try JSONDecoder().decode(JSONValue.self, from: Data(fields[1].value.utf8)) == nested)
        #expect(AgentRequestReading.approvalFields(in: .object([
            "timeout": .number(0), "empty_text": .string(""), "options": nested
        ])) == fields)
    }

    @Test @MainActor
    func codeIsRecessedButDescriptionsAndUnknownArgumentsAreProse() throws {
        let input = JSONValue.object([
            "command": .string("printf '%s\\n' \"$HOME\""),
            "description": .string("Print the home directory."),
            "vendor_note": .string("Keep this unfamiliar field visible."),
            "file_path": .string("/tmp/a file.swift")
        ])
        let fields = AgentRequestReading.approvalFields(in: input)
        let request = AgentRequest(id: "call", toolName: "Bash", form: .command("legacy"), argumentFields: fields)
        let layout = try #require(RequestBodyLayout.laidOut(request))
        #expect(layout.fields.filter(\.isCode).map(\.id) == ["command"])
        #expect(layout.fields.flatMap(\.lines).joined().contains("Keep this unfamiliar field visible."))
        #expect(layout.fields[0].argument.value == "printf '%s\\n' \"$HOME\"")
    }

    @Test @MainActor
    func structuredBodyDrawingMatchesItsMeasuredHeightAndReachesTheLastLine() throws {
        for width: CGFloat in [320, PanelMetrics.requestBodyWidth] {
            for input: JSONValue in [
                .object(["prompt": .string("This is a no-op permission-dialog test. Just say what the page title is."), "url": .string("https://example.com")]),
                .object(["command": .string(String(repeating: "  echo hello && ", count: 40)), "description": .string("A long command.")]),
                .object([String(repeating: "long_key_", count: 16): .string(String(repeating: "https://example.com/", count: 30))])
            ] {
                let request = AgentRequest(id: "call", toolName: "Tool", form: .command("legacy"), argumentFields: AgentRequestReading.approvalFields(in: input))
                let layout = try #require(RequestBodyLayout.laidOut(request, width: width))
                let host = NSHostingView(rootView: RequestBodyView(layout: layout).frame(width: width))
                host.setFrameSize(NSSize(width: width, height: layout.contentHeight))
                host.layoutSubtreeIfNeeded()
                #expect(abs(host.fittingSize.height - layout.contentHeight) < 0.5)
                #expect(layout.drawnHeight <= PanelMetrics.requestBodyMaximumHeight)
                #expect(layout.linesBelowTheFold(scrolledBy: max(0, layout.contentHeight - layout.drawnHeight)) == 0)
                if layout.contentHeight > PanelMetrics.requestBodyMaximumHeight {
                    #expect(layout.linesBelowTheFold(scrolledBy: 0) > 0)
                }
            }
        }
    }

    @Test @MainActor
    func proseWrapsWithoutInventingCommandContinuationIndent() {
        let source = "A sentence with several ordinary words."
        let lines = AgentRequestReading.wrapped(source, to: 90, font: PanelMetrics.proseFont, indentContinuations: false)
        #expect(lines.count > 1)
        #expect(lines.joined() == source)
    }

    /// And the bodies that are prose actually ask for that.
    ///
    /// §4.5 said so and the layout did not: a question, a plan and a document
    /// all took `wrapped`'s default, so every line of a wrapped paragraph after
    /// the first drew two spaces in from the one above it — a hanging indent
    /// invented for shell arguments, applied to a sentence. Asserted through
    /// ``RequestBodyLayout/laidOut(_:showing:expandedOptions:width:)`` rather
    /// than against `wrapped` directly, because the call site is what was wrong.
    @Test @MainActor
    func aProseBodyIsLaidOutWithoutTheCommandContinuationIndent() throws {
        let paragraph = "This is a long question about which database to use, "
            + "asked in enough words that it has to wrap more than once."
        let forms: [AgentRequest.Form] = [
            .question(paragraph),
            .document(paragraph),
            .questions([
                AgentQuestion(
                    id: 0, header: nil, text: paragraph,
                    options: [AgentQuestionOption(id: 0, label: "SQLite", description: nil)],
                    allowsSeveralAnswers: false
                )
            ])
        ]
        for form in forms {
            let request = AgentRequest(id: "call", toolName: "Tool", form: form)
            let layout = try #require(RequestBodyLayout.laidOut(request, width: 240))
            #expect(layout.lines.count > 2, "\(form)")
            for line in layout.lines.dropFirst() {
                #expect(!line.hasPrefix(" "), "\(line)")
            }
            #expect(layout.lines.joined() == paragraph, "\(form)")
        }
    }

    /// A command's continuation indent is untouched by that.
    ///
    /// §4.5's rule is machine text's and always was: on a shell command the
    /// difference between a continuation and a new line is the difference
    /// between one command and two.
    @Test @MainActor
    func aCommandBodyKeepsItsContinuationIndent() throws {
        let request = AgentRequest(
            id: "call", toolName: "Bash",
            form: .command("git log --oneline --graph --decorate --all --since=yesterday")
        )
        let layout = try #require(RequestBodyLayout.laidOut(request, width: 200))
        #expect(layout.lines.count > 1)
        #expect(layout.lines.dropFirst().allSatisfy { $0.hasPrefix("  ") })
    }

    /// Every line is as full as it can be, and none of them overflows.
    ///
    /// **The property the bisection has to keep.** The fitter used to measure
    /// every prefix of a line in turn — one full text layout per character, on
    /// a string a character longer each time — which made wrapping quadratic in
    /// the length of a line and a realistic body `14 ms` to lay out. Width only
    /// grows with length, so the first length that overflows can be bracketed
    /// in `log n` measurements instead of `n`; what must not move is *where the
    /// break lands*, and that is exactly this: the line fits, and one more
    /// character of what follows would not have.
    ///
    /// Checked on an unbreakable token, where the break is at the character and
    /// the assertion is exact, and on prose, where a break at a space is only
    /// right if the word it moved down would not have fitted whole.
    @Test @MainActor
    func aWrappedLineIsTheLongestOneThatFitsAndNeverOverflows() throws {
        let mono = PanelMetrics.machineTextFont
        let prose = PanelMetrics.proseFont

        // A token with nowhere to break: every line but the last is exactly
        // full, and one more glyph would put it over.
        for width in [37.0, 61.5, 140.0, 233.0] as [CGFloat] {
            let token = String(repeating: "abcdefghij", count: 12)
            let lines = AgentRequestReading.wrapped(
                token, to: width, font: mono, indentContinuations: false
            )
            #expect(lines.joined() == token, "\(width)")
            for (index, line) in lines.enumerated() {
                #expect(PanelMetrics.textWidth(line, font: mono) <= width, "\(line)")
                guard index + 1 < lines.count, let next = lines[index + 1].first else { continue }
                #expect(
                    PanelMetrics.textWidth(line + String(next), font: mono) > width,
                    "line \(index) at \(width) is one character short of full"
                )
            }
        }

        // Prose, where the break moves back to the last space: the line fits,
        // and the word that went down with it would not have.
        let paragraph = "Claude wants to run a command that will modify files "
            + "outside the current project directory, which is a change that "
            + "reaches past this checkout and is worth reading before granting."
        for width in [120.0, 240.0, PanelMetrics.requestBodyWidth] as [CGFloat] {
            let lines = AgentRequestReading.wrapped(
                paragraph, to: width, font: prose, indentContinuations: false
            )
            #expect(lines.joined() == paragraph, "\(width)")
            for (index, line) in lines.enumerated() {
                #expect(PanelMetrics.textWidth(line, font: prose) <= width, "\(line)")
                guard index + 1 < lines.count else { continue }
                let nextWord = lines[index + 1].prefix { $0 != " " }
                #expect(
                    PanelMetrics.textWidth(line + nextWord, font: prose) > width,
                    "line \(index) at \(width) had room for \(nextWord)"
                )
            }
        }
    }
}

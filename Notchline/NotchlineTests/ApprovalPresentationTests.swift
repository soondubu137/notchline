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

    /// §4.5: prose bodies take no hanging continuation indent. Asserted through
    /// ``RequestBodyLayout/laidOut(_:showing:expandedOptions:width:)`` because the call site was wrong.
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

    /// §4.5's indent is for machine text: on a shell command a continuation versus a new line is
    /// one command versus two.
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

    /// The property the bisection must keep: the line fits, and one more character would not.
    /// Checked on an unbreakable token (exact) and on prose (the moved word would not have fitted).
    @Test @MainActor
    func aWrappedLineIsTheLongestOneThatFitsAndNeverOverflows() throws {
        let mono = PanelMetrics.machineTextFont
        let prose = PanelMetrics.proseFont

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

    /// §4.7: a lagging window draws blank panel, not a late line. Swept over every offset, both
    /// open-row viewport heights, and bodies either side of the slab.
    @Test @MainActor
    func theDrawnSlabAlwaysContainsTheViewport() throws {
        for lineCount in [1, 8, 60, 124, 125, 400, 4000] {
            let text = (1...lineCount).map { "line \($0)" }.joined(separator: "\n")
            for form in [AgentRequest.Form.command(text), .document(text)] {
                let request = AgentRequest(id: "slab", toolName: "Bash", form: form)
                let layout = try #require(RequestBodyLayout.laidOut(request))
                let travel = max(layout.contentHeight - layout.maximumHeight, 0)
                #expect(layout.drawnHeight <= layout.maximumHeight)
                for step in stride(from: 0.0, through: travel + 1, by: 3.0) {
                    let offset = min(step, travel)
                    guard let window = layout.drawnWindow(scrolledBy: offset) else {
                        // Not windowed: shorter than the slab, so every line is drawn.
                        #expect(layout.contentHeight <= layout.drawnHeight * 16)
                        continue
                    }
                    #expect(window.lowerBound <= offset, "\(lineCount) at \(offset)")
                    #expect(
                        window.upperBound >= offset + layout.drawnHeight,
                        "\(lineCount) at \(offset): \(window) misses the foot of the viewport"
                    )
                }
            }
        }
    }

    /// Inclusive both ways, so a half-touched line is drawn; clamped before integer conversion, so
    /// a far-off run cannot trap.
    @Test @MainActor
    func aWindowReachesEveryLineItTouchesAndNoOthers() {
        let visible = RequestBodyLayout.visibleLines
        // Ten 10pt lines; 25...45 touches lines 2, 3 and 4.
        #expect(visible(10, 10, 0, 25...45) == 2..<5)
        #expect(visible(10, 10, 0, 20...40) == 2..<4)
        #expect(visible(10, 10, 100, 125...145) == 2..<5)
        #expect(visible(10, 10, 1000, 0...50).isEmpty)
        #expect(visible(10, 10, 0, 5000...6000).isEmpty)
        #expect(visible(10, 10, 0, -500...5000) == 0..<10)
        #expect(visible(10, 10, 0, nil) == 0..<10)
        #expect(visible(0, 10, 0, 0...10).isEmpty)
        #expect(visible(10, 0, 0, 0...10) == 0..<10)
    }

    /// Compared pixel for pixel at full height: the height drives the wheel's travel, the rail and
    /// §4.4's count.
    @Test @MainActor
    func aWindowedBodyDrawsWhatTheWholeOneDrewAndStandsAsTall() throws {
        let text = (1...300)
            .map { "line \($0): a plan step long enough to wrap at the body width" }
            .joined(separator: "\n")
        let request = AgentRequest(id: "windowed", toolName: "ExitPlanMode", form: .document(text))
        let layout = try #require(RequestBodyLayout.laidOut(request))
        let width = PanelMetrics.requestBodyWidth
        #expect(layout.contentHeight > layout.drawnHeight * 16, "the body has to be long enough to window")

        func render(_ window: ClosedRange<CGFloat>?) throws -> NSBitmapImageRep {
            let host = NSHostingView(
                rootView: RequestBodyView(layout: layout, window: window).frame(width: width)
            )
            host.setFrameSize(NSSize(width: width, height: layout.contentHeight))
            host.layoutSubtreeIfNeeded()
            #expect(abs(host.fittingSize.height - layout.contentHeight) < 0.5, "\(String(describing: window))")
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            return rep
        }

        let whole = try render(nil)
        for offset in [0.0, layout.drawnHeight * 9, layout.contentHeight - layout.drawnHeight] {
            let window = try #require(layout.drawnWindow(scrolledBy: offset))
            let windowed = try render(window)
            let scale = CGFloat(whole.pixelsHigh) / layout.contentHeight
            let top = Int((offset * scale).rounded(.down))
            let bottom = min(
                whole.pixelsHigh,
                Int(((offset + layout.drawnHeight) * scale).rounded(.up))
            )
            var differing = 0
            for y in top..<bottom {
                for x in stride(from: 0, to: whole.pixelsWide, by: 3) {
                    if whole.colorAt(x: x, y: y) != windowed.colorAt(x: x, y: y) { differing += 1 }
                }
            }
            #expect(differing == 0, "\(differing) pixels differ at offset \(offset)")
        }
    }
}

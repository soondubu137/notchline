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
}

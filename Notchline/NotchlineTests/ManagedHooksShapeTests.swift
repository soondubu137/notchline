import Foundation
import Testing
@testable import Notchline

/// Named-hook containers and list-shaped handlers (`ManagedHookDefinition.Shape`). Measured on
/// Antigravity CLI 1.2.2, 2026-09-11: tool events take matcher groups, lifecycle events take
/// handler lists, and a group under a list-shaped event disables the whole named hook.
struct ManagedHooksShapeTests {
    private let helper = "/bin/sh '/Users/someone/Library/Application Support/Notchline/agents/antigravity/hook.sh'"

    private var configuration: ManagedHooksConfiguration {
        .command(
            helper,
            containerKey: "notchline",
            definitions: [
                ManagedHookDefinition(event: "PreInvocation", matcher: nil, shape: .handlerList, argument: "PreInvocation"),
                ManagedHookDefinition(event: "Stop", matcher: nil, shape: .handlerList, argument: "Stop"),
                ManagedHookDefinition(event: "PreToolUse", matcher: "*", argument: "PreToolUse")
            ],
            descriptionForNewFiles: nil
        )
    }

    private let theirs: [String: Any] = [
        "lint-checker": [
            "PostToolUse": [
                ["matcher": "run_command", "hooks": [["type": "command", "command": "./scripts/lint.sh", "timeout": 10]]]
            ],
            "Stop": [["command": "./scripts/done.sh"]]
        ]
    ]

    private func handlers(_ root: [String: Any], _ event: String) -> [[String: Any]]? {
        (root["notchline"] as? [String: Any])?[event] as? [[String: Any]]
    }

    // MARK: - What is written

    /// Nothing is stamped at the root of a file this app creates.
    @Test
    func aListShapedDefinitionIsWrittenBareAndAGroupedOneInItsGroup() throws {
        let root = try configuration.installing(into: [:], isNewFile: true)
        #expect(root.keys.sorted() == ["notchline"])
        let stop = try #require(handlers(root, "Stop"))
        #expect(stop.count == 1)
        #expect(stop[0]["command"] as? String == "\(helper) Stop")
        #expect(stop[0]["type"] as? String == "command")
        #expect(stop[0]["timeout"] as? Int == ManagedHookDefinition.lifecycleTimeoutSeconds)
        #expect(stop[0]["hooks"] == nil, "a group here would disable every handler in the named hook")
        #expect(stop[0]["matcher"] == nil)
        let tool = try #require(handlers(root, "PreToolUse"))
        #expect(tool.count == 1)
        #expect(tool[0]["matcher"] as? String == "*")
        #expect((tool[0]["hooks"] as? [[String: Any]])?.first?["command"] as? String == "\(helper) PreToolUse")
        #expect(configuration.isFullyInstalled(in: root))
        #expect(configuration.registration(in: root) == .complete)
        #expect(configuration.eventsWhoseDefinitionChanges(comparedTo: root).isEmpty)
    }

    // MARK: - Beside the user's own

    @Test
    func theUsersHandlersSurviveInstallReinstallAndRemoval() throws {
        var original = theirs
        original["notchline"] = ["Stop": [["command": "./their-own.sh"]]]
        let before = try JSONSerialization.data(withJSONObject: original["lint-checker"]!, options: .sortedKeys)

        let installed = try configuration.installing(into: original, isNewFile: false)
        let twice = try configuration.installing(into: installed, isNewFile: false)
        for root in [installed, twice] {
            let lint = try JSONSerialization.data(withJSONObject: root["lint-checker"]!, options: .sortedKeys)
            #expect(lint == before)
            let stop = try #require(handlers(root, "Stop"))
            #expect(stop.map { $0["command"] as? String } == ["./their-own.sh", "\(helper) Stop"])
            #expect(configuration.isFullyInstalled(in: root))
        }

        let removed = try configuration.removing(from: twice)
        #expect(handlers(removed, "Stop")?.map { $0["command"] as? String } == ["./their-own.sh"])
        #expect(handlers(removed, "PreInvocation") == nil)
        #expect(handlers(removed, "PreToolUse") == nil)
        #expect(configuration.isFullyRemoved(from: removed))
        #expect(configuration.registration(in: removed) == .absent)
        let lint = try JSONSerialization.data(withJSONObject: removed["lint-checker"]!, options: .sortedKeys)
        #expect(lint == before)
    }

    @Test
    func anEmptiedContainerIsRemovedWithItsLastHandler() throws {
        let installed = try configuration.installing(into: theirs, isNewFile: false)
        let removed = try configuration.removing(from: installed)
        #expect(removed["notchline"] == nil)
        #expect(removed.keys.sorted() == ["lint-checker"])
    }

    // MARK: - Repair

    @Test
    func aStaleListHandlerIsReportedAndReplaced() throws {
        var installed = try configuration.installing(into: [:], isNewFile: true)
        var container = installed["notchline"] as! [String: Any]
        container["Stop"] = [["type": "command", "command": "\(helper) Stop", "timeout": 30]]
        installed["notchline"] = container

        #expect(!configuration.isFullyInstalled(in: installed))
        #expect(configuration.registration(in: installed) == .mismatched)
        #expect(configuration.eventsWhoseDefinitionChanges(comparedTo: installed) == ["Stop"])

        let repaired = try configuration.installing(into: installed, isNewFile: false)
        let stop = try #require(handlers(repaired, "Stop"))
        #expect(stop.count == 1)
        #expect(stop[0]["timeout"] as? Int == ManagedHookDefinition.lifecycleTimeoutSeconds)
        #expect(configuration.registration(in: repaired) == .complete)
    }

    // MARK: - Refusals

    @Test
    func anUnreadableListIsRefusedRatherThanOverwritten() throws {
        let root: [String: Any] = ["notchline": ["Stop": "./not-a-list.sh"]]
        #expect(throws: ManagedHooksConfigurationError.eventIsNotGroupArray(event: "Stop")) {
            try configuration.installing(into: root, isNewFile: false)
        }
        let removed = try configuration.removing(from: root)
        #expect((removed["notchline"] as? [String: Any])?["Stop"] as? String == "./not-a-list.sh")
    }

    @Test
    func theDefaultContainerIsStillHooks() throws {
        let classic = ManagedHooksConfiguration.command(
            helper,
            definitions: [ManagedHookDefinition(event: "Stop", matcher: nil)]
        )
        #expect(classic.containerKey == "hooks")
        let root = try classic.installing(into: [:], isNewFile: false)
        #expect(root.keys.sorted() == ["hooks"])
        let groups = try #require((root["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        #expect((groups.first?["hooks"] as? [[String: Any]])?.count == 1)
        #expect(classic.isFullyInstalled(in: root))
        #expect(try classic.removing(from: root).isEmpty)
    }
}

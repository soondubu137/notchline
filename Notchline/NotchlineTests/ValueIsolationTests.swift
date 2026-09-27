import Foundation
import Testing
@testable import Notchline

/// A value that an actor or a nonisolated source reads is a `nonisolated` type
/// (`system-architecture.md` §7). Under the app's MainActor default an unmarked value type is not
/// neutral: its computed members and synthesised `==` are MainActor-isolated, so the runtime reading
/// `agent.displayName` inside `await lifecycle.gate(…)` waited for the main thread on every refresh.
///
/// Each type below conforms to a protocol whose witness this file declares, and that witness takes
/// the type's own isolation. A `SendableMetatype` parameter refuses a MainActor-isolated
/// conformance, so a type that loses its mark stops this file compiling.
/// `TurnApprovalRoutingPin.Answer` is private, so nothing here pins it.
struct ValueIsolationTests {
    @Test func theValuesActorsReadAreNotMainActorIsolated() async {
        readOffTheMainActor(AgentKind.self)
        readOffTheMainActor(AgentPresence.self)
        readOffTheMainActor(SessionStatus.self)
        readOffTheMainActor(MonitorStatus.self)
        readOffTheMainActor(MonitorAvailability.self)
        readOffTheMainActor(MonitoredTurnState.self)
        readOffTheMainActor(AnswerHandle.self)
        readOffTheMainActor(JSONValue.self)
        readOffTheMainActor(TerminalHostRegistry.self)

        // The runtime half of an isolated conformance: a dynamic cast to it fails off its actor.
        let castOffTheMainActor = await Task.detached {
            [(AnswerHandle(ticket: 1) as Any) is any Hashable,
             (MonitorAvailability.ready as Any) is any Equatable,
             (JSONValue.null as Any) is any Equatable]
        }.value
        #expect(castOffTheMainActor == [true, true, true])
    }
}

private protocol ReadOffTheMainActor {
    static func probe()
}

private func readOffTheMainActor<Value: ReadOffTheMainActor & SendableMetatype>(_: Value.Type) {}

extension AgentKind: ReadOffTheMainActor { static func probe() {} }
extension AgentPresence: ReadOffTheMainActor { static func probe() {} }
extension SessionStatus: ReadOffTheMainActor { static func probe() {} }
extension MonitorStatus: ReadOffTheMainActor { static func probe() {} }
extension MonitorAvailability: ReadOffTheMainActor { static func probe() {} }
extension MonitoredTurnState: ReadOffTheMainActor { static func probe() {} }
extension AnswerHandle: ReadOffTheMainActor { static func probe() {} }
extension JSONValue: ReadOffTheMainActor { static func probe() {} }
extension TerminalHostRegistry: ReadOffTheMainActor { static func probe() {} }

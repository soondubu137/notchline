import Foundation

/// What a navigation attempt actually achieved. Codex reopens the exact thread; Claude Code
/// cannot focus an existing session, so its host is raised and the message must say so.
enum NavigationOutcome: Sendable, Equatable {
    case openedThread(host: String)
    case raisedApplication(host: String)
    case focusedTerminal(host: String)

    func message(forTitle title: String) -> String {
        switch self {
        case let .openedThread(host):
            "Opened in \(host): \(title)"
        case let .raisedApplication(host):
            "Raised \(host), but could not reach the session itself: \(title)"
        case let .focusedTerminal(host):
            "Brought \(host) to the front: \(title)"
        }
    }
}

@MainActor
protocol AgentNavigating: AnyObject {
    @discardableResult
    func open(_ session: MonitoredSession) async throws -> NavigationOutcome
}

enum AgentNavigationError: LocalizedError, Equatable {
    case noNavigator(AgentKind)

    var errorDescription: String? {
        switch self {
        case let .noNavigator(agent):
            "\(agent.displayName) sessions cannot be opened at the moment."
        }
    }
}

/// Sends each row to its product's navigator. Takes the whole session: a Codex row is a deep
/// link, a Claude Code row a process and a working directory.
@MainActor
final class AgentNavigationRouter: AgentNavigating {
    private let navigators: [AgentKind: any AgentNavigating]

    init(_ navigators: [AgentKind: any AgentNavigating]) {
        self.navigators = navigators
    }

    @discardableResult
    func open(_ session: MonitoredSession) async throws -> NavigationOutcome {
        guard let navigator = navigators[session.agent] else {
            throw AgentNavigationError.noNavigator(session.agent)
        }
        return try await navigator.open(session)
    }
}

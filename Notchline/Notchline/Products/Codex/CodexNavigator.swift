import Foundation

/// A CLI Thread is never reopened in Desktop as a side effect of clicking its row.
@MainActor
final class CodexNavigator: AgentNavigating {
    private let surfaces: CodexSurfaceLedger
    private let desktop: any AgentNavigating
    private let terminal: any AgentNavigating

    init(surfaces: CodexSurfaceLedger, desktop: any AgentNavigating, terminal: (any AgentNavigating)? = nil) {
        self.surfaces = surfaces
        self.desktop = desktop
        self.terminal = terminal ?? ProcessHostNavigator(
            sessions: surfaces,
            // SessionStart is delayed until submission after /new; it cannot prove the current view.
            allowsTerminalFocus: { _, _ in false }
        )
    }

    func open(_ session: MonitoredSession) async throws -> NavigationOutcome {
        if surfaces.isCLI(session.threadID) {
            return try await terminal.open(session)
        }
        guard surfaces.hasDesktop(session.threadID) else { throw CodexNavigationError.targetUnavailable }
        return try await desktop.open(session)
    }
}

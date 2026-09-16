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

    /// One liveness reading decides the target, so an owner that exited since the last refresh
    /// gives the same answer whichever surface it was: `sessionEnded`, from here, rather than one
    /// sentence from this navigator and another from whichever navigator the stale routing reached.
    func open(_ session: MonitoredSession) async throws -> NavigationOutcome {
        switch surfaces.navigableSurface(ofThread: session.threadID) {
        case .desktop: return try await desktop.open(session)
        case .cli: return try await terminal.open(session)
        case nil: throw CodexNavigationError.sessionEnded
        }
    }
}

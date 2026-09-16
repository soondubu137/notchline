import AppKit
import Foundation

protocol CodexNavigationTargetChecking: Sendable {
    func isThreadNavigable(_ threadID: String) async throws -> Bool
}

enum CodexNavigationError: LocalizedError, Equatable {
    case invalidThreadID
    case targetUnavailable
    /// No live execution owns the Thread any more, on either surface. Distinct from
    /// ``targetUnavailable``, which is Codex answering that the Thread itself is gone.
    case sessionEnded
    case validationFailed
    case desktopUnavailable
    case openRejected

    var errorDescription: String? {
        switch self {
        case .invalidThreadID:
            "The session identifier is not valid."
        case .targetUnavailable:
            "That session has been archived, deleted, or is no longer available."
        case .sessionEnded:
            "That session has ended and can no longer be opened."
        case .validationFailed:
            "Could not confirm that the session still exists; please try again shortly."
        case .desktopUnavailable:
            "Codex Desktop was not found."
        case .openRejected:
            "Codex Desktop did not accept the request to open the session."
        }
    }
}

enum CodexDeepLink {
    nonisolated static func threadURL(threadID: String) throws -> URL {
        guard !threadID.isEmpty else {
            throw CodexNavigationError.invalidThreadID
        }

        let allowedCharacters = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        guard let encodedThreadID = threadID.addingPercentEncoding(
            withAllowedCharacters: allowedCharacters
        ), !encodedThreadID.isEmpty,
        let url = URL(string: "codex://threads/\(encodedThreadID)") else {
            throw CodexNavigationError.invalidThreadID
        }
        return url
    }
}

@MainActor
protocol CodexWorkspaceOpening: AnyObject {
    func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL?
    func open(_ url: URL, withApplicationAt applicationURL: URL) async throws
}

@MainActor
final class AppKitCodexWorkspace: CodexWorkspaceOpening {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func open(_ url: URL, withApplicationAt applicationURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            workspace.open(
                [url],
                withApplicationAt: applicationURL,
                configuration: configuration
            ) { application, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if application == nil {
                    continuation.resume(throwing: CodexNavigationError.openRejected)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

@MainActor
final class CodexDesktopNavigator: AgentNavigating {
    static let desktopBundleIdentifier = "com.openai.codex"
    static let desktopDisplayName = "Codex Desktop"

    private let targetChecker: any CodexNavigationTargetChecking
    private let workspace: any CodexWorkspaceOpening

    init(
        targetChecker: any CodexNavigationTargetChecking,
        workspace: (any CodexWorkspaceOpening)? = nil
    ) {
        self.targetChecker = targetChecker
        self.workspace = workspace ?? AppKitCodexWorkspace()
    }

    @discardableResult
    func open(_ session: MonitoredSession) async throws -> NavigationOutcome {
        let threadID = session.threadID
        let deepLink = try CodexDeepLink.threadURL(threadID: threadID)

        let isNavigable: Bool
        do {
            isNavigable = try await targetChecker.isThreadNavigable(threadID)
        } catch {
            throw CodexNavigationError.validationFailed
        }
        guard isNavigable else {
            throw CodexNavigationError.targetUnavailable
        }

        guard let applicationURL = workspace.applicationURL(
            forBundleIdentifier: Self.desktopBundleIdentifier
        ) else {
            throw CodexNavigationError.desktopUnavailable
        }

        do {
            try await workspace.open(
                deepLink,
                withApplicationAt: applicationURL
            )
        } catch let error as CodexNavigationError {
            throw error
        } catch {
            throw CodexNavigationError.openRejected
        }
        return .openedThread(host: Self.desktopDisplayName)
    }
}

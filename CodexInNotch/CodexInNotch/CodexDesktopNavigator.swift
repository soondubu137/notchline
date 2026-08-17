import AppKit
import Foundation

protocol CodexNavigationTargetChecking: Sendable {
    func isThreadNavigable(_ threadID: String) async throws -> Bool
}

/// What a navigation attempt actually achieved.
///
/// Codex returns to the exact thread. Claude Code cannot — there is no
/// supported way to focus a session that already exists, so the best available
/// answer is raising its host. The row deliberately draws no mark for that
/// difference, because a row carries exactly one mark and the elapsed time has
/// it. That makes it all the more important that the sentence the user reads
/// afterwards says what really happened, instead of claiming what Codex would
/// have done.
enum NavigationOutcome: Sendable, Equatable {
    /// The exact turn was reopened in its own host.
    case openedThread(host: String)
    /// The host was raised, but not the session inside it.
    case raisedApplication(host: String)
    /// The terminal running the session was brought forward.
    case focusedTerminal(host: String)

    func message(forTitle title: String) -> String {
        switch self {
        case let .openedThread(host):
            "已在 \(host) 中打开：\(title)"
        case let .raisedApplication(host):
            "已唤起 \(host)，但无法定位到具体会话：\(title)"
        case let .focusedTerminal(host):
            "已聚焦 \(host)：\(title)"
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
            "\(agent.displayName) 会话暂时无法打开。"
        }
    }
}

/// Sends each row to the navigator for its own product.
///
/// The whole session is passed rather than a thread id: a Codex row is a deep
/// link, and a Claude Code row is a process and a working directory. There is
/// no identifier both of them fit inside.
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

enum CodexNavigationError: LocalizedError, Equatable {
    case invalidThreadID
    case targetUnavailable
    case validationFailed
    case desktopUnavailable
    case openRejected

    var errorDescription: String? {
        switch self {
        case .invalidThreadID:
            "会话标识无效。"
        case .targetUnavailable:
            "该会话已被归档、删除或不再可用。"
        case .validationFailed:
            "暂时无法确认该会话仍然存在，请稍后重试。"
        case .desktopUnavailable:
            "未找到 Codex Desktop。"
        case .openRejected:
            "Codex Desktop 未能接受打开会话的请求。"
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

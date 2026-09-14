import Foundation

/// Native setup is optional and separate from observation availability.
enum ProductSetup: Sendable {
    case none
    case managedHooks(SetupDescription)
    case companionExtension

    var isConfigurable: Bool {
        if case .none = self { return false }
        return true
    }

    var installedMessage: String {
        switch self {
        case .none: "This product needs no setup."
        case let .managedHooks(description): description.installedMessage
        case .companionExtension: "Companion installed. Reopen Trae’s windows to connect."
        }
    }
    var removedMessage: String {
        switch self {
        case .none: "This product needs no setup."
        case let .managedHooks(description): description.removedMessage
        case .companionExtension: "Notchline’s Trae companion has been removed."
        }
    }

    var switchHelp: String {
        switch self {
        case .none: "This product needs no setup."
        case let .managedHooks(description): description.switchHelp
        case .companionExtension: "Installs or removes Notchline’s companion extension in Trae. Reopen Trae’s windows after installation."
        }
    }

    var managedHooks: SetupDescription? {
        guard case let .managedHooks(description) = self else { return nil }
        return description
    }
}


/// Everything the app needs to know about a product before building its Provider: its name,
/// how its integration is set up, and how to make the Provider and navigator. The store,
/// Settings rows and their sentences all read these values (`tiered-support.md` §5.1).
struct ProductDescriptor: Sendable {
    let kind: AgentKind
    /// The row's label in Settings and first run; Codex names its Desktop app.
    let settingsTitle: String
    let setup: ProductSetup
    /// Builds the Provider and navigator together: the Codex navigator pre-flights a click against
    /// the Provider's App Server connection.
    let make: @MainActor @Sendable () -> ProductModule
    /// The `Watches` paragraph of the row's ⓘ popover; nil where the product's name says it.
    /// `docs/product-support.md` holds the complete coverage matrix.
    let watches: String?
    /// The `Not shown` paragraph of the popover: what this product's rows will never say (e.g. a
    /// product without wait detection draws waits as `Running`; `docs/product-support.md` §2). Nil
    /// when no broad boundary needs declaring.
    let notShown: String?

    init(
        kind: AgentKind,
        settingsTitle: String,
        setup: ProductSetup,
        watches: String? = nil,
        notShown: String? = nil,
        make: @escaping @MainActor @Sendable () -> ProductModule
    ) {
        self.kind = kind
        self.settingsTitle = settingsTitle
        self.setup = setup
        self.watches = watches
        self.notShown = notShown
        self.make = make
    }

    var displayName: String {
        kind.displayName
    }
}

struct ProductModule {
    let service: any AgentMonitoring
    let navigator: any AgentNavigating
}

/// How one product's observation is put in place, in the terms Settings explains it in. Every
/// sentence about the file derives from the same values the writer uses.
struct SetupDescription: Sendable {
    let configurationFileRelativeToHome: String
    /// How many definitions this build writes there, read off the vocabulary, never typed.
    let definitionCount: Int
    /// What the user must do after the write before the product runs the hooks, or nil. Phrased to
    /// follow a semicolon.
    let trustStep: String?
    /// What `Connected` can claim beyond having been reached (`integration-settings-behaviour.md`
    /// §5); a hook-only product claims only that its hooks are in place.
    let connectedDetail: String

    /// The file as the user knows it: `~/.codex/hooks.json`.
    var displayPath: String {
        "~/" + configurationFileRelativeToHome
    }

    /// `hooks.json.notchline-backup`, beside the file.
    var backupName: String {
        URL(fileURLWithPath: configurationFileRelativeToHome).lastPathComponent
            + ".notchline-backup"
    }

    func configurationFile(fileManager: FileManager) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(configurationFileRelativeToHome)
    }

    var switchHelp: String {
        "Adds or removes Notchline's \(definitionCount) lifecycle definitions in "
            + "\(displayPath) together, after copying that file to \(backupName)."
    }

    /// What to say once the definitions are in the file. A product with a trust step gets only that
    /// step; the backup disclosure is in the footnote under the rows.
    var installedMessage: String {
        if let trustStep {
            return "Hooks installed; \(trustStep)."
        }
        return "Hooks written to \(displayPath). Your file as it was is beside it, "
            + "as \(backupName)."
    }

    var removedMessage: String {
        "The hooks managed by Notchline have been removed from \(displayPath); "
            + "nothing else in it was touched."
    }
}

enum ProductRegistry {
    /// Every product this build knows, in `AgentKind` declaration order (a test holds them together).
    static let builtIn: [ProductDescriptor] = [
        ProductDescriptor(
            kind: .codex,
            settingsTitle: "Codex Desktop",
            setup: .managedHooks(SetupDescription(
                configurationFileRelativeToHome: ".codex/hooks.json",
                definitionCount: CodexHookVocabulary().managedDefinitions.count,
                trustStep: "open /hooks in Codex and trust the new definitions",
                connectedDetail: "compatible version"
            )),
            make: {
                let service = LiveCodexMonitorService()
                return ProductModule(
                    service: service,
                    navigator: CodexDesktopNavigator(targetChecker: service)
                )
            }
        ),
        ProductDescriptor(
            kind: .claudeCode,
            settingsTitle: "Claude Code",
            setup: .managedHooks(SetupDescription(
                configurationFileRelativeToHome: ".claude/settings.json",
                definitionCount: ClaudeCodeHookVocabulary().managedDefinitions.count,
                trustStep: nil,
                connectedDetail: "hooks installed"
            )),
            make: {
                let service = ClaudeCodeMonitorService()
                return ProductModule(
                    service: service,
                    // Raises the host rather than reopening the session: the declared boundary (ADR 0004).
                    navigator: ProcessHostNavigator(sessions: service)
                )
            }
        ),
        ProductDescriptor(
            kind: .antigravity,
            // One switch for Desktop and the CLI: both read the one hooks file it writes.
            settingsTitle: "Antigravity",
            setup: .managedHooks(SetupDescription(
                configurationFileRelativeToHome: AntigravityHookVocabulary.hooksFileRelativeToHome,
                definitionCount: AntigravityHookVocabulary().managedDefinitions.count,
                trustStep: nil,
                connectedDetail: "hooks installed"
            )),
            watches: "Antigravity Desktop and Antigravity CLI.",
            notShown: "Approvals and questions. An active Turn reads Working... until it ends, "
                + "and a Turn stopped early may keep reading it. Usage quota.",
            make: {
                // A conversation's surface comes from its transcript path, recorded once by the translator.
                let surfaces = AntigravitySurfaceLedger()
                // One kernel reading answers the CLI's presence, admission and process; Desktop's presence is
                // its application running.
                let conversations = AntigravityConversationScanner()
                let desktop = AntigravityDesktopApplication()
                let sessions = AntigravitySessions(cli: conversations, desktop: desktop, surfaces: surfaces)
                let service = HookProductProvider(
                    agent: .antigravity,
                    hooks: HookLifecycleSource(
                        paths: .live(for: .antigravity),
                        vocabulary: AntigravityHookVocabulary(
                            translator: AntigravityPayloadTranslator(surfaces: surfaces)
                        )
                    ),
                    sessions: sessions,
                    // Desktop files a conversation under a Project of its own.
                    rowContent: AntigravityRowContent(surfaces: surfaces, projects: AntigravityDesktopProjects()),
                    // A CLI row is read at its terminal; a Desktop row by Desktop's own viewed record.
                    readEvidence: AntigravityReadEvidence(
                        surfaces: surfaces,
                        terminal: TerminalReadEvidence(sessions: sessions)
                    )
                )
                return ProductModule(
                    service: service,
                    navigator: AntigravityNavigator(
                        surfaces: surfaces,
                        desktop: desktop,
                        terminal: ProcessHostNavigator(sessions: sessions)
                    )
                )
            }
        ),
        ProductDescriptor(
            kind: .trae, settingsTitle: "Trae Desktop", setup: .companionExtension,
            watches: "Trae 3.5.91 local IDE Threads. Requests are read here and answered in Trae. "
                + "Visible completed Turns clear in IDE and IDE-hosted SOLO, including multiple windows.",
            notShown: "Complete SOLO progress/approval coverage, standalone SOLO, Plan/Spec, remote work and usage quota.",
            make: {
                let service = TraeProvider()
                return ProductModule(service: service, navigator: TraeNavigator(transport: service.source.transport))
            }
        )
    ]

    static func descriptor(for kind: AgentKind) -> ProductDescriptor {
        guard let descriptor = builtIn.first(where: { $0.kind == kind }) else {
            preconditionFailure("\(kind) has no ProductDescriptor; add it to ProductRegistry.builtIn")
        }
        return descriptor
    }

    /// The products as one spoken list: `Codex and Claude Code`.
    static var spokenNames: String {
        let names = builtIn.map(\.displayName)
        guard names.count > 1, let last = names.last else {
            return names.joined()
        }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    static var spokenConfigurationFiles: String {
        let paths = builtIn.compactMap { $0.setup.managedHooks?.displayPath }
        guard paths.count > 1, let last = paths.last else {
            return paths.joined()
        }
        return paths.dropLast().joined(separator: ", ") + " or " + last
    }
}

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


/// Everything the app needs to know about a product before it has built the
/// product's Provider: what to call it, how its integration is set up, and how
/// to make the Provider and its navigator.
///
/// One value per product, held in ``ProductRegistry/builtIn``. The store's
/// composition root, the Settings rows and the sentences under them are all
/// read off these values, so adding a product is adding an element here rather
/// than editing each of those places by hand. Before this existed, Settings
/// drew two rows by hand and its help text said "five" definitions for a
/// product that had seven — prose about a product drifts, a value read from
/// the product does not.
///
/// See [`tiered-support.md`](../../docs/technical-explorations/multi-product-provider-architecture/tiered-support.md)
/// §5.1.
struct ProductDescriptor: Sendable {
    let kind: AgentKind
    /// The row's label in Settings and first run. The product's own name
    /// suffices for most; Codex is watched through its Desktop app and says so.
    let settingsTitle: String
    let setup: ProductSetup
    /// Builds the Provider and the navigator that answers a click on its rows,
    /// together, because the Codex navigator pre-flights a click against the
    /// Provider's own App Server connection.
    let make: @MainActor @Sendable () -> ProductModule
    /// What Notchline watches of this product, in the product's own surfaces
    /// and modes: the `Watches` paragraph of the row's ⓘ popover.
    ///
    /// Nil where the product's name already says it. Neither this nor
    /// ``notShown`` claims every request form or independent capability is
    /// supported; `docs/product-support.md` holds the complete coverage matrix.
    let watches: String?
    /// What this product's rows will never say: the `Not shown` paragraph of the
    /// popover.
    ///
    /// A product without wait detection draws an active Turn as `Running`,
    /// with the same mark as every other — the row carries one mark and it is
    /// the timer — and says here, once, that a wait is not among the things it
    /// can show (`docs/product-support.md` §2). Nil when no broad boundary needs
    /// declaring.
    ///
    /// Two fields rather than the one sentence the row's caption used to carry,
    /// because the popover heads them apart and a caption is one line now
    /// (`figma-design.md` §8.1).
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

/// The Provider and its navigator, as one product contributes them.
struct ProductModule {
    let service: any AgentMonitoring
    let navigator: any AgentNavigating
}

/// How one product's observation is put in place, in the terms Settings has to
/// explain it in.
///
/// Both shipping products register hooks in a file of their own, and differ in
/// whether a trust step follows the write and in what `Connected` can honestly
/// claim. Every sentence Settings says about the file is derived here, from the
/// same values the writer uses, so the count, the path and the backup name
/// cannot disagree with what actually happens.
struct SetupDescription: Sendable {
    /// The file the definitions are written into, relative to the user's home.
    let configurationFileRelativeToHome: String
    /// How many definitions this build writes there — read off the vocabulary,
    /// never typed.
    let definitionCount: Int
    /// What the user has to do after the write before the product runs the
    /// hooks, or nil for a product that runs what is registered. Phrased as an
    /// instruction that can follow a semicolon.
    let trustStep: String?
    /// What `Connected` can claim beyond having been reached. The App Server
    /// answers `initialize` and has not refused a method, which is what
    /// `compatible version` means (`integration-settings-behaviour.md` §5); a
    /// hook-only product can claim no more than that its hooks are in place.
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

    /// The switch's tooltip.
    var switchHelp: String {
        "Adds or removes Notchline's \(definitionCount) lifecycle definitions in "
            + "\(displayPath) together, after copying that file to \(backupName)."
    }

    /// What to say once the definitions are in the file.
    ///
    /// A product with a trust step gets that step and nothing else: the message
    /// has a required action to carry and a second sentence would compete with
    /// it. The disclosure about the backup lands before the switch is flipped,
    /// in the footnote under the rows.
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
    /// Every product this build knows, in display order.
    ///
    /// The order here is `AgentKind`'s declaration order and a test holds the
    /// two together: the enum still decides ordering wherever a row or a footer
    /// group is sorted, and this list is what the store and Settings iterate.
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
                    // Raises the host rather than reopening the session, which
                    // is the declared boundary rather than a fallback -- see
                    // ADR 0004 and ``ProcessHostNavigator``.
                    navigator: ProcessHostNavigator(sessions: service)
                )
            }
        ),
        ProductDescriptor(
            kind: .antigravity,
            // Desktop and the CLI, which read the one hooks file this switch
            // writes: a switch per surface could not be honest about it.
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
                // Which surface a conversation is on is what its events' transcript
                // path says, recorded once by the translator and read by every
                // source that treats the two differently.
                let surfaces = AntigravitySurfaceLedger()
                // One kernel reading answers the CLI's presence, admission and
                // which process a row's conversation is running in; Desktop's are
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
                    // A CLI row is read at its terminal; a Desktop row by
                    // Desktop's own record of the conversation being viewed.
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
            watches: "Trae 3.5.91 in local IDE mode. Command approvals and questions are read here "
                + "and answered in Trae.",
            notShown: "SOLO, Plan/Spec, remote work, read removal and usage quota.",
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

    /// The files the switches write, as one spoken list.
    static var spokenConfigurationFiles: String {
        let paths = builtIn.compactMap { $0.setup.managedHooks?.displayPath }
        guard paths.count > 1, let last = paths.last else {
            return paths.joined()
        }
        return paths.dropLast().joined(separator: ", ") + " or " + last
    }
}

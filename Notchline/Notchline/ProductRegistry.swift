import Foundation

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
    let setup: SetupDescription
    /// Builds the Provider and the navigator that answers a click on its rows,
    /// together, because the Codex navigator pre-flights a click against the
    /// Provider's own App Server connection.
    let make: @MainActor @Sendable () -> ProductModule

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
            setup: SetupDescription(
                configurationFileRelativeToHome: ".codex/hooks.json",
                definitionCount: CodexHookVocabulary().managedDefinitions.count,
                trustStep: "open /hooks in Codex and trust the new definitions",
                connectedDetail: "compatible version"
            ),
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
            setup: SetupDescription(
                configurationFileRelativeToHome: ".claude/settings.json",
                definitionCount: ClaudeCodeHookVocabulary().managedDefinitions.count,
                trustStep: nil,
                connectedDetail: "hooks installed"
            ),
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
        let paths = builtIn.map(\.setup.displayPath)
        guard paths.count > 1, let last = paths.last else {
            return paths.joined()
        }
        return paths.dropLast().joined(separator: ", ") + " or " + last
    }
}

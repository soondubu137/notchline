import AppKit
import Foundation

/// What Trae's own extension manifest says about ``TraeInstallation/extensionID``,
/// read fresh rather than remembered — the parallel of `HookRegistration` for
/// a product with no hooks file.
nonisolated enum TraeCompanionRegistration: Sendable, Equatable {
    /// Nothing under that ID is in Trae's manifest.
    case absent
    /// Something is, but not the version this build installs.
    case mismatched
    /// Exactly the version this build expects.
    case current
}

/// Installs one owned companion with Trae's extension CLI. No Hooks,
/// application bundle or authentication files are edited by this
/// integration, and installation never edits anything but through that CLI.
/// Removal edits Trae's own extension manifest directly, but only as a
/// fallback when that same CLI cannot do the removal itself -- see
/// ``remove()``.
///
/// **Trae's own extension manifest is the only source of truth for "is it
/// installed".** This used to be a marker Notchline wrote to its own support
/// directory after a successful install, deleted after a successful removal —
/// a private belief that only this app's own code path could update. A
/// companion removed any other way (Trae's Extensions view, deleting the
/// folder, a corrupt profile) left that belief uncorrected: Settings went on
/// reporting "Installed, reopen the Trae window to connect" forever, because
/// reopening Trae can never make an absent extension connect. Worse, turning
/// the switch off then called `--uninstall-extension` on an extension already
/// gone, which exits non-zero, threw before the marker could be deleted, and
/// snapped the switch back on -- a state with no way out.
///
/// Reading `~/.trae/extensions/extensions.json` -- the same file Trae's own
/// CLI consults for `--list-extensions` -- answers the actual question
/// instead of a cached opinion about it, at the cost of one small JSON read
/// per check rather than a process spawn. A companion present at the wrong
/// version reads ``TraeCompanionRegistration/mismatched``, the same shape
/// `HookRegistration.mismatched` already gives the hooks-based products, so
/// Settings can offer the same recovery: switch shows off, turning it on
/// reinstalls.
nonisolated struct TraeInstallation: Sendable {
    static let traeVersion = "3.5.91"
    static let companionVersion = "1.2.0"
    static let extensionID = "notchline.trae-companion"
    let application: URL
    let directory: URL
    let resources: URL
    let extensionsManifest: URL

    init(application: URL = URL(fileURLWithPath: "/Applications/Trae.app"),
         directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Notchline/agents/trae"),
         resources: URL = Bundle.main.resourceURL ?? URL(fileURLWithPath: "/"),
         extensionsManifest: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".trae/extensions/extensions.json")) {
        self.application = application; self.directory = directory; self.resources = resources
        self.extensionsManifest = extensionsManifest
    }
    /// What Trae itself currently has registered for ``extensionID``, read
    /// fresh from its own manifest rather than trusted from a prior install.
    var registration: TraeCompanionRegistration {
        guard let data = try? Data(contentsOf: extensionsManifest),
              let entries = try? JSONDecoder().decode([ManifestEntry].self, from: data),
              let installed = entries.first(where: { $0.identifier.id.caseInsensitiveCompare(Self.extensionID) == .orderedSame })
        else { return .absent }
        return installed.version == Self.companionVersion ? .current : .mismatched
    }
    var compatible: Bool {
        Bundle(url: application)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == Self.traeVersion
    }
    private struct ManifestEntry: Decodable {
        struct Identifier: Decodable { let id: String }
        let identifier: Identifier
        let version: String
    }

    func install() async throws {
        try await Task.detached {
            guard compatible else { throw TraeBridgeError.version }
            let fm = FileManager.default
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let staging = fm.temporaryDirectory.appendingPathComponent("notchline-trae-install-\(UUID().uuidString)")
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging) }
            let archive = try package(in: staging)
            try run(application.appendingPathComponent("Contents/Resources/app/bin/trae"),
                    arguments: ["--install-extension", archive.path, "--force"])
        }.value
    }

    /// Idempotent: a companion Trae has already lost has nothing left to
    /// uninstall, and Trae's CLI exits 1 for that ("is not installed"),
    /// which the switch must not read as a failed removal.
    ///
    /// **Trae 3.5.91's own `--uninstall-extension` crashes unconditionally**
    /// -- `Cannot read properties of undefined (reading 'isProtectedExtension')`,
    /// thrown before it ever reaches the extension being removed. Verified
    /// independently of this companion's shape, in an isolated profile with
    /// no Trae Desktop instance attached: a plain control extension with none
    /// of this companion's manifest fields fails the identical way. So the
    /// official CLI path cannot remove anything right now, on any build of
    /// Trae running this version, and retrying it changes nothing.
    ///
    /// The fallback does directly what a working uninstall would have:
    /// delete this extension's own folder and its one entry in
    /// ``extensionsManifest``, leaving every other installed extension's
    /// entry untouched. Reopening Trae's windows is required afterward, the
    /// same requirement install already carries -- a running window's
    /// in-memory extension list is not expected to notice a manifest edit
    /// underneath it before then, which is exactly the state a real
    /// uninstall through the CLI would also have left it in.
    func remove() async throws {
        try await Task.detached {
            guard registration != .absent else { return }
            do {
                try run(application.appendingPathComponent("Contents/Resources/app/bin/trae"),
                        arguments: ["--uninstall-extension", Self.extensionID])
            } catch {
                try removeFromManifestDirectly()
            }
        }.value
    }

    /// Bypasses Trae's broken uninstall command by editing its manifest
    /// directly. Reads and rewrites the whole entry list as loose JSON
    /// rather than through ``ManifestEntry`` -- decoding every entry into
    /// that narrow shape and re-encoding them would silently drop every
    /// field of every *other* installed extension this app does not model.
    private func removeFromManifestDirectly() throws {
        let failureMessage = "Trae's extension manifest could not be changed. "
            + "Remove \"Notchline Companion\" from Trae's Extensions view instead."
        guard let data = try? Data(contentsOf: extensionsManifest),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { throw TraeBridgeError.installation(failureMessage) }
        var removedFolder: String?
        let remaining = entries.filter { entry in
            guard let id = (entry["identifier"] as? [String: Any])?["id"] as? String,
                  id.caseInsensitiveCompare(Self.extensionID) == .orderedSame else { return true }
            let version = entry["version"] as? String ?? Self.companionVersion
            removedFolder = entry["relativeLocation"] as? String ?? "\(id)-\(version)"
            return false
        }
        // Already gone by the time this read completes; nothing left to do.
        guard remaining.count < entries.count else { return }
        guard let rewritten = try? JSONSerialization.data(withJSONObject: remaining) else {
            throw TraeBridgeError.installation(failureMessage)
        }
        try rewritten.write(to: extensionsManifest, options: .atomic)
        if let removedFolder {
            try? FileManager.default.removeItem(at: extensionsManifest.deletingLastPathComponent()
                .appendingPathComponent(removedFolder))
        }
    }

    /// Also used by the isolated installation acceptance fixture.
    func package(in staging: URL) throws -> URL {
        let fm = FileManager.default
        let root = staging.appendingPathComponent("package")
        let extensionDirectory = root.appendingPathComponent("extension")
        try fm.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["name":"trae-companion", "publisher":"notchline", "version":Self.companionVersion,
            "displayName":"Notchline Companion", "description":"Read local Trae IDE progress and requests in Notchline.",
            "engines":["vscode":"^1.107.0"], "main":"./extension.js", "activationEvents":["onStartupFinished"],
            "extensionKind":["ui"], "enabledApiProposals":["icube"], "license":"GPL-3.0-or-later", "icon":"icon.png"]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: extensionDirectory.appendingPathComponent("package.json"))
        try fm.copyItem(at: resources.appendingPathComponent("trae-extension.js"),
                        to: extensionDirectory.appendingPathComponent("extension.js"))
        try fm.copyItem(at: resources.appendingPathComponent("companion-icon.png"),
                        to: extensionDirectory.appendingPathComponent("icon.png"))
        var bridge = try Data(contentsOf: resources.appendingPathComponent("trae-projection.js"))
        bridge.append(try Data(contentsOf: resources.appendingPathComponent("trae-renderer.js")))
        try bridge.write(to: extensionDirectory.appendingPathComponent("bridge-v1.js"))
        let types = """
        <?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="json" ContentType="application/json"/><Default Extension="js" ContentType="application/javascript"/><Default Extension="vsixmanifest" ContentType="text/xml"/><Default Extension="png" ContentType="image/png"/></Types>
        """
        try Data(types.utf8).write(to: root.appendingPathComponent("[Content_Types].xml"))
        let vsix = """
        <?xml version="1.0" encoding="utf-8"?>
        <PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011"><Metadata><Identity Language="en-US" Id="trae-companion" Version="\(Self.companionVersion)" Publisher="notchline"/><DisplayName>Notchline Companion</DisplayName><Description xml:space="preserve">Read local Trae IDE progress and requests in Notchline.</Description><Icon>extension/icon.png</Icon><Tags/><Categories>Other</Categories><GalleryFlags>Public</GalleryFlags><Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.107.0"/></Properties></Metadata><Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation><Dependencies/><Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/><Asset Type="Microsoft.VisualStudio.Services.Icons.Default" Path="extension/icon.png" Addressable="true"/></Assets></PackageManifest>
        """
        try Data(vsix.utf8).write(to: root.appendingPathComponent("extension.vsixmanifest"))
        let archive = staging.appendingPathComponent("notchline-trae.vsix")
        try run(URL(fileURLWithPath: "/usr/bin/ditto"), arguments: ["-c", "-k", "--norsrc", root.path, archive.path])
        return archive
    }

    private func run(_ executable: URL, arguments: [String]) throws {
        let process = Process()
        process.executableURL = executable; process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        // No captured user content or unlimited pipe buffer. CLI failures have
        // an actionable fixed message; these operations carry no model request.
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(45)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); throw TraeBridgeError.installation("Trae's extension installer did not finish. Reopen Trae and try again.") }
        guard process.terminationStatus == 0 else { throw TraeBridgeError.installation("Trae could not change the companion installation. Check its Extensions view and try again.") }
    }
}

import AppKit
import Foundation

/// Trae's own extension manifest entry for ``TraeInstallation/extensionID``, read fresh.
nonisolated enum TraeCompanionRegistration: Sendable, Equatable {
    case absent
    case mismatched
    case current
}

/// Installs one owned companion through Trae's extension CLI; no Hooks, bundle or auth files
/// are edited. Installed state is read from `~/.trae/extensions/extensions.json`, never a marker
/// of our own, so a companion removed elsewhere reads absent.
nonisolated struct TraeInstallation: Sendable {
    static let traeVersion = "3.5.91"
    static let companionVersion = "1.2.1"
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

    /// Idempotent: Trae's CLI exits 1 for a companion already gone.
    ///
    /// Trae 3.5.91's `--uninstall-extension` always crashes (`isProtectedExtension`), so this
    /// deletes the extension's folder and its one ``extensionsManifest`` entry. Trae's windows must
    /// be reopened afterwards.
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

    /// Loose JSON, not ``ManifestEntry``: re-encoding would drop other extensions' unmodelled fields.
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
        // No captured user content or unbounded pipe buffer.
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(45)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); throw TraeBridgeError.installation("Trae's extension installer did not finish. Reopen Trae and try again.") }
        guard process.terminationStatus == 0 else { throw TraeBridgeError.installation("Trae could not change the companion installation. Check its Extensions view and try again.") }
    }
}

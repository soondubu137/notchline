import AppKit
import Foundation

/// Installs one owned companion with Trae's extension CLI. No Hooks, settings,
/// application bundle or authentication files are edited by this integration.
nonisolated struct TraeInstallation: Sendable {
    static let traeVersion = "3.5.91"
    static let companionVersion = "1.0.0"
    static let extensionID = "notchline.trae-companion"
    let application: URL
    let directory: URL
    let resources: URL

    init(application: URL = URL(fileURLWithPath: "/Applications/Trae.app"),
         directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Notchline/agents/trae"),
         resources: URL = Bundle.main.resourceURL ?? URL(fileURLWithPath: "/")) {
        self.application = application; self.directory = directory; self.resources = resources
    }
    var marker: URL { directory.appendingPathComponent("installation.json") }
    var installed: Bool {
        guard let data = try? Data(contentsOf: marker),
              let value = try? JSONDecoder().decode(Registration.self, from: data) else { return false }
        return value.version == Self.companionVersion
    }
    var compatible: Bool {
        Bundle(url: application)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == Self.traeVersion
    }
    private struct Registration: Codable { let version: String }

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
            try JSONEncoder().encode(Registration(version: Self.companionVersion)).write(to: marker, options: .atomic)
        }.value
    }

    func remove() async throws {
        try await Task.detached {
            try run(application.appendingPathComponent("Contents/Resources/app/bin/trae"),
                    arguments: ["--uninstall-extension", Self.extensionID])
            if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
        }.value
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
            "extensionKind":["ui"], "enabledApiProposals":["icube"], "license":"GPL-3.0-or-later"]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: extensionDirectory.appendingPathComponent("package.json"))
        try fm.copyItem(at: resources.appendingPathComponent("trae-extension.js"),
                        to: extensionDirectory.appendingPathComponent("extension.js"))
        var bridge = try Data(contentsOf: resources.appendingPathComponent("trae-projection.js"))
        bridge.append(try Data(contentsOf: resources.appendingPathComponent("trae-renderer.js")))
        try bridge.write(to: extensionDirectory.appendingPathComponent("bridge-v1.js"))
        let types = """
        <?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="json" ContentType="application/json"/><Default Extension="js" ContentType="application/javascript"/><Default Extension="vsixmanifest" ContentType="text/xml"/></Types>
        """
        try Data(types.utf8).write(to: root.appendingPathComponent("[Content_Types].xml"))
        let vsix = """
        <?xml version="1.0" encoding="utf-8"?>
        <PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011"><Metadata><Identity Language="en-US" Id="trae-companion" Version="\(Self.companionVersion)" Publisher="notchline"/><DisplayName>Notchline Companion</DisplayName><Description xml:space="preserve">Read local Trae IDE progress and requests in Notchline.</Description><Tags/><Categories>Other</Categories><GalleryFlags>Public</GalleryFlags><Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.107.0"/></Properties></Metadata><Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation><Dependencies/><Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets></PackageManifest>
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

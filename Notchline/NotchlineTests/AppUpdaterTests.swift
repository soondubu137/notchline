import Foundation
import Testing
@testable import Notchline

/// Every shipped copy reads its feed from a URL compiled into it, so the URL, the file it names
/// and the shape of that file are contracts with copies that already exist (`docs/adr/0022`).
struct AppUpdaterTests {
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let feedURL =
        "https://raw.githubusercontent.com/soondubu137/notchline/master/appcast.xml"

    @Test func theBuiltAppReadsTheFeedOnMaster() {
        // `Bundle.main` is the app: the tests are hosted inside it.
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String == Self.feedURL)
    }

    @Test func theFeedURLNamesTheFeedFileAtTheRepositoryRoot() throws {
        let path = try #require(URL(string: Self.feedURL)).lastPathComponent
        #expect(FileManager.default.fileExists(
            atPath: Self.repositoryRoot.appendingPathComponent(path).path
        ))
    }

    @Test func noUpdaterStartsWithoutAPublicKey() throws {
        #expect(!AppUpdater.hasPublicKey(try bundle(info: [:])))
        #expect(!AppUpdater.hasPublicKey(try bundle(info: ["SUPublicEDKey": ""])))
        #expect(!AppUpdater.hasPublicKey(try bundle(info: ["SUPublicEDKey": "  "])))
        #expect(AppUpdater.hasPublicKey(try bundle(
            info: ["SUPublicEDKey": "B9KrayMX4Wr+owCMTj31CS2Yoo90flO6SNFcXuXgtb8="]
        )))
    }

    /// Sparkle offers the item with the highest `sparkle:version`; a lower build added above a
    /// higher one, or an archive that is not a release asset, would be a publishing mistake.
    @Test func everyFeedItemIsASignedReleaseAssetNewestFirst() throws {
        let feed = try XMLDocument(
            contentsOf: Self.repositoryRoot.appendingPathComponent("appcast.xml")
        )
        #expect(try feed.nodes(forXPath: "/rss/channel").count == 1)

        var previousBuild = Int.max
        for item in try feed.nodes(forXPath: "/rss/channel/item") {
            let build = try #require(Int(try text(item, "sparkle:version")))
            #expect(build < previousBuild)
            previousBuild = build

            let version = try text(item, "sparkle:shortVersionString")
            let enclosure = try #require(try item.nodes(forXPath: "enclosure").first as? XMLElement)
            #expect(enclosure.attribute(forName: "url")?.stringValue
                == "https://github.com/soondubu137/notchline/releases/download/v\(version)/Notchline-\(version).zip")
            let signature = enclosure.attribute(
                forLocalName: "edSignature",
                uri: "http://www.andymatuschak.org/xml-namespaces/sparkle"
            )
            // Not `!(… ?? "").isEmpty`: the macro reports that form failed with the value present.
            #expect(signature?.stringValue?.isEmpty == false)
        }
    }

    private func text(_ node: XMLNode, _ path: String) throws -> String {
        try #require(try node.nodes(forXPath: path).first?.stringValue)
    }

    private func bundle(info: [String: String]) throws -> Bundle {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppUpdaterTests-\(UUID().uuidString).bundle")
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist = info
        plist["CFBundleIdentifier"] = "com.example.app-updater-tests.\(UUID().uuidString)"
        try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        return try #require(Bundle(url: root))
    }
}

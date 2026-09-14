// What this build calls itself. The numbers come from the bundle (`MARKETING_VERSION`,
// `CURRENT_PROJECT_VERSION`); the stage word lives here because
// `CFBundleShortVersionString` must be numeric-dotted.
import SwiftUI

enum AppVersion {
    /// Where this build stands before `1.0`, or `nil` once it needs no qualifying.
    static let stage: String? = "Alpha"

    /// `0.1.0` — `MARKETING_VERSION`, as stamped into this bundle.
    static var marketing: String? { infoString(for: "CFBundleShortVersionString") }

    /// `1` — `CURRENT_PROJECT_VERSION`.
    static var build: String? { infoString(for: "CFBundleVersion") }

    /// `0.1.0 Alpha`.
    static var name: String? {
        guard let marketing else { return nil }
        return stage.map { "\(marketing) \($0)" } ?? marketing
    }

    /// `Version 0.1.0 Alpha (1)`, drawn in Settings. The build number tells apart alpha builds of
    /// one version in bug reports.
    static var summary: String? {
        guard let name else { return nil }
        guard let build else { return "Version \(name)" }
        return "Version \(name) (\(build))"
    }

    /// The spoken form, where `(1)` would be read as punctuation.
    static var spokenSummary: String? {
        guard let name else { return nil }
        guard let build else { return "Version \(name)" }
        return "Version \(name), build \(build)"
    }

    /// The About panel keeps the author credit in the ordinary copyright line.
    static var copyrightNotice: String? { infoString(for: "NSHumanReadableCopyright") }

    nonisolated static let repositoryURL = URL(string: "https://github.com/soondubu137/notchline")!

    /// A bundle that cannot say its version draws none, never `Unknown`.
    private static func infoString(for key: String) -> String? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            !value.isEmpty
        else { return nil }
        return value
    }
}

/// The build version on the closing line of Settings.
struct AppVersionLine: View {
    var body: some View {
        if let summary = AppVersion.summary {
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(MacOSWindowColor.tertiaryText)
                .monospacedDigit()
                .accessibilityLabel(AppVersion.spokenSummary ?? summary)
        }
    }
}

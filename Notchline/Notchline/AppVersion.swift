// What this build calls itself, and the line the two windows draw it on.
//
// The numbers are read from the bundle rather than written here. They live in
// `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, which is what the build
// stamps into `Info.plist` and what notarisation, the crash reporter and any
// installer read; a copy in Swift would be a second declaration of the same
// fact, and the copy is the one that gets forgotten at the next release.
//
// **The stage word is the part the bundle cannot carry.**
// `CFBundleShortVersionString` is a numeric-dotted string or it is invalid, so
// `0.1.0 Alpha` cannot be the marketing version: it fails validation, and every
// comparison made against it — an update check, a bug report sorted by version
// — becomes a string compare on something that no longer orders. So the
// numbers stay a version, the word stays a word, and they meet only where they
// are drawn.
import SwiftUI

/// The version this build is, composed from what the bundle says plus the one
/// word the bundle has nowhere to put.
enum AppVersion {
    /// Where this build stands in the run-up to `1.0`, or `nil` once a build
    /// needs no qualifying.
    ///
    /// The one hand-written part, for the reason in the file comment. It is
    /// drawn verbatim, so it changes here and nowhere else.
    static let stage: String? = "Alpha"

    /// `0.1.0` — `MARKETING_VERSION`, as stamped into this bundle.
    static var marketing: String? { infoString(for: "CFBundleShortVersionString") }

    /// `1` — `CURRENT_PROJECT_VERSION`.
    static var build: String? { infoString(for: "CFBundleVersion") }

    /// `0.1.0 Alpha` — what this build is called, with nothing in front of it.
    static var name: String? {
        guard let marketing else { return nil }
        return stage.map { "\(marketing) \($0)" } ?? marketing
    }

    /// `Version 0.1.0 Alpha (1)` — the About-box form, and what both windows
    /// draw.
    ///
    /// The build number is kept rather than tidied away because this is an
    /// alpha: two people running `0.1.0` can be running different code, and the
    /// number in brackets is the only thing in the interface that tells those
    /// builds apart in a bug report.
    static var summary: String? {
        guard let name else { return nil }
        guard let build else { return "Version \(name)" }
        return "Version \(name) (\(build))"
    }

    /// The same statement said aloud, where `(1)` would be read as punctuation.
    static var spokenSummary: String? {
        guard let name else { return nil }
        guard let build else { return "Version \(name)" }
        return "Version \(name), build \(build)"
    }

    /// Nothing is guessed: a bundle that cannot say which version it is draws
    /// no version at all, rather than a line reading `Unknown`.
    private static func infoString(for key: String) -> String? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            !value.isEmpty
        else { return nil }
        return value
    }
}

/// The version, on the closing line of whichever window is showing.
///
/// One view rather than a line written into each window, so first run and
/// Settings cannot end up saying it in two different forms — which is the same
/// argument that makes `ProductConnectionRows` one view used twice.
///
/// It sits under the read-only statement both windows close on, at the
/// footnote's own size and in the same tertiary ink: a version is the quietest
/// true thing in a window, and nothing here should read louder than the
/// sentence above it.
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

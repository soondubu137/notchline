import Foundation
import Testing

/// A `UserDefaults` suite of one test's own, kept as a file in the temporary directory. The test
/// calls ``remove()`` from a `defer`; the name is unique because every case runs in two test hosts
/// at once.
///
/// Not a plain suite name, which lives in `~/Library/Preferences`: `cfprefsd` writes that plist
/// back, empty, a few seconds after the test host exits, however the test cleared it — domain
/// removed, file deleted, both in either order, with or without a synchronise first. Plain names
/// had left over 4,500 plists there by 2026-10-04. A suite named by an absolute path is one
/// `cfprefsd` leaves deleted: measured the same day, still gone 27 s after exit.
struct ScratchDefaults {
    let defaults: UserDefaults
    let path: String

    init(_ label: String) {
        path = FileManager.default.temporaryDirectory
            .appending(path: "\(label)-\(UUID().uuidString).plist").path
        defaults = UserDefaults(suiteName: path)!
    }

    func remove() {
        defaults.removePersistentDomain(forName: path)
        try? FileManager.default.removeItem(atPath: path)
    }
}

@Test func aScratchSuiteIsTheFileAtItsPathAndRemovingItLeavesNothing() {
    let scratch = ScratchDefaults("scratch-defaults")
    scratch.defaults.set(true, forKey: "written")
    #expect(CFPreferencesAppSynchronize(scratch.path as CFString))
    #expect(FileManager.default.fileExists(atPath: scratch.path))

    scratch.remove()
    #expect(!FileManager.default.fileExists(atPath: scratch.path))
}

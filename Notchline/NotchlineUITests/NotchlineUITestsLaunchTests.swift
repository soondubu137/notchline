import XCTest

final class NotchlineUITestsLaunchTests: XCTestCase {

    // Keep `runsForEachTargetApplicationUIConfiguration` false: XCTest reaches light/dark by writing
    // the Mac's real appearance and never restores it (measured: left Dark). Use `NSApp.appearance`.

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

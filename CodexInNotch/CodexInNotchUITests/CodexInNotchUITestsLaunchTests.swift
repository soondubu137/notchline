//
//  CodexInNotchUITestsLaunchTests.swift
//  CodexInNotchUITests
//
//  Created by Yinfeng Lu on 8/10/26.
//

import XCTest

final class CodexInNotchUITestsLaunchTests: XCTestCase {

    // Do not override `runsForEachTargetApplicationUIConfiguration` back to `true`.
    // On macOS the two target application UI configurations are the light and dark
    // system appearances, and XCTest reaches them by writing the machine's real
    // appearance setting — not the app's `NSAppearance`. It never restores the value it
    // found, so the run ends on whichever configuration happened to execute last and
    // the user's Mac is left on it. Measured: `testLaunch` ran twice, the setting went
    // Light -> Dark mid-run, and stayed Dark after the suite exited.
    //
    // The default (`false`) runs this test once, in whatever appearance is already set,
    // and touches nothing. To cover both appearances, drive the app's own
    // `NSApp.appearance` from a launch argument instead of the system-wide setting.

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

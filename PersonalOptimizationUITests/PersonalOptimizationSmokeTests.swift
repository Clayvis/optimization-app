import XCTest

@MainActor
final class PersonalOptimizationSmokeTests: XCTestCase {
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        return app
    }

    func testPrimaryNavigationAndAdvancedSetup() {
        continueAfterFailure = false
        let app = launchApp()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Dojo"].tap()
        XCTAssertTrue(app.navigationBars["The Dojo"].waitForExistence(timeout: 3))

        app.buttons["dojo.advancedSetup"].tap()
        XCTAssertTrue(app.navigationBars["Advanced Setup"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Time anchors"].exists)
    }

    func testQuickWaterLogShowsConfirmation() {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["Water"].tap()
        let quickLog = app.buttons["hydration.quick.8"]
        XCTAssertTrue(quickLog.waitForExistence(timeout: 5))
        quickLog.tap()
        XCTAssertTrue(app.staticTexts["Streak alive."].waitForExistence(timeout: 3))
    }
}

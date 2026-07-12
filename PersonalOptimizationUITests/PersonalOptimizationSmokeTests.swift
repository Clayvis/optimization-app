import XCTest

final class PersonalOptimizationSmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    func testPrimaryNavigationAndAdvancedSetup() {
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Dojo"].tap()
        XCTAssertTrue(app.navigationBars["The Dojo"].waitForExistence(timeout: 3))

        app.buttons["dojo.advancedSetup"].tap()
        XCTAssertTrue(app.navigationBars["Advanced Setup"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Time anchors"].exists)
    }

    func testQuickWaterLogShowsConfirmation() {
        app.tabBars.buttons["Water"].tap()
        let quickLog = app.buttons["hydration.quick.8"]
        XCTAssertTrue(quickLog.waitForExistence(timeout: 5))
        quickLog.tap()
        XCTAssertTrue(app.staticTexts["Streak alive."].waitForExistence(timeout: 3))
    }
}

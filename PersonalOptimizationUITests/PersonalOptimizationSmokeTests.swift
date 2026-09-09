import XCTest

@MainActor
final class PersonalOptimizationSmokeTests: XCTestCase {
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        return app
    }

    /// Timeouts are sized for shared CI runners, where app launch alone can
    /// take 10+ seconds and a navigation push can trail the tap by several
    /// seconds. Local runs pass in a fraction of these budgets; a genuine
    /// regression still fails, just a few seconds slower.
    func testPrimaryNavigationAndAdvancedSetup() {
        continueAfterFailure = false
        let app = launchApp()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Dojo"].tap()
        XCTAssertTrue(app.navigationBars["The Dojo"].waitForExistence(timeout: 10))

        let advancedSetup = app.buttons["dojo.advancedSetup"]
        XCTAssertTrue(advancedSetup.waitForExistence(timeout: 10))
        advancedSetup.tap()
        XCTAssertTrue(app.navigationBars["Advanced Setup"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Time anchors"].waitForExistence(timeout: 5))
    }

    func testQuickWaterLogShowsConfirmation() {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["Water"].tap()
        let quickLog = app.buttons["hydration.quick.8"]
        XCTAssertTrue(quickLog.waitForExistence(timeout: 15))
        quickLog.tap()
        XCTAssertTrue(app.staticTexts["Streak alive."].waitForExistence(timeout: 10))
    }

    func testTodayCoachCanStartAndSaveWorkoutWithoutSetup() {
        continueAfterFailure = false
        let app = launchApp()
        let start = app.buttons["today.startWorkout"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        for _ in 0..<4 where !start.isHittable { app.swipeUp() }
        start.tap()
        let finish = app.buttons["customActivity.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "The Today action starts the timer directly")
        for _ in 0..<4 where !finish.isHittable { app.swipeUp() }
        finish.tap()
        XCTAssertTrue(app.staticTexts["Daily win earned · +50 XP"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["today.resumePlan"].exists, "Starting a workout must not also select rest")
    }

    func testTodayRestDayDoesNotStartWorkout() {
        continueAfterFailure = false
        let app = launchApp()
        let rest = app.buttons["today.restDay"]
        XCTAssertTrue(rest.waitForExistence(timeout: 15))
        for _ in 0..<4 where !rest.isHittable { app.swipeUp() }
        rest.tap()
        XCTAssertTrue(app.buttons["today.resumePlan"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["customActivity.finish"].exists)
        XCTAssertFalse(app.staticTexts["Daily win earned · +50 XP"].exists)
    }
}

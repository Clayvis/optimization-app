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

    /// Nutrition Phase 1: a first-time user logs a food from Today with no
    /// targets, no database, and no Health authorization (skipped under
    /// --ui-testing). The day view lists it and the Today card totals it.
    func testNutritionFirstFoodLogsFromTodayWithoutSetup() {
        continueAfterFailure = false
        let app = launchApp()
        // A plain-styled NavigationLink row is exposed as a cell, not a button,
        // and a lazy List only instantiates it once it is near the viewport.
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 15))
        let card = app.descendants(matching: .any).matching(identifier: "today.nutritionCard").firstMatch
        for _ in 0..<4 where !card.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(card.exists, "Today shows the nutrition card")
        for _ in 0..<4 where !card.isHittable { app.swipeUp() }
        card.tap()

        let addBreakfast = app.buttons["nutrition.add.breakfast"]
        XCTAssertTrue(addBreakfast.waitForExistence(timeout: 10))
        addBreakfast.tap()

        let name = app.textFields["nutrition.newFood.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "An empty food list opens straight on New food")
        name.tap()
        name.typeText("Test oats")
        let calories = app.textFields["nutrition.newFood.calories"]
        calories.tap()
        calories.typeText("200")
        let protein = app.textFields["nutrition.newFood.protein"]
        protein.tap()
        protein.typeText("20")

        let log = app.buttons["nutrition.newFood.log"]
        for _ in 0..<4 where !log.isHittable { app.swipeUp() }
        XCTAssertTrue(log.waitForExistence(timeout: 5))
        log.tap()

        XCTAssertTrue(app.staticTexts["Test oats"].waitForExistence(timeout: 10))
        let breakfastTotal = app.staticTexts["nutrition.total.breakfast"]
        XCTAssertTrue(breakfastTotal.waitForExistence(timeout: 5), "The breakfast header totals the slot")
        XCTAssertEqual(breakfastTotal.label, "200 kcal")

        // Setting targets is the opt-in: from then on protein and calories
        // remaining lead Today, visible without scrolling (spec criterion).
        let setTargets = app.buttons["nutrition.targets"]
        XCTAssertTrue(setTargets.waitForExistence(timeout: 5))
        setTargets.tap()
        let saveTargets = app.buttons["nutrition.targets.save"]
        XCTAssertTrue(saveTargets.waitForExistence(timeout: 10))
        saveTargets.tap()
        XCTAssertTrue(app.buttons["nutrition.targets"].waitForExistence(timeout: 10), "Back on the day view after saving")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        // Today keeps the scroll offset from the earlier swipes; the criterion
        // is about the top of the list, so return there first.
        for _ in 0..<3 { app.swipeDown() }
        let proteinLeft = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'g protein left'")).firstMatch
        XCTAssertTrue(proteinLeft.waitForExistence(timeout: 10), "The Today card shows protein remaining once targets exist")
        XCTAssertTrue(proteinLeft.isHittable, "Protein remaining is visible without scrolling")
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

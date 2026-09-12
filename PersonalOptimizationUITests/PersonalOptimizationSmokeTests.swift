import XCTest

@MainActor
final class PersonalOptimizationSmokeTests: XCTestCase {
    private func launchApp(mascot: Bool = false, onboarding: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        if mascot { app.launchArguments.append("--ui-testing-mascot") }
        if onboarding { app.launchArguments.append("--ui-testing-onboarding") }
        app.launch()
        return app
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        let app = launchApp(mascot: true)
        let start = app.buttons["today.startWorkout"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        for _ in 0..<4 where !start.isHittable { app.swipeUp() }
        start.tap()
        let finish = app.buttons["customActivity.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "The Today action starts the timer directly")
        app.tabBars.buttons["Dojo"].tap()
        let companion = app.buttons["mascot.companion"]
        XCTAssertTrue(companion.waitForExistence(timeout: 10))
        XCTAssertEqual(companion.label, "Training", "The mascot stays live after leaving Today")
        app.tabBars.buttons["Today"].tap()
        for _ in 0..<4 where !finish.isHittable { app.swipeUp() }
        finish.tap()
        XCTAssertTrue(app.staticTexts["Daily win earned · +50 XP"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["today.resumePlan"].exists, "Starting a workout must not also select rest")
        app.tabBars.buttons["Dojo"].tap()
        XCTAssertTrue(companion.waitForExistence(timeout: 10))
        XCTAssertEqual(companion.label, "Daily win")
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
        let app = launchApp(mascot: true)
        let rest = app.buttons["today.restDay"]
        XCTAssertTrue(rest.waitForExistence(timeout: 15))
        for _ in 0..<4 where !rest.isHittable { app.swipeUp() }
        rest.tap()
        XCTAssertTrue(app.buttons["today.resumePlan"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["customActivity.finish"].exists)
        XCTAssertFalse(app.staticTexts["Daily win earned · +50 XP"].exists)
        app.tabBars.buttons["Dojo"].tap()
        let companion = app.buttons["mascot.companion"]
        XCTAssertTrue(companion.waitForExistence(timeout: 10))
        XCTAssertEqual(companion.label, "Recovery day")
    }

    func testMascotPreviewsDoNotChangeLiveStateOrEarnWorkoutCredit() {
        continueAfterFailure = false
        let app = launchApp(mascot: true)
        app.tabBars.buttons["Dojo"].tap()
        let companion = app.buttons["mascot.companion"]
        XCTAssertTrue(companion.waitForExistence(timeout: 10))
        let originalState = companion.label
        let gallery = app.buttons["mascot.reactionsGallery"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 10))
        gallery.tap()
        for state in ["training", "recovering", "comeback", "celebrating"] {
            let preview = app.buttons["mascot.preview.\(state)"]
            for _ in 0..<3 where !preview.isHittable { app.swipeUp() }
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            preview.tap()
            capture("Mascot \(state)", app: app)
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(companion.waitForExistence(timeout: 10))
        XCTAssertEqual(companion.label, originalState)
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.buttons["today.startWorkout"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Daily win earned · +50 XP"].exists)
    }

    func testFirstLaunchQuickProfileSetsTodaysWorkoutGoal() {
        continueAfterFailure = false
        let app = launchApp(onboarding: true)
        let next = app.buttons["onboarding.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        capture("Quick profile, empty measurements", app: app)
        next.tap()
        XCTAssertTrue(app.staticTexts["Error: Enter your height using the selected units."].waitForExistence(timeout: 5))
        app.buttons["Dismiss error"].tap()
        let name = app.textFields["onboarding.name"]
        name.tap()
        name.typeText("Alex")
        app.toolbars.buttons["Done"].tap()
        let height = app.textFields["onboarding.height"]
        for _ in 0..<3 where !height.isHittable { app.swipeUp() }
        height.tap()
        height.typeText("5")
        app.toolbars.buttons["Done"].tap()
        let inches = app.textFields["onboarding.inches"]
        for _ in 0..<3 where !inches.isHittable { app.swipeUp() }
        inches.tap()
        inches.typeText(XCUIKeyboardKey.delete.rawValue + "4")
        app.toolbars.buttons["Done"].tap()
        let weight = app.textFields["onboarding.weight"]
        for _ in 0..<3 where !weight.isHittable { app.swipeUp() }
        weight.tap()
        weight.typeText("145")
        app.toolbars.buttons["Done"].tap()
        next.tap()
        let minutes = app.segmentedControls["onboarding.minutes"]
        XCTAssertTrue(minutes.waitForExistence(timeout: 10))
        minutes.buttons["20 min"].tap()
        capture("Quick profile, goals", app: app)
        let female = app.buttons["onboarding.ninja_female"]
        for _ in 0..<3 where !female.isHittable { app.swipeUp() }
        female.tap()
        next.tap()
        let start = app.buttons["today.startWorkout"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        XCTAssertEqual(start.label, "Start 20-min walking")
        XCTAssertFalse(app.buttons["onboarding.continue"].exists)
        app.tabBars.buttons["Dojo"].tap()
        XCTAssertTrue(app.buttons["mascot.companion"].waitForExistence(timeout: 10))
    }
}

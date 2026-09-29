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

        tapClearOfKeyboard(app.buttons["nutrition.newFood.log"], in: app)

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

    func testInBodyManualScanPersistsAndShowsMuscleEstimate() {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["Train"].tap()
        let entry = app.buttons["InBody Progress Coach"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        app.buttons["Add or import InBody scans"].tap()
        app.buttons["Type values"].tap()
        for (label, value) in [("Height (in)", "70"), ("Weight (lb)", "200"),
                               ("Skeletal muscle (lb)", "90"), ("Lean body mass (lb)", "160"),
                               ("Body-fat mass (lb)", "40"), ("Body fat (%)", "20")] {
            type(value, into: app.textFields[label], in: app)
        }
        app.buttons["inbody.save"].tap()
        XCTAssertTrue(app.staticTexts["Estimated skeletal muscle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Edit latest scan"].exists)
    }

    /// A photo of the result sheet prefills the editor for review. The UI-test
    /// hook reads a synthetic sample sheet through the real recognizer, since
    /// tests cannot drive the system photo picker.
    func testInBodyPhotoPrefillsValuesForReview() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-inbody-photo"]
        app.launch()
        app.tabBars.buttons["Train"].tap()
        let entry = app.buttons["InBody Progress Coach"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        app.buttons["Add or import InBody scans"].tap()
        app.buttons["Choose photo"].tap()
        let summary = app.descendants(matching: .any)["inbody.photo.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 30), "The sheet is read and the editor opens for review")
        XCTAssertEqual(app.textFields["Weight (lb)"].value as? String, "200")
        XCTAssertEqual(app.textFields["Skeletal muscle (lb)"].value as? String, "88.2")
        XCTAssertEqual(app.textFields["Body fat (%)"].value as? String, "22.5")
        app.buttons["inbody.save"].tap()
        // A labeled row also exposes its label and value as one combined text.
        XCTAssertTrue(app.staticTexts["Estimated skeletal muscle, 88.2 lb"].waitForExistence(timeout: 10),
                      "The reviewed values were saved")
        XCTAssertTrue(app.staticTexts["200.0 lb"].exists)
        XCTAssertTrue(app.staticTexts["March 14, 2026"].exists, "The sheet's test date, not today")
    }

    /// Train: "New workout" starts empty and named by the user, exercises are
    /// added as you go, and the finished workout becomes the repeat tile.
    func test_newWorkoutBuildsAsYouGoAndBecomesTheRepeatTile() {
        continueAfterFailure = false
        let app = launchApp()
        app.tabBars.buttons["Train"].tap()
        let newWorkout = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "New workout")).firstMatch
        XCTAssertTrue(newWorkout.waitForExistence(timeout: 15))
        for _ in 0..<4 where !newWorkout.isHittable { app.swipeUp() }
        newWorkout.tap()
        type("Pull day", into: app.textFields["lift.new.name"], in: app)
        let start = app.buttons["lift.new.start"]
        XCTAssertTrue(waitUntilHittable(start))
        start.tap()
        let exerciseName = app.textFields["lift.addExercise.name"]
        XCTAssertTrue(exerciseName.waitForExistence(timeout: 10), "The empty workout asks for its first exercise")
        type("Chin-up", into: exerciseName, in: app)
        tapClearOfKeyboard(app.buttons["Add custom exercise"], in: app)
        tapClearOfKeyboard(app.buttons["lift.addSet"].firstMatch, in: app)
        let confirm = app.buttons["lift.confirmSet"]
        for _ in 0..<5 where !(confirm.exists && confirm.isHittable) { app.swipeUp() }
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["lift.editSet"].firstMatch.waitForExistence(timeout: 10), "The set is logged")
        let end = app.buttons["End workout"]
        for _ in 0..<6 where !(end.exists && end.isHittable) { app.swipeUp() }
        end.tap()
        XCTAssertTrue(app.navigationBars["New workout"].waitForExistence(timeout: 10), "Ending returns to the start screen")
        app.navigationBars["New workout"].buttons.element(boundBy: 0).tap()
        let repeatTile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pull day")).firstMatch
        XCTAssertTrue(repeatTile.waitForExistence(timeout: 10), "The finished workout is offered by its own name")
        for _ in 0..<4 where !repeatTile.isHittable { app.swipeUp() }
        repeatTile.tap()
        XCTAssertTrue(app.staticTexts["Chin-up"].waitForExistence(timeout: 10), "Repeat lists the same exercises")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Last time")).firstMatch.exists)
        XCTAssertTrue(app.buttons["lift.startWorkout"].exists)
    }

    func test_recentWholeMealLogsFromHomeInTwoTaps() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-repeat-meals"]
        app.launch()
        let quickAdd = app.buttons["today.quickAddMeal"]
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 15))
        XCTAssertTrue(quickAdd.isHittable, "Quick add is visible without scrolling when nutrition has targets")
        quickAdd.tap() // Tap 1: Home -> Recent.
        let repeatMeal = app.buttons["nutrition.repeatMeal"].firstMatch
        XCTAssertTrue(repeatMeal.waitForExistence(timeout: 10))
        capture("Recent meals", app: app)
        repeatMeal.tap() // Tap 2: log the complete original portion.
        // Durable result, not the 1.8-second confirmation banner (too brief to
        // assert on reliably on shared CI runners): the fixture's 2 × 40 g oats
        // (10 g protein) brings today's 150 g protein target to 140 g left.
        XCTAssertTrue(app.staticTexts["140 g protein left"].waitForExistence(timeout: 10),
                      "The repeated meal counts toward today on the Home card")
        XCTAssertTrue(quickAdd.exists)
    }

    func test_savedMealLogsFromHomeInThreeTaps() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-repeat-meals"]
        app.launch()
        let quickAdd = app.buttons["today.quickAddMeal"]
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 15))
        quickAdd.tap() // Tap 1.
        app.buttons["Saved meals"].tap() // Tap 2.
        let log = app.buttons["nutrition.logSavedMeal"].firstMatch
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        capture("Saved meals", app: app)
        log.tap() // Tap 3.
        XCTAssertTrue(app.staticTexts["140 g protein left"].waitForExistence(timeout: 10),
                      "The saved meal counts toward today on the Home card")
    }

    func test_saveMealAndCopyPreviewCancelThenConfirm() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-repeat-meals"]
        app.launch()
        let card = app.buttons["today.nutritionCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        app.buttons["Previous day"].tap()
        let actions = app.buttons["nutrition.actions.breakfast"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        for _ in 0..<3 where !actions.isHittable { app.swipeUp() }
        actions.tap()
        app.buttons["Save meal"].tap()
        let name = app.textFields["nutrition.savedMeal.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeText("Weekend oats")
        app.buttons["nutrition.mealAction.confirm"].tap()
        // The sheet closes only when the save succeeds (a failure keeps it open
        // with an error). The confirmation banner lasts 1.8 seconds, too brief
        // to assert on reliably on shared CI runners (CI run #37).
        XCTAssertTrue(name.waitForNonExistence(timeout: 10), "Saving closes the sheet")
        app.navigationBars.buttons["Today"].tap()
        app.buttons["nutrition.copyYesterday"].tap()
        XCTAssertTrue(app.staticTexts["Test oats"].waitForExistence(timeout: 10))
        capture("Copy meal preview", app: app)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["Test oats"].exists, "Cancel does not append food")
        app.buttons["nutrition.copyYesterday"].tap()
        app.buttons["nutrition.mealAction.confirm"].tap()
        XCTAssertTrue(app.staticTexts["Test oats"].waitForExistence(timeout: 10), "Confirm appends the copied food")

        // The saved meal is durable and reachable from Home. Back responds only
        // once the copy sheet has finished closing; under load a tap sent
        // during that animation was lost, so wait for it and retry once.
        let back = app.navigationBars.buttons["BackButton"]
        XCTAssertTrue(waitUntilHittable(back), "Back to Today")
        back.tap()
        let quickAdd = app.buttons["today.quickAddMeal"]
        if !quickAdd.waitForExistence(timeout: 5), back.exists, back.isHittable { back.tap() }
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 10))
        quickAdd.tap()
        app.buttons["Saved meals"].tap()
        XCTAssertTrue(app.staticTexts["Weekend oats"].waitForExistence(timeout: 10), "The new saved meal is listed")
    }

    /// Suggested workout from Train: Review shows the plan, Start creates the
    /// linked session, and the first set prefills from the coach's load.
    func test_suggestedLiftReviewStartsWorkoutWithPrefilledSet() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-suggested-lift"]
        app.launch()
        app.tabBars.buttons["Train"].tap()
        let review = app.buttons["Review"]
        XCTAssertTrue(review.waitForExistence(timeout: 15), "The suggestion card offers Review")
        for _ in 0..<3 where !review.isHittable { app.swipeUp() }
        review.tap()
        XCTAssertTrue(app.staticTexts["Goblet squat"].waitForExistence(timeout: 10), "Review shows the suggested plan")
        let start = app.buttons["lift.startWorkout"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        for _ in 0..<4 where !start.isHittable { app.swipeUp() }
        start.tap()
        let addSet = app.buttons["lift.addSet"].firstMatch
        XCTAssertTrue(addSet.waitForExistence(timeout: 10), "Start opens the active workout")
        for _ in 0..<4 where !addSet.isHittable { app.swipeUp() }
        addSet.tap()
        let weight = app.textFields["lift.setWeight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 10))
        XCTAssertEqual(weight.value as? String, "40", "The coach's suggested load prefills the first set")
        // Log set sits at the bottom of the form, created only once scrolled near.
        let confirm = app.buttons["lift.confirmSet"]
        for _ in 0..<5 where !(confirm.exists && confirm.isHittable) { app.swipeUp() }
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["lift.editSet"].firstMatch.waitForExistence(timeout: 10), "The logged set is listed and editable")
    }

    /// Today shows the same card inside a List; its destination is hosted on
    /// the List, so Review must still open the plan from there.
    func test_suggestedLiftOpensFromToday() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-suggested-lift"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 15))
        let review = app.buttons["Review"]
        let plan = app.buttons["today.trainingPlan"]
        for _ in 0..<5 where !plan.exists && !review.exists { app.swipeUp() }
        // The disclosure remembers its state between launches; open it only if closed.
        if !review.exists, plan.exists { plan.tap() }
        XCTAssertTrue(review.waitForExistence(timeout: 10), "Today's plan shows the suggestion")
        for _ in 0..<4 where !review.isHittable { app.swipeUp() }
        review.tap()
        XCTAssertTrue(app.staticTexts["Goblet squat"].waitForExistence(timeout: 10), "Review opens the plan from Today")
        XCTAssertTrue(app.buttons["lift.startWorkout"].waitForExistence(timeout: 10))
    }

    /// Barcode hit: Quick add, the scan button, the barcode, then one tap logs
    /// it. UI tests use the typed-barcode path (no camera in the simulator)
    /// and never touch the network; the fixture food is a cached database hit.
    func test_scannedBarcodeLogsTheFoundFood() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-repeat-meals", "--ui-testing-barcode-food"]
        app.launch()
        openBarcodeScan(in: app)
        lookUpBarcode("4901234567894", in: app)
        XCTAssertTrue(app.staticTexts["nutrition.barcode.foundName"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["nutrition.barcode.foundName"].label, "Test granola")
        XCTAssertTrue(app.staticTexts[OpenFoodFactsAttribution.text].exists, "Open Food Facts is credited")
        app.buttons["nutrition.barcode.log"].tap()
        // 150 g protein target, 6 g in one serving.
        XCTAssertTrue(app.staticTexts["144 g protein left"].waitForExistence(timeout: 10), "The scanned food counts toward today")
        // The logged entry keeps crediting the database it came from.
        let card = app.buttons["today.nutritionCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Test granola")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "The scanned food is logged on today's page")
        for _ in 0..<3 where !row.isHittable { app.swipeUp() }
        row.tap()
        let credit = app.staticTexts["nutrition.edit.attribution"]
        XCTAssertTrue(credit.waitForExistence(timeout: 10), "The entry detail credits Open Food Facts")
        XCTAssertEqual(credit.label, OpenFoodFactsAttribution.text)
    }

    /// Barcode miss: New food opens with the barcode attached, and the next
    /// scan of the same code finds the food the user created.
    func test_unknownBarcodeBecomesAFoodTheNextScanFinds() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-repeat-meals"]
        app.launch()
        openBarcodeScan(in: app)
        lookUpBarcode("0012345678905", in: app)
        let barcode = app.staticTexts["nutrition.newFood.barcode"]
        XCTAssertTrue(barcode.waitForExistence(timeout: 10), "New food carries the scanned barcode")
        XCTAssertTrue(barcode.label.contains("0012345678905"))
        type("Corner bakery roll", into: app.textFields["nutrition.newFood.name"], in: app)
        type("180", into: app.textFields["nutrition.newFood.calories"], in: app)
        type("5", into: app.textFields["nutrition.newFood.protein"], in: app)
        tapClearOfKeyboard(app.buttons["nutrition.newFood.log"], in: app)
        // Waits for the sheet to finish dismissing before Quick add is tapped again.
        openBarcodeScan(in: app)
        lookUpBarcode("0012345678905", in: app)
        XCTAssertTrue(app.staticTexts["nutrition.barcode.foundName"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["nutrition.barcode.foundName"].label, "Corner bakery roll")
    }

    private func lookUpBarcode(_ digits: String, in app: XCUIApplication) {
        let field = app.textFields["nutrition.barcode.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The typed-barcode path is available")
        type(digits, into: field, in: app)
        let lookUp = app.buttons["nutrition.barcode.lookup"]
        XCTAssertTrue(waitUntilHittable(lookUp), "Look up is tappable")
        lookUp.tap()
    }

    /// Quick add from Today, then the sheet's Scan barcode button. Each tap
    /// waits until its target can take it: on the slower CI runner a tap sent
    /// right after Quick add found no Scan button yet (CI run for 9893f16).
    private func openBarcodeScan(in app: XCUIApplication) {
        let quickAdd = app.buttons["today.quickAddMeal"]
        XCTAssertTrue(waitUntilHittable(quickAdd, timeout: 15), "Today shows Quick add")
        quickAdd.tap()
        let scan = app.buttons["nutrition.scan"]
        XCTAssertTrue(waitUntilHittable(scan), "The add sheet shows Scan barcode")
        scan.tap()
    }

    /// Existence first, so hittability is never queried on a missing element.
    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        return XCTWaiter.wait(for: [hittable], timeout: timeout) == .completed
    }

    /// Brings a form field into view and types into it once it holds focus.
    /// A quick flick leaves the form decelerating, and a tap during that
    /// glide only stops the scroll: on shared CI runners the field then never
    /// gets keyboard focus. Drags therefore start on the row labels (a drag
    /// that starts inside the right-aligned text fields is text interaction,
    /// not a scroll), end with a hold so no momentum remains, stay above the
    /// decimal keyboard, and move about one row at a time so a lazily
    /// rendered field cannot be skipped. Focus is confirmed, retrying the
    /// tap, before typing.
    private func type(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Field exists")
        for _ in 0..<10 where !field.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.45))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.33)),
                       withVelocity: .slow,
                       thenHoldForDuration: 0.4)
        }
        XCTAssertTrue(field.isHittable, "Field scrolled into view")
        for _ in 0..<3 {
            field.tap()
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { break }
        }
        XCTAssertEqual(field.value(forKey: "hasKeyboardFocus") as? Bool, true, "Field holds keyboard focus")
        field.typeText(text)
    }

    /// Taps a control that may sit under the software keyboard. `isHittable`
    /// does not account for the keyboard, so a control low in a form can
    /// report hittable while the tap lands on the keyboard instead. A lazy
    /// form also creates rows only near the viewport, so the control may not
    /// exist yet. Scroll (slow drags on the label side, never starting on a
    /// field) until it exists with its center above the keyboard, then tap.
    private func tapClearOfKeyboard(_ element: XCUIElement, in app: XCUIApplication) {
        func covered() -> Bool {
            let keyboard = app.keyboards.firstMatch
            return keyboard.exists && element.frame.midY > keyboard.frame.minY - 8
        }
        // Short-circuit order matters: frame and isHittable need an existing element.
        for _ in 0..<10 where !element.waitForExistence(timeout: 1) || !element.isHittable || covered() {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.45))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.25)),
                       withVelocity: .slow,
                       thenHoldForDuration: 0.4)
        }
        XCTAssertTrue(element.exists, "Control exists")
        XCTAssertTrue(element.isHittable && !covered(), "Control is clear of the keyboard")
        element.tap()
    }
}

/// Mirrors OpenFoodFactsProvider.attribution (UI tests cannot import the app module).
private enum OpenFoodFactsAttribution {
    static let text = "Nutrition facts from Open Food Facts, available under the Open Database License (ODbL)."
}

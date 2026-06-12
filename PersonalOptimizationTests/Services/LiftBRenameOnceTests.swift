import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class LiftBRenameOnceTests: XCTestCase {
    private let gateKey = "LiftBRename.v1.completed"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: gateKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: gateKey)
        super.tearDown()
    }

    func test_newActivityLabel_mapsKnownSeededNames() {
        XCTAssertEqual(LiftBRenameOnce.newActivityLabel(for: "Lift B (different exercises than Mon)"),
                       "My Workout (custom lift)")
        XCTAssertEqual(LiftBRenameOnce.newActivityLabel(for: "Lift B"), "My Workout")
        XCTAssertEqual(LiftBRenameOnce.newActivityLabel(for: "Heavy lift B"), "My Workout (heavy)")
        XCTAssertNil(LiftBRenameOnce.newActivityLabel(for: "My Workout"))
        XCTAssertNil(LiftBRenameOnce.newActivityLabel(for: "Evening lift"))
    }

    func test_runIfNeeded_renamesSeededRows_skipsCustomRows() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext

        let seeded = ScheduleBlock(dayOfWeek: 4, startTime: "18:00", endTime: "19:00",
                                   activity: "Lift B (different exercises than Mon)",
                                   type: .training, module: "lift_b")
        let userOwned = ScheduleBlock(dayOfWeek: 5, startTime: "18:00", endTime: "19:00",
                                      activity: "Lift B",
                                      type: .training, module: "lift_b")
        userOwned.isCustom = true
        let otherModule = ScheduleBlock(dayOfWeek: 1, startTime: "18:00", endTime: "19:00",
                                        activity: "Lift B",
                                        type: .training, module: "lift_a")
        context.insert(seeded)
        context.insert(userOwned)
        context.insert(otherModule)
        try context.save()

        LiftBRenameOnce.runIfNeeded(modelContext: context)

        XCTAssertEqual(seeded.activity, "My Workout (custom lift)")
        XCTAssertEqual(userOwned.activity, "Lift B")
        XCTAssertEqual(otherModule.activity, "Lift B")
    }

    func test_runIfNeeded_gatesAfterFirstRun() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        LiftBRenameOnce.runIfNeeded(modelContext: context)

        let late = ScheduleBlock(dayOfWeek: 4, startTime: "18:00", endTime: "19:00",
                                 activity: "Lift B",
                                 type: .training, module: "lift_b")
        context.insert(late)
        try context.save()

        LiftBRenameOnce.runIfNeeded(modelContext: context)
        XCTAssertEqual(late.activity, "Lift B")
    }
}

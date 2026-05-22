import XCTest
@testable import PersonalOptimization

@MainActor
final class SchedulePlannerTests: XCTestCase {

    private func anchors(training: String = "07:00",
                         learning: String = "19:00",
                         wake: String = "06:00",
                         bedtime: String = "22:00",
                         kidDrop: String = "09:00",
                         kidPickup: String = "17:00") -> SchedulePlanner.AnchorSet {
        SchedulePlanner.AnchorSet(
            wakeHHMM: wake,
            bedtimeHHMM: bedtime,
            kidDropHHMM: kidDrop,
            kidPickupHHMM: kidPickup,
            trainingStartHHMM: training,
            learningStartHHMM: learning
        )
    }

    private func block(day: Int = 1,
                       anchor: ParametricBlock.Anchor = .training,
                       duration: Int = 60,
                       offset: Int? = nil,
                       activity: String = "Lift A",
                       module: String? = "lift_a",
                       startHHMM: String? = nil,
                       endHHMM: String? = nil) -> ParametricBlock {
        ParametricBlock(
            dayOfWeek: day,
            anchor: anchor,
            durationMinutes: duration,
            offsetMinutes: offset,
            activity: activity,
            type: "training",
            module: module,
            explicitStartHHMM: startHHMM,
            explicitEndHHMM: endHHMM
        )
    }

    func test_trainingAnchor_morning() throws {
        let b = block(anchor: .training, duration: 60)
        let (s, e) = try SchedulePlanner.resolve(block: b, anchors: anchors(training: "06:30"), stackedOffsetMinutes: 0)
        XCTAssertEqual(s, "06:30")
        XCTAssertEqual(e, "07:30")
    }

    func test_trainingAnchor_evening() throws {
        let b = block(anchor: .training, duration: 60)
        let (s, e) = try SchedulePlanner.resolve(block: b, anchors: anchors(training: "20:00"), stackedOffsetMinutes: 0)
        XCTAssertEqual(s, "20:00")
        XCTAssertEqual(e, "21:00")
    }

    func test_learningAnchor_eveningWindow() throws {
        let b = block(anchor: .learning, duration: 30, activity: "Japanese", module: "japanese")
        let (s, e) = try SchedulePlanner.resolve(block: b, anchors: anchors(learning: "19:30"), stackedOffsetMinutes: 0)
        XCTAssertEqual(s, "19:30")
        XCTAssertEqual(e, "20:00")
    }

    func test_morningAnchor_atWake() throws {
        let b = block(anchor: .morning, duration: 15, activity: "Hydrate", module: nil)
        let (s, e) = try SchedulePlanner.resolve(block: b, anchors: anchors(wake: "05:45"), stackedOffsetMinutes: 0)
        XCTAssertEqual(s, "05:45")
        XCTAssertEqual(e, "06:00")
    }

    func test_preKidDropAnchor_subtractsDuration() throws {
        // Drop at 09:00, duration 30 → start at 08:30, end at 09:00.
        let b = block(anchor: .preKidDrop, duration: 30, activity: "Breakfast", module: nil)
        let (s, e) = try SchedulePlanner.resolve(block: b, anchors: anchors(kidDrop: "09:00"), stackedOffsetMinutes: 0)
        XCTAssertEqual(s, "08:30")
        XCTAssertEqual(e, "09:00")
    }

    func test_postKidPickupAnchor_startsAtPickup() throws {
        let b = block(anchor: .postKidPickup, duration: 30, activity: "Family", module: nil)
        let (s, e) = try SchedulePlanner.resolve(block: b, anchors: anchors(kidPickup: "17:00"), stackedOffsetMinutes: 0)
        XCTAssertEqual(s, "17:00")
        XCTAssertEqual(e, "17:30")
    }

    func test_eveningAnchor_midpointBetweenPickupAndBedtime() throws {
        // Pickup 17:00, bedtime 22:00 → midpoint 19:30.
        let b = block(anchor: .evening, duration: 30, activity: "Admin", module: nil)
        let (s, e) = try SchedulePlanner.resolve(block: b, anchors: anchors(bedtime: "22:00", kidPickup: "17:00"), stackedOffsetMinutes: 0)
        XCTAssertEqual(s, "19:30")
        XCTAssertEqual(e, "20:00")
    }

    func test_explicitAnchor_passesThrough() throws {
        let b = block(anchor: .explicit, duration: 60, activity: "Break fast", module: nil, startHHMM: "12:00", endHHMM: "12:30")
        let (s, e) = try SchedulePlanner.resolve(block: b, anchors: anchors(), stackedOffsetMinutes: 0)
        XCTAssertEqual(s, "12:00")
        XCTAssertEqual(e, "12:30")
    }

    func test_explicitAnchor_missingTimes_throws() {
        let b = block(anchor: .explicit, duration: 60, activity: "Bad", module: nil, startHHMM: nil, endHHMM: nil)
        XCTAssertThrowsError(try SchedulePlanner.resolve(block: b, anchors: anchors(), stackedOffsetMinutes: 0))
    }

    func test_offsetMinutes_addsToBase() throws {
        let b = block(anchor: .training, duration: 30, offset: 15, activity: "Warmup", module: nil)
        let (s, e) = try SchedulePlanner.resolve(block: b, anchors: anchors(training: "07:00"), stackedOffsetMinutes: 0)
        XCTAssertEqual(s, "07:15")
        XCTAssertEqual(e, "07:45")
    }

    func test_stackedTrainingBlocksSameDay_increment30Min() throws {
        let blocks = [
            block(day: 2, anchor: .training, duration: 30, activity: "Warmup", module: nil),
            block(day: 2, anchor: .training, duration: 30, activity: "Lift", module: nil)
        ]
        let resolved = try SchedulePlanner.resolveAll(templateBlocks: blocks, anchors: anchors(training: "07:00"))
        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(resolved[0].startHHMM, "07:00")
        XCTAssertEqual(resolved[1].startHHMM, "07:30")
    }

    func test_resolveAll_sortsByDayThenStart() throws {
        let blocks = [
            block(day: 3, anchor: .training, duration: 60, activity: "Tue Lift", module: "lift_a"),
            block(day: 1, anchor: .training, duration: 60, activity: "Sun Lift", module: "lift_b"),
            block(day: 1, anchor: .evening, duration: 30, activity: "Sun Admin", module: nil)
        ]
        let resolved = try SchedulePlanner.resolveAll(templateBlocks: blocks, anchors: anchors())
        XCTAssertEqual(resolved.map { $0.dayOfWeek }, [1, 1, 3])
    }

    /// Regression test for the M5 launch problem: with a morning training
    /// anchor the balanced template must NOT land lifts at 18:00.
    func test_balancedTemplate_atMorningAnchor_doesNotProduce1800Lift() throws {
        let json = """
        {"version":2,"blocks":[
            {"dayOfWeek":1,"anchor":"training","durationMinutes":60,"activity":"Lift A","type":"training","module":"lift_a"},
            {"dayOfWeek":3,"anchor":"training","durationMinutes":60,"activity":"Lift B","type":"training","module":"lift_b"}
        ]}
        """.data(using: .utf8)!
        let file = try JSONDecoder().decode(ParametricScheduleFile.self, from: json)
        let resolved = try SchedulePlanner.resolveAll(
            templateBlocks: file.blocks,
            anchors: anchors(training: "06:30")
        )
        XCTAssertFalse(resolved.contains { $0.startHHMM == "18:00" })
        XCTAssertTrue(resolved.allSatisfy { $0.startHHMM == "06:30" })
    }

    func test_eveningAnchor_doesNotCollideWithExplicitMidday() throws {
        // Explicit and evening shouldn't stack against each other since they
        // use different anchor keys for the same day.
        let blocks = [
            block(day: 1, anchor: .explicit, duration: 30, activity: "Lunch fast", module: nil, startHHMM: "12:00", endHHMM: "12:30"),
            block(day: 1, anchor: .evening, duration: 30, activity: "Admin", module: nil)
        ]
        let resolved = try SchedulePlanner.resolveAll(templateBlocks: blocks, anchors: anchors())
        XCTAssertEqual(resolved.count, 2)
        XCTAssertEqual(resolved.first { $0.activity == "Lunch fast" }?.startHHMM, "12:00")
    }

    func test_endTimeNeverExceedsMidnight_clampsToEndOfDay() throws {
        // Synthetic edge: bedtime + duration that would push past 23:59.
        let b = block(anchor: .evening, duration: 240, activity: "Long", module: nil)
        let (_, e) = try SchedulePlanner.resolve(
            block: b,
            anchors: anchors(bedtime: "23:00", kidPickup: "22:00"),
            stackedOffsetMinutes: 0
        )
        // Midpoint of 22:00 and 23:00 is 22:30; 22:30 + 240m would be 02:30 next day.
        // Planner clamps to 23:59.
        XCTAssertEqual(e, "23:59")
    }
}

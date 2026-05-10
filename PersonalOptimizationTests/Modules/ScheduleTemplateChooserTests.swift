import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class ScheduleTemplateChooserTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    func test_apply_blank_wipesNonCustomBlocks() throws {
        let seeded = ScheduleBlock(dayOfWeek: 1, startTime: "09:00", endTime: "10:00", activity: "Stand-up", type: .other)
        let custom = ScheduleBlock(dayOfWeek: 1, startTime: "10:00", endTime: "11:00", activity: "Coffee", type: .other)
        custom.isCustom = true
        context.insert(seeded)
        context.insert(custom)
        try context.save()

        try ScheduleTemplateApplier.apply(.blank, modelContext: context)

        let remaining = try context.fetch(FetchDescriptor<ScheduleBlock>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.activity, "Coffee")
        XCTAssertTrue(remaining.first?.isCustom ?? false)
    }

    func test_apply_balanced_reseeds_and_preserves_custom() throws {
        let custom = ScheduleBlock(dayOfWeek: 1, startTime: "21:00", endTime: "22:00", activity: "Dad time", type: .other)
        custom.isCustom = true
        context.insert(custom)
        try context.save()

        try ScheduleTemplateApplier.apply(.balanced,
                                          modelContext: context,
                                          bundle: ScheduleSeedTests.resourceBundle())

        let remaining = try context.fetch(FetchDescriptor<ScheduleBlock>())
        // The custom row survives; seeded rows are added in addition.
        XCTAssertTrue(remaining.contains { $0.activity == "Dad time" && $0.isCustom })
        XCTAssertGreaterThan(remaining.count, 1)
    }

    func test_template_displayName_humanReadable() {
        XCTAssertEqual(ScheduleTemplate.balanced.displayName, "Balanced")
        XCTAssertEqual(ScheduleTemplate.gymFocused.displayName, "Gym focused")
        XCTAssertEqual(ScheduleTemplate.blank.displayName, "Blank slate")
    }
}

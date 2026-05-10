import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class ScheduleSeedTests: XCTestCase {

    func test_loadDefaultScheduleFile_decodesAll39Blocks() throws {
        let bundle = Bundle(for: type(of: self))
        let testBundle = bundle.url(forResource: "default_schedule", withExtension: "json") != nil
            ? bundle
            : Bundle.main
        let file = try ScheduleSeed.loadDefaultScheduleFile(bundle: testBundle)
        XCTAssertEqual(file.version, 1)
        XCTAssertEqual(file.timezone, "Asia/Tokyo")
        XCTAssertEqual(file.blocks.count, 39)
    }

    func test_seedIfNeeded_onEmptyContainer_inserts39Blocks() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext

        try ScheduleSeed.seedIfNeeded(modelContext: context, bundle: Self.resourceBundle())

        let count = try context.fetchCount(FetchDescriptor<ScheduleBlock>())
        XCTAssertEqual(count, 39)
    }

    func test_seedIfNeeded_onPopulatedContainer_isIdempotent() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext

        try ScheduleSeed.seedIfNeeded(modelContext: context, bundle: Self.resourceBundle())
        try ScheduleSeed.seedIfNeeded(modelContext: context, bundle: Self.resourceBundle())
        try ScheduleSeed.seedIfNeeded(modelContext: context, bundle: Self.resourceBundle())

        let count = try context.fetchCount(FetchDescriptor<ScheduleBlock>())
        XCTAssertEqual(count, 39)
    }

    func test_seedIfNeeded_perDayCounts() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        try ScheduleSeed.seedIfNeeded(modelContext: context, bundle: Self.resourceBundle())

        let expected: [Int: Int] = [1: 8, 2: 6, 3: 8, 4: 6, 5: 7, 6: 2, 7: 2]
        for (day, count) in expected {
            let descriptor = FetchDescriptor<ScheduleBlock>(
                predicate: #Predicate<ScheduleBlock> { $0.dayOfWeek == day }
            )
            XCTAssertEqual(try context.fetchCount(descriptor), count, "Day \(day) expected \(count)")
        }
    }

    // MARK: - Per-template seeds

    func test_loadScheduleFile_balanced_decodes() throws {
        let file = try ScheduleSeed.loadScheduleFile(resourceName: "schedule_balanced", bundle: Self.resourceBundle())
        XCTAssertEqual(file.version, 1)
        XCTAssertFalse(file.blocks.isEmpty, "balanced template must seed at least one block")
    }

    func test_loadScheduleFile_gymFocused_decodes() throws {
        let file = try ScheduleSeed.loadScheduleFile(resourceName: "schedule_gym_focused", bundle: Self.resourceBundle())
        XCTAssertFalse(file.blocks.isEmpty)
        let liftDays = Set(file.blocks.filter { $0.type == "training" && ($0.module == "lift_a" || $0.module == "lift_b") }.map(\.dayOfWeek))
        XCTAssertGreaterThanOrEqual(liftDays.count, 3, "gym-focused must schedule lift on 3+ days")
    }

    func test_loadScheduleFile_languageFocused_decodes() throws {
        let file = try ScheduleSeed.loadScheduleFile(resourceName: "schedule_language_focused", bundle: Self.resourceBundle())
        XCTAssertFalse(file.blocks.isEmpty)
        let learningDays = Set(file.blocks.filter { $0.type == "learning" }.map(\.dayOfWeek))
        XCTAssertGreaterThanOrEqual(learningDays.count, 5, "language-focused must schedule learning on 5+ days")
    }

    func test_loadScheduleFile_fastingFocused_decodes() throws {
        let file = try ScheduleSeed.loadScheduleFile(resourceName: "schedule_fasting_focused", bundle: Self.resourceBundle())
        XCTAssertFalse(file.blocks.isEmpty)
    }

    func test_perTemplateSeeds_areNotClaySchedule() throws {
        // No template JSON should mention Clay-specific tokens like DeepWater,
        // McTureous, Pimsleur, or PMGT. Those belong only in default_schedule.json.
        let tokens = ["DeepWater", "McTureous", "Pimsleur", "PMGT"]
        let names = ["schedule_balanced", "schedule_gym_focused", "schedule_language_focused", "schedule_fasting_focused"]
        for name in names {
            let file = try ScheduleSeed.loadScheduleFile(resourceName: name, bundle: Self.resourceBundle())
            for block in file.blocks {
                for token in tokens {
                    XCTAssertFalse(block.activity.contains(token), "\(name) leaks token \(token) in block: \(block.activity)")
                }
            }
        }
    }

    func test_resetToTemplate_wipesPriorSeedAndApplies() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext

        // Seed Clay's default first to simulate auto-seed having run.
        try ScheduleSeed.seedIfNeeded(modelContext: context, bundle: Self.resourceBundle())
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleBlock>()), 39)

        // Apply the gym-focused template. Clay's blocks should be wiped.
        try ScheduleSeed.resetToTemplate(resourceName: "schedule_gym_focused",
                                         modelContext: context,
                                         bundle: Self.resourceBundle())

        // No remaining Clay blocks; only gym-focused blocks (5).
        let total = try context.fetchCount(FetchDescriptor<ScheduleBlock>())
        let gymFile = try ScheduleSeed.loadScheduleFile(resourceName: "schedule_gym_focused", bundle: Self.resourceBundle())
        XCTAssertEqual(total, gymFile.blocks.count)

        // Verify no leaked Clay-specific activity strings.
        let blocks = try context.fetch(FetchDescriptor<ScheduleBlock>())
        for block in blocks {
            XCTAssertFalse(block.activity.contains("DeepWater"), "Clay's basketball block survived reset")
            XCTAssertFalse(block.activity.contains("PMGT"), "Clay's coursework block survived reset")
        }
    }

    func test_resetToTemplate_preservesCustomBlocks() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext

        // User-created block: should survive a template reset.
        let custom = ScheduleBlock(
            dayOfWeek: 6,
            startTime: "11:00",
            endTime: "12:00",
            activity: "My custom block",
            type: .other,
            module: nil
        )
        custom.isCustom = true
        context.insert(custom)
        try context.save()

        try ScheduleSeed.resetToTemplate(resourceName: "schedule_balanced",
                                         modelContext: context,
                                         bundle: Self.resourceBundle())

        let customs = try context.fetch(
            FetchDescriptor<ScheduleBlock>(predicate: #Predicate { $0.isCustom == true })
        )
        XCTAssertEqual(customs.count, 1)
        XCTAssertEqual(customs.first?.activity, "My custom block")
    }

    // MARK: - Applier routing

    func test_applier_balanced_seedsBalancedTemplate() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext

        try ScheduleTemplateApplier.apply(.balanced, modelContext: context, bundle: Self.resourceBundle())

        let expectedCount = try ScheduleSeed.loadScheduleFile(resourceName: "schedule_balanced", bundle: Self.resourceBundle()).blocks.count
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduleBlock>()), expectedCount)
    }

    func test_applier_blank_emptiesScheduleAndPreservesCustom() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext

        try ScheduleSeed.seedIfNeeded(modelContext: context, bundle: Self.resourceBundle())
        let custom = ScheduleBlock(
            dayOfWeek: 7, startTime: "11:00", endTime: "12:00",
            activity: "My custom block", type: .other, module: nil
        )
        custom.isCustom = true
        context.insert(custom)
        try context.save()

        try ScheduleTemplateApplier.apply(.blank, modelContext: context, bundle: Self.resourceBundle())

        let all = try context.fetch(FetchDescriptor<ScheduleBlock>())
        XCTAssertEqual(all.count, 1, "Only the custom block should survive a blank apply")
        XCTAssertTrue(all.first?.isCustom ?? false)
    }

    /// The schedule JSON ships in the iOS app bundle. When tests run hosted in that app,
    /// Bundle.main is the app bundle and resources are reachable. When tests run standalone
    /// (rare), fall back to the test bundle.
    static func resourceBundle() -> Bundle {
        if Bundle.main.url(forResource: "default_schedule", withExtension: "json") != nil {
            return Bundle.main
        }
        return Bundle(for: ScheduleSeedTests.self)
    }
}

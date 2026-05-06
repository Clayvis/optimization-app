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

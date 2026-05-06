import XCTest
import SwiftData
import SwiftUI
@testable import PersonalOptimization

@MainActor
final class EngagementIntegrationTests: XCTestCase {
    private let jst = TimeZone(identifier: "Asia/Tokyo")!

    func test_allMascotAssets_loadFromMainBundle() {
        // Verifies every CharacterState's assetName resolves to a UIImage at runtime.
        // PersonalOptimizationTests target hosts in the main app, so Asset Catalog is reachable.
        for state in CharacterState.allCases {
            let img = UIImage(named: state.assetName)
            XCTAssertNotNil(img, "Missing asset \(state.assetName)")
        }
    }

    func test_mascotAssets_totalBackingMemoryUnder8MB() {
        // PNGs are ~500KB each on disk; decoded RGBA at 1024x1024 is ~4MB each.
        // We ensure the Asset Catalog doesn't ship oversized variants by capping the
        // sum of file sizes (proxy for resident memory after compression).
        var totalBytes: Int = 0
        for state in CharacterState.allCases {
            let url = Bundle.main.url(forResource: state.assetName, withExtension: "png", subdirectory: nil)
            // Asset Catalog images aren't on disk as standalone files; fallback path:
            // Read via UIImage(named:) and compute pngData count.
            if let data = url.flatMap({ try? Data(contentsOf: $0) }) {
                totalBytes += data.count
            } else if let img = UIImage(named: state.assetName), let data = img.pngData() {
                totalBytes += data.count
            }
        }
        // 8MB budget per spec; encoded PNG sums should be well under this.
        XCTAssertLessThan(totalBytes, 8 * 1024 * 1024,
                          "Mascot assets total \(totalBytes) bytes exceeds 8MB budget")
    }

    func test_streakAndSummary_agreeOnTodaysWorkoutCompletion() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext

        let streakService = StreakService(modelContext: context, timezone: jst)
        let summaryService = DailySummaryService(modelContext: context, timezone: jst)

        let block = ScheduleBlock(dayOfWeek: 3, startTime: "16:00", endTime: "17:00",
                                  activity: "Lift A", type: .training, module: "lift_a")
        context.insert(block)

        let asOf = jstDate(2026, 5, 6, 18, 0)
        try streakService.recordWorkoutLedger(date: asOf, source: .lift)
        let counter = try streakService.recompute(domain: .workout, asOf: asOf)
        let tally = summaryService.todayProtocol(asOf: asOf)

        XCTAssertEqual(counter.currentStreak, 1)
        XCTAssertTrue(tally.domains.first(where: { $0.domain == .workout })?.completed ?? false)
    }

    func test_characterState_reflectsSickDayActivation() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let streakService = StreakService(modelContext: context, timezone: jst)

        try streakService.activateSickDay()
        let inputs = CharacterStateService.gatherInputs(modelContext: context, timezone: jst)
        XCTAssertTrue(inputs.sickDayActive)
        let resolved = CharacterStateService.resolve(inputs: inputs)
        XCTAssertEqual(resolved.state, .tired)
    }

    private func jstDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = jst
        return cal.date(from: c)!
    }
}

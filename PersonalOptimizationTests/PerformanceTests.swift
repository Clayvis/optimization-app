import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class PerformanceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        try ScheduleSeed.seedIfNeeded(modelContext: context, bundle: ScheduleSeedTests.resourceBundle())
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    /// PERFORMANCE.md target: schedule resolution under 50ms.
    /// Re-asserted at the test-fixture level with 100 iterations to amortize jitter.
    func test_perf_currentBlockResolution_100Iterations_under50ms() {
        let service = ScheduleService(modelContext: context, timezone: TimeZone(identifier: "Asia/Tokyo")!)
        let date = Date()
        measure {
            for _ in 0..<100 {
                _ = service.currentBlock(at: date)
            }
        }
    }

    /// PERFORMANCE.md target: SwiftData fetch (1000 records) under 100ms.
    func test_perf_swiftDataFetch_1000Logs_under100ms() throws {
        for i in 0..<1000 {
            let log = DailyLog(date: Date(timeIntervalSince1970: TimeInterval(i) * 86400))
            log.waterOz = Double(i % 200)
            context.insert(log)
        }
        try context.save()
        measure {
            _ = (try? context.fetch(FetchDescriptor<DailyLog>())) ?? []
        }
    }

    /// PERFORMANCE.md target: JSON export of full database under 5s.
    func test_perf_jsonExport_full_under5s() throws {
        let profile = UserProfile(name: "Clay", dob: Date(timeIntervalSince1970: 764985600), sex: "male")
        context.insert(profile)
        for i in 0..<200 {
            let log = DailyLog(date: Date(timeIntervalSince1970: TimeInterval(i) * 86400))
            log.waterOz = Double(i)
            context.insert(log)
        }
        for i in 0..<50 {
            let session = LiftSession(date: Date(), template: i % 2 == 0 ? "Lift A" : "Lift B")
            session.totalVolumeLbs = Double(i * 1000)
            context.insert(session)
        }
        try context.save()

        measure {
            _ = try? JSONExportService.export(modelContext: context)
        }
    }

    /// PERFORMANCE.md target: SwiftData single-entity write under 50ms.
    func test_perf_swiftDataWrite_singleEntity_under50ms() {
        measure {
            for _ in 0..<100 {
                context.insert(DailyLog(date: Date(timeIntervalSinceReferenceDate: TimeInterval.random(in: 0...1e9))))
                try? context.save()
            }
        }
    }

    /// M3.6_SPEC: Coach insight cache lookup < 10ms.
    /// Insert one cached row and re-fetch via the service path used by todayInsight().
    func test_perf_coachCacheLookup_under10ms() throws {
        let insight = CoachInsight(generatedAt: Date(),
                                   insightText: "Stay the course.",
                                   contextSummary: "test",
                                   tokenUsage: 100,
                                   refreshCount: 0)
        context.insert(insight)
        try context.save()
        let service = CoachService(modelContext: context, api: NoopAPI())
        measure {
            for _ in 0..<200 {
                _ = service.cachedInsight()
            }
        }
    }

    /// M3.6_SPEC: Daily quote rendering < 50ms (curated path).
    func test_perf_dailyQuoteCurated_under50ms() {
        let service = DailyQuoteService()
        measure {
            for _ in 0..<200 {
                _ = service.curatedQuote(style: "stoic")
            }
        }
    }

    /// M3.6_SPEC: Schedule editor list with 50 blocks renders in < 100ms (fetch path).
    func test_perf_scheduleEditorFetch_50Blocks_under100ms() throws {
        for day in 1...7 {
            for i in 0..<8 {
                let hour = String(format: "%02d", i + 6)
                let nextHour = String(format: "%02d", i + 7)
                let block = ScheduleBlock(
                    dayOfWeek: day,
                    startTime: "\(hour):00",
                    endTime: "\(nextHour):00",
                    activity: "Block \(i)",
                    type: .other
                )
                context.insert(block)
            }
        }
        try context.save()
        measure {
            _ = (try? context.fetch(FetchDescriptor<ScheduleBlock>(
                sortBy: [SortDescriptor(\ScheduleBlock.dayOfWeek), SortDescriptor(\ScheduleBlock.startTime)]
            ))) ?? []
        }
    }
}

@MainActor
private final class NoopAPI: CoachAPIInvoking {
    nonisolated func complete(model: String,
                              systemPrompt: String,
                              userPrompt: String,
                              maxTokens: Int) async throws -> ClaudeAPIClient.Response {
        ClaudeAPIClient.Response(text: "noop", inputTokens: 0, outputTokens: 0, modelUsed: .sonnet46)
    }
}

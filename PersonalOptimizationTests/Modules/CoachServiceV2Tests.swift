import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class CoachServiceV2Tests: XCTestCase {

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

    // MARK: - CoachPrompts

    func test_coachPrompts_dailyInsight_includesStyle() {
        let prompt = CoachPrompts.system(for: .dailyInsight, style: "stoic")
        XCTAssertTrue(prompt.contains("Style: stoic."))
        XCTAssertTrue(prompt.contains("max 80 words"))
    }

    func test_coachPrompts_prescribeWorkout_outputsJSONFormat() {
        let prompt = CoachPrompts.system(for: .prescribeWorkout, style: "warrior")
        XCTAssertTrue(prompt.contains("Style: warrior."))
        XCTAssertTrue(prompt.contains("workoutType"))
        XCTAssertTrue(prompt.contains("rationale"))
    }

    func test_coachPrompts_differBetweenModes() {
        let insight = CoachPrompts.system(for: .dailyInsight, style: "balanced")
        let prescribe = CoachPrompts.system(for: .prescribeWorkout, style: "balanced")
        let suggest = CoachPrompts.system(for: .suggestSchedule, style: "balanced")
        let weekly = CoachPrompts.system(for: .weeklyProgram, style: "balanced")
        XCTAssertNotEqual(insight, prescribe)
        XCTAssertNotEqual(prescribe, suggest)
        XCTAssertNotEqual(suggest, weekly)
    }

    func test_coachPrompts_customStyle_embedsUserText() {
        let prompt = CoachPrompts.system(
            for: .dailyInsight,
            style: "custom",
            customStylePrompt: "Marcus Aurelius with reps"
        )
        XCTAssertTrue(prompt.contains("custom: Marcus Aurelius with reps"))
    }

    func test_coachPrompts_defaultMaxTokens_perMode() {
        XCTAssertEqual(CoachPrompts.defaultMaxTokens(for: .dailyInsight), 256)
        XCTAssertGreaterThan(CoachPrompts.defaultMaxTokens(for: .prescribeWorkout), 256)
        XCTAssertGreaterThan(CoachPrompts.defaultMaxTokens(for: .weeklyProgram), 1000)
    }

    // MARK: - gatherFullContext

    func test_gatherFullContext_composesTodayAndHistorical() {
        let profile = ensureProfile()
        profile.primaryGoal = "build muscle"
        profile.equipmentAccess = "gym"
        profile.weeklyTrainingTargetSessions = 5
        let service = CoachService(modelContext: context, api: PrescribeStubAPI())
        let ctx = service.gatherFullContext(profile: profile)
        XCTAssertEqual(ctx.primaryGoal, "build muscle")
        XCTAssertEqual(ctx.equipmentAccess, "gym")
        XCTAssertEqual(ctx.weeklyTrainingTargetSessions, 5)
        let summary = ctx.summaryForPrompt
        XCTAssertTrue(summary.contains("Primary goal: build muscle"))
        XCTAssertTrue(summary.contains("Today snapshot"))
        XCTAssertTrue(summary.contains("Historical context"))
    }

    func test_gatherFullContext_secondaryGoalsParsedFromCSV() {
        let profile = ensureProfile()
        profile.secondaryGoalsCSV = "stay sharp on the court, learn Japanese conversational"
        let service = CoachService(modelContext: context, api: PrescribeStubAPI())
        let ctx = service.gatherFullContext(profile: profile)
        XCTAssertEqual(ctx.secondaryGoals.count, 2)
        XCTAssertTrue(ctx.secondaryGoals.contains("stay sharp on the court"))
    }

    // MARK: - prescribeTodaysWorkout

    func test_prescribeTodaysWorkout_createsRowFromValidJSON() async throws {
        let api = PrescribeStubAPI(text: """
        {"workoutType":"lift_a","rationale":"You hit a fresh PR last week. Push.","template":{"exercises":[{"name":"Squat","sets":5,"reps":5,"weightLbs":225}]}}
        """)
        let service = CoachService(modelContext: context, api: api)
        let p = try await service.prescribeTodaysWorkout()
        XCTAssertEqual(p.workoutType, .liftA)
        XCTAssertEqual(p.status, .suggested)
        XCTAssertTrue(p.rationale.contains("PR"))
        XCTAssertTrue(p.template.contains("Squat"))
    }

    func test_prescribeTodaysWorkout_idempotentOnSameDay() async throws {
        let api = PrescribeStubAPI(text: """
        {"workoutType":"rest","rationale":"Recover.","template":{"reason":"low sleep"}}
        """)
        let service = CoachService(modelContext: context, api: api)
        _ = try await service.prescribeTodaysWorkout()
        _ = try await service.prescribeTodaysWorkout()
        XCTAssertEqual(api.callCount, 1)
        let count = try context.fetch(FetchDescriptor<PrescribedWorkout>()).count
        XCTAssertEqual(count, 1)
    }

    func test_prescribeTodaysWorkout_forceRefreshReplacesContent() async throws {
        let api = PrescribeStubAPI(text: """
        {"workoutType":"lift_a","rationale":"Initial","template":{}}
        """)
        let service = CoachService(modelContext: context, api: api)
        _ = try await service.prescribeTodaysWorkout()

        api.text = """
        {"workoutType":"swim","rationale":"Updated","template":{"intensityZone":"z2"}}
        """
        let updated = try await service.prescribeTodaysWorkout(forceRefresh: true)
        XCTAssertEqual(api.callCount, 2)
        XCTAssertEqual(updated.workoutType, .swim)
        XCTAssertTrue(updated.rationale.contains("Updated"))
    }

    func test_prescribeTodaysWorkout_invalidJSON_fallsBackToRest() async throws {
        let api = PrescribeStubAPI(text: "this is not json")
        let service = CoachService(modelContext: context, api: api)
        let p = try await service.prescribeTodaysWorkout()
        XCTAssertEqual(p.workoutType, .rest)
        XCTAssertTrue(p.rationale.contains("not json"))
    }

    func test_prescribeTodaysWorkout_missingAPIKey_throws() async {
        let api = PrescribeStubAPI(error: ClaudeAPIError.missingAPIKey)
        let service = CoachService(modelContext: context, api: api)
        do {
            _ = try await service.prescribeTodaysWorkout()
            XCTFail("Expected throw")
        } catch CoachServiceError.missingAPIKey {
            // expected
        } catch {
            XCTFail("Expected missingAPIKey, got \(error)")
        }
    }

    func test_prescribeTodaysWorkout_stripsCodeFences() async throws {
        let api = PrescribeStubAPI(text: """
        ```json
        {"workoutType":"basketball","rationale":"Sharpen","template":{"durationMin":60}}
        ```
        """)
        let service = CoachService(modelContext: context, api: api)
        let p = try await service.prescribeTodaysWorkout()
        XCTAssertEqual(p.workoutType, .basketball)
    }

    // MARK: - suggestScheduleOptimizations

    func test_suggestScheduleOptimizations_skipsAPIWhenNoPatterns() async throws {
        let api = PrescribeStubAPI(text: "{}")
        let service = CoachService(modelContext: context, api: api)
        let suggestions = try await service.suggestScheduleOptimizations()
        XCTAssertTrue(suggestions.isEmpty)
        XCTAssertEqual(api.callCount, 0)
    }

    func test_suggestScheduleOptimizations_persistsParsedRow() async throws {
        // Seed enough volume-decline data to clear the threshold.
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        for i in -13...0 {
            let day = cal.date(byAdding: .day, value: i, to: today)!
            let lift = LiftSession(date: day, template: "Lift A")
            lift.totalVolumeLbs = (i < -6) ? 1500 : 200
            context.insert(lift)
        }
        try context.save()

        let api = PrescribeStubAPI(text: """
        {"summary":"Shift Wed lift to Thu","detail":"Pattern shows you've been moving it","changeType":"shift_block","changePayload":{"from":3,"to":4}}
        """)
        let service = CoachService(modelContext: context, api: api)
        let suggestions = try await service.suggestScheduleOptimizations()
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.changeType, .shiftBlock)
        XCTAssertEqual(suggestions.first?.status, .pending)
    }

    // MARK: - generateWeeklyProgrammingPass

    func test_generateWeeklyProgrammingPass_createsActiveProgram() async throws {
        let api = PrescribeStubAPI(text: """
        {"narrative":"Build a strength base.","days":{"mon":{"workoutType":"lift_a"},"tue":{"workoutType":"basketball"}}}
        """)
        let service = CoachService(modelContext: context, api: api)
        let program = try await service.generateWeeklyProgrammingPass()
        XCTAssertEqual(program.status, .active)
        XCTAssertTrue(program.coachNarrative.contains("strength"))
        XCTAssertTrue(program.programJSON.contains("lift_a"))
    }

    func test_generateWeeklyProgrammingPass_idempotentInSameWeek() async throws {
        let api = PrescribeStubAPI(text: """
        {"narrative":"Initial","days":{"mon":{"workoutType":"rest"}}}
        """)
        let service = CoachService(modelContext: context, api: api)
        _ = try await service.generateWeeklyProgrammingPass()
        _ = try await service.generateWeeklyProgrammingPass()
        XCTAssertEqual(api.callCount, 1)
    }

    // MARK: - Read APIs

    func test_todaysPrescription_returnsLatest() async throws {
        let api = PrescribeStubAPI(text: """
        {"workoutType":"swim","rationale":"Pool day","template":{}}
        """)
        let service = CoachService(modelContext: context, api: api)
        _ = try await service.prescribeTodaysWorkout()
        let cached = service.todaysPrescription()
        XCTAssertEqual(cached?.workoutType, .swim)
    }

    func test_pendingScheduleSuggestions_filtersByStatus() {
        let pending = ScheduleSuggestion(generatedAt: Date(), summary: "p", detail: "d", changeType: .shiftBlock)
        let dismissed = ScheduleSuggestion(generatedAt: Date(), summary: "d", detail: "d", changeType: .shiftBlock)
        dismissed.status = .dismissed
        context.insert(pending)
        context.insert(dismissed)
        try? context.save()

        let service = CoachService(modelContext: context, api: PrescribeStubAPI())
        let result = service.pendingScheduleSuggestions()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.summary, "p")
    }

    // MARK: - Helpers

    private func ensureProfile() -> UserProfile {
        if let existing = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first {
            return existing
        }
        let p = UserProfile()
        context.insert(p)
        try? context.save()
        return p
    }
}

@MainActor
private final class PrescribeStubAPI: CoachAPIInvoking {
    nonisolated(unsafe) var text: String
    nonisolated(unsafe) var error: Error?
    nonisolated(unsafe) var callCount: Int = 0

    init(text: String = "{}", error: Error? = nil) {
        self.text = text
        self.error = error
    }

    nonisolated func complete(model: String,
                              systemPrompt: String,
                              userPrompt: String,
                              maxTokens: Int) async throws -> ClaudeAPIClient.Response {
        callCount += 1
        if let error { throw error }
        return ClaudeAPIClient.Response(text: text, inputTokens: 100, outputTokens: 50)
    }
}

import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class ScheduleAIServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        // Seed a profile so the service doesn't have to create one in tests.
        let profile = UserProfile()
        profile.anthropicModel = "claude-sonnet-4-6"
        context.insert(profile)
        try context.save()
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Happy path

    func test_generate_validResponse_returnsProposalAndPersistsRun() async throws {
        let payload = #"""
        {
          "blocks": [
            {"dayOfWeek": 1, "startTime": "18:00", "endTime": "19:00",
             "activity": "Lift A", "type": "training", "module": "lift_a",
             "anchorEvent": null, "anchorOffsetMinutes": null}
          ],
          "rationale": "Three lift days, plenty of recovery.",
          "warnings": []
        }
        """#
        let api = StubGenerateAPI(text: payload)
        let service = ScheduleAIService(modelContext: context, api: api)

        let result = try await service.generate(intake: makeIntake())

        XCTAssertEqual(result.proposal.blocks.count, 1)
        XCTAssertEqual(result.proposal.blocks.first?.module, "lift_a")
        XCTAssertEqual(api.callCount, 1, "Happy path must not retry")

        let runs = try context.fetch(FetchDescriptor<ScheduleGenerationRun>())
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.status, .proposed)
    }

    // MARK: - Fence stripping

    func test_generate_jsonWrappedInMarkdownFence_decodesCorrectly() async throws {
        let payload = """
        ```json
        {
          "blocks": [
            {"dayOfWeek": 1, "startTime": "18:00", "endTime": "19:00",
             "activity": "Lift A", "type": "training", "module": "lift_a",
             "anchorEvent": null, "anchorOffsetMinutes": null}
          ],
          "rationale": "ok",
          "warnings": []
        }
        ```
        """
        let api = StubGenerateAPI(text: payload)
        let service = ScheduleAIService(modelContext: context, api: api)

        let result = try await service.generate(intake: makeIntake())
        XCTAssertEqual(result.proposal.blocks.count, 1)
    }

    // MARK: - Retry on validation failure

    func test_generate_invalidThenValid_retriesAndSucceeds() async throws {
        let badPayload = #"""
        {
          "blocks": [
            {"dayOfWeek": 8, "startTime": "18:00", "endTime": "19:00",
             "activity": "Lift A", "type": "training", "module": "lift_a",
             "anchorEvent": null, "anchorOffsetMinutes": null}
          ],
          "rationale": "broken weekday",
          "warnings": []
        }
        """#
        let goodPayload = #"""
        {
          "blocks": [
            {"dayOfWeek": 1, "startTime": "18:00", "endTime": "19:00",
             "activity": "Lift A", "type": "training", "module": "lift_a",
             "anchorEvent": null, "anchorOffsetMinutes": null}
          ],
          "rationale": "fixed",
          "warnings": []
        }
        """#
        let api = StubGenerateAPI(texts: [badPayload, goodPayload])
        let service = ScheduleAIService(modelContext: context, api: api)

        let result = try await service.generate(intake: makeIntake())
        XCTAssertEqual(api.callCount, 2, "Validator must trigger one retry")
        XCTAssertEqual(result.proposal.blocks.first?.dayOfWeek, 1)
    }

    func test_generate_invalidTwice_throwsValidationFailed() async throws {
        let badPayload = #"""
        {
          "blocks": [
            {"dayOfWeek": 9, "startTime": "18:00", "endTime": "19:00",
             "activity": "Lift A", "type": "training", "module": "lift_a",
             "anchorEvent": null, "anchorOffsetMinutes": null}
          ],
          "rationale": "still broken",
          "warnings": []
        }
        """#
        let api = StubGenerateAPI(texts: [badPayload, badPayload])
        let service = ScheduleAIService(modelContext: context, api: api)

        do {
            _ = try await service.generate(intake: makeIntake())
            XCTFail("Expected validationFailedAfterRetry")
        } catch ScheduleAIService.ServiceError.validationFailedAfterRetry {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
        XCTAssertEqual(api.callCount, 2)
    }

    // MARK: - Rejected memory injection

    func test_generate_rejectedSummariesAppearInPrompt() async throws {
        let memoryService = CoachMemoryService(modelContext: context)
        _ = try memoryService.add(value: "shift_block: Move Wed lift to Sat",
                                  key: "rejected_suggestion_aaaa",
                                  importance: 2,
                                  expiresIn: 60)
        _ = try memoryService.add(value: "add_block: Add Friday recovery",
                                  key: "rejected_suggestion_bbbb",
                                  importance: 2,
                                  expiresIn: 60)

        let api = StubGenerateAPI(text: minimalValidPayload)
        let service = ScheduleAIService(modelContext: context, api: api)
        _ = try await service.generate(intake: makeIntake())

        XCTAssertTrue(api.lastUserPrompt.contains("Move Wed lift to Sat"))
        XCTAssertTrue(api.lastUserPrompt.contains("Add Friday recovery"))
        XCTAssertTrue(api.lastUserPrompt.contains("REJECTED PROPOSALS"))
    }

    func test_generate_noRejections_promptHasNoRejectedSection() async throws {
        let api = StubGenerateAPI(text: minimalValidPayload)
        let service = ScheduleAIService(modelContext: context, api: api)
        _ = try await service.generate(intake: makeIntake())

        XCTAssertFalse(api.lastUserPrompt.contains("REJECTED PROPOSALS"))
    }

    // MARK: - Apply path

    func test_applyDrafts_replacesNonCustomAndPreservesCustom() throws {
        // Seed an existing non-custom block (simulating a prior generation).
        let stale = ScheduleBlock(dayOfWeek: 2, startTime: "08:00", endTime: "09:00",
                                  activity: "Stale", type: .training, module: "lift_b")
        context.insert(stale)
        // Seed a user-custom block — must survive the apply.
        let custom = ScheduleBlock(dayOfWeek: 6, startTime: "11:00", endTime: "12:00",
                                   activity: "Date night", type: .family, module: nil)
        custom.isCustom = true
        context.insert(custom)
        try context.save()

        let drafts: [ScheduleBlockDraft] = [
            ScheduleBlockDraft(
                dayOfWeek: 1, startTime: "18:00", endTime: "19:00",
                activity: "Lift A", type: "training", module: "lift_a",
                anchorEvent: nil, anchorOffsetMinutes: nil
            )
        ]
        try ScheduleSeed.applyDrafts(drafts, anchorEvents: ["after_dinner"], modelContext: context)

        let all = try context.fetch(FetchDescriptor<ScheduleBlock>())
        XCTAssertEqual(all.count, 2, "Stale block gone; draft + custom remain")
        XCTAssertTrue(all.contains { $0.activity == "Date night" && $0.isCustom })
        XCTAssertTrue(all.contains { $0.activity == "Lift A" })

        let profile = try XCTUnwrap(context.fetch(FetchDescriptor<UserProfile>()).first)
        XCTAssertNotNil(profile.lastGeneratedAt)
        XCTAssertEqual(profile.anchorEventsCSV, "after_dinner")
    }

    // MARK: - Rejection key dedup

    func test_rejectionKey_sameShapeProducesSameKey() {
        let key1 = ScheduleSuggestionInbox.rejectionKey(
            changeType: "shiftBlock",
            payload: #"{"from":"wed","to":"sat"}"#
        )
        let key2 = ScheduleSuggestionInbox.rejectionKey(
            changeType: "shiftBlock",
            payload: #"{"from":"wed","to":"sat"}"#
        )
        XCTAssertEqual(key1, key2)
        XCTAssertTrue(key1.hasPrefix("rejected_suggestion_"))
    }

    func test_rejectionKey_differentPayloadProducesDifferentKey() {
        let key1 = ScheduleSuggestionInbox.rejectionKey(changeType: "shiftBlock", payload: "a")
        let key2 = ScheduleSuggestionInbox.rejectionKey(changeType: "shiftBlock", payload: "b")
        XCTAssertNotEqual(key1, key2)
    }

    // MARK: - Helpers

    private var minimalValidPayload: String {
        #"""
        {
          "blocks": [
            {"dayOfWeek": 1, "startTime": "18:00", "endTime": "19:00",
             "activity": "Lift A", "type": "training", "module": "lift_a",
             "anchorEvent": null, "anchorOffsetMinutes": null}
          ],
          "rationale": "minimal",
          "warnings": []
        }
        """#
    }

    private func makeIntake() -> ScheduleIntake {
        var intake = ScheduleIntake.blank
        intake.primaryGoal = .strength
        return intake
    }
}

/// Configurable stub. Supports a single response or a sequence (for retry tests).
@MainActor
final class StubGenerateAPI: CoachAPIInvoking {
    nonisolated(unsafe) var texts: [String]
    nonisolated(unsafe) var callCount: Int = 0
    nonisolated(unsafe) var lastUserPrompt: String = ""

    init(text: String) {
        self.texts = [text]
    }

    init(texts: [String]) {
        self.texts = texts
    }

    nonisolated func complete(model: String,
                              systemPrompt: String,
                              userPrompt: String,
                              maxTokens: Int) async throws -> ClaudeAPIClient.Response {
        let nextText: String = await MainActor.run {
            let i = min(callCount, texts.count - 1)
            let t = texts[i]
            callCount += 1
            lastUserPrompt = userPrompt
            return t
        }
        return ClaudeAPIClient.Response(text: nextText, inputTokens: 100, outputTokens: 200, modelUsed: .sonnet46)
    }
}

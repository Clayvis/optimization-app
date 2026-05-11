import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class PersonaServiceTests: XCTestCase {

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

    // MARK: - currentOrCreate

    func test_currentOrCreate_emptyContainer_createsRow() {
        let service = PersonaService(modelContext: context)
        let persona = service.currentOrCreate()
        XCTAssertEqual(persona.confidence, 0)
        XCTAssertTrue(persona.identityAnchorsCSV.isEmpty)
        let count = (try? context.fetch(FetchDescriptor<UserPersona>()))?.count ?? 0
        XCTAssertEqual(count, 1)
    }

    func test_currentOrCreate_existingRow_returnsIt() {
        let p = UserPersona()
        p.identityAnchorsCSV = "competitor"
        context.insert(p)
        try? context.save()

        let returned = PersonaService(modelContext: context).currentOrCreate()
        XCTAssertEqual(returned.identityAnchorsCSV, "competitor")
    }

    // MARK: - recordAnswer

    func test_recordAnswer_appendsKeyAndBumpsConfidence() {
        let service = PersonaService(modelContext: context)
        service.recordAnswer(key: "motivation_driver")
        let persona = service.currentOrCreate()
        XCTAssertTrue(persona.answeredQuestionKeysCSV.contains("motivation_driver"))
        XCTAssertEqual(persona.confidence, 10)
    }

    func test_recordAnswer_isIdempotentPerKey() {
        let service = PersonaService(modelContext: context)
        service.recordAnswer(key: "motivation_driver")
        service.recordAnswer(key: "motivation_driver")
        let persona = service.currentOrCreate()
        // confidence increments only on first answer to the key
        XCTAssertEqual(persona.confidence, 10)
    }

    // MARK: - nextQuestion

    func test_nextQuestion_emptyAnswers_returnsFirstFromLibrary() {
        let service = PersonaService(modelContext: context)
        let next = service.nextQuestion()
        XCTAssertEqual(next?.key, PersonaQuestion.library.first?.key)
    }

    func test_nextQuestion_skipsAnsweredKeys() {
        let service = PersonaService(modelContext: context)
        service.recordAnswer(key: "motivation_driver")
        let next = service.nextQuestion()
        XCTAssertNotEqual(next?.key, "motivation_driver")
    }

    func test_nextQuestion_allAnswered_returnsNil() {
        let service = PersonaService(modelContext: context)
        for q in PersonaQuestion.library {
            service.recordAnswer(key: q.key)
        }
        XCTAssertNil(service.nextQuestion())
    }

    // MARK: - shouldShowWeeklyQuestion

    func test_shouldShowWeeklyQuestion_freshInstall_yes() {
        let service = PersonaService(modelContext: context)
        XCTAssertTrue(service.shouldShowWeeklyQuestion())
    }

    func test_shouldShowWeeklyQuestion_askedToday_no() {
        let service = PersonaService(modelContext: context)
        service.markQuestionAsked()
        XCTAssertFalse(service.shouldShowWeeklyQuestion())
    }

    func test_shouldShowWeeklyQuestion_eightDaysLater_yes() {
        let baseDate = Date()
        let later = baseDate.addingTimeInterval(8 * 86_400)
        let service = PersonaService(modelContext: context, now: { baseDate })
        service.markQuestionAsked()

        let laterService = PersonaService(modelContext: context, now: { later })
        XCTAssertTrue(laterService.shouldShowWeeklyQuestion())
    }

    // MARK: - promptContextBlock

    func test_promptContextBlock_emptyPersona_returnsEmpty() {
        let service = PersonaService(modelContext: context)
        XCTAssertTrue(service.promptContextBlock().isEmpty)
    }

    func test_promptContextBlock_includesOnlyFilledFields() {
        let persona = PersonaService(modelContext: context).currentOrCreate()
        persona.motivationDriverRaw = PersonaMotivationDriver.identity.rawValue
        persona.communicationStyleRaw = PersonaCommunicationStyle.direct.rawValue
        persona.identityAnchorsCSV = "competitor, teacher"
        try? context.save()

        let block = PersonaService(modelContext: context).promptContextBlock()
        XCTAssertTrue(block.contains("USER PERSONA"))
        XCTAssertTrue(block.contains("identity"))
        XCTAssertTrue(block.contains("direct"))
        XCTAssertTrue(block.contains("competitor"))
        XCTAssertTrue(block.contains("teacher"))
        // Doesn't surface unfilled fields
        XCTAssertFalse(block.contains("Failure response"))
    }

    func test_promptContextBlock_historicalAttempts_includesAvoidanceLanguage() {
        let persona = PersonaService(modelContext: context).currentOrCreate()
        persona.historicalAttemptsCSV = "Noom: too restrictive, 5am gym: kids needed me"
        try? context.save()

        let block = PersonaService(modelContext: context).promptContextBlock()
        XCTAssertTrue(block.contains("Do NOT re-recommend"))
        XCTAssertTrue(block.contains("Noom"))
    }
}

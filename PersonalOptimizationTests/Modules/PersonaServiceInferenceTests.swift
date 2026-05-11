import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class PersonaServiceInferenceTests: XCTestCase {

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

    // MARK: - inferFromBehavior

    func test_inferFromBehavior_emptyContainer_returnsNoSignals() {
        let service = PersonaService(modelContext: context)
        XCTAssertTrue(service.inferFromBehavior().isEmpty)
    }

    func test_inferFromBehavior_skipsFieldsAlreadyAnswered() {
        let service = PersonaService(modelContext: context)
        // Pre-fill 8 morning lifts that would otherwise yield peakAlertness signal.
        let cal = Calendar.current
        for offset in 0..<8 {
            let date = cal.date(byAdding: .day, value: -offset, to: Date())!
            let nineAM = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
            let lift = LiftSession(date: nineAM, template: "Lift A")
            lift.durationMinutes = 45
            context.insert(lift)
        }
        try? context.save()

        // First call: signal proposed.
        XCTAssertTrue(service.inferFromBehavior().contains { $0.field == .peakAlertness })

        // User actively answered peak_alertness via questionnaire — passive signal should no longer fire.
        service.recordAnswer(key: "peak_alertness")
        XCTAssertFalse(service.inferFromBehavior().contains { $0.field == .peakAlertness })
    }

    func test_inferFromBehavior_filtersDismissedSignals() {
        let service = PersonaService(modelContext: context)
        let cal = Calendar.current
        for offset in 0..<8 {
            let date = cal.date(byAdding: .day, value: -offset, to: Date())!
            let nineAM = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
            context.insert(LiftSession(date: nineAM, template: "Lift A"))
        }
        try? context.save()

        let signals = service.inferFromBehavior()
        guard let first = signals.first else {
            return XCTFail("Expected at least one signal")
        }

        service.dismissSignal(first)
        XCTAssertFalse(service.inferFromBehavior().contains { $0.key == first.key })
    }

    func test_inferFromBehavior_sortedByConfidenceDescending() {
        let service = PersonaService(modelContext: context)
        let cal = Calendar.current
        // Stack signals: strong peakAlertness (8/8 morning) + weaker failureResponse
        for offset in 0..<8 {
            let date = cal.date(byAdding: .day, value: -offset, to: Date())!
            let nineAM = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
            let lift = LiftSession(date: nineAM, template: "Lift A")
            lift.durationMinutes = 45
            context.insert(lift)
        }
        try? context.save()

        let signals = service.inferFromBehavior()
        let sorted = signals.sorted { $0.confidence > $1.confidence }
        XCTAssertEqual(signals.map(\.key), sorted.map(\.key))
    }

    // MARK: - acceptSignal

    func test_acceptSignal_writesFieldAndBumpsConfidence() {
        let service = PersonaService(modelContext: context)
        let initialConfidence = service.currentOrCreate().confidence

        let signal = PersonaBehavioralInference.PersonaSignal(
            key: "peakAlertness=morning",
            field: .peakAlertness,
            proposedRaw: PersonaPeakAlertness.morning.rawValue,
            proposedDisplay: PersonaPeakAlertness.morning.displayName,
            confidence: 70,
            evidence: "test"
        )
        service.acceptSignal(signal)

        let persona = service.currentOrCreate()
        XCTAssertEqual(persona.peakAlertnessRaw, PersonaPeakAlertness.morning.rawValue)
        XCTAssertEqual(persona.confidence, initialConfidence + 10)
        XCTAssertTrue(persona.answeredQuestionKeysCSV.contains("peak_alertness"))
    }

    func test_acceptSignal_marksAnsweredSoActiveQuestionnaireSkipsIt() {
        let service = PersonaService(modelContext: context)
        let signal = PersonaBehavioralInference.PersonaSignal(
            key: "recoverySensitivity=highListener",
            field: .recoverySensitivity,
            proposedRaw: PersonaRecoverySensitivity.highListener.rawValue,
            proposedDisplay: PersonaRecoverySensitivity.highListener.displayName,
            confidence: 65,
            evidence: "test"
        )
        service.acceptSignal(signal)

        // nextQuestion() should no longer surface recovery_sensitivity
        var nextKey: String? = service.nextQuestion()?.key
        while let key = nextKey, key != "recovery_sensitivity" {
            service.recordAnswer(key: key)
            nextKey = service.nextQuestion()?.key
        }
        XCTAssertNotEqual(nextKey, "recovery_sensitivity")
    }

    // MARK: - dismissSignal

    func test_dismissSignal_persistsToCoachMemory() {
        let service = PersonaService(modelContext: context)
        let signal = PersonaBehavioralInference.PersonaSignal(
            key: "failureResponse=pushThrough",
            field: .failureResponse,
            proposedRaw: PersonaFailureResponse.pushThrough.rawValue,
            proposedDisplay: PersonaFailureResponse.pushThrough.displayName,
            confidence: 60,
            evidence: "test"
        )
        service.dismissSignal(signal)

        let memories = (try? context.fetch(FetchDescriptor<CoachMemory>())) ?? []
        XCTAssertTrue(memories.contains { $0.key == "persona_signal_dismissed_failureResponse=pushThrough" })
    }

    func test_dismissSignal_doesNotWritePersonaField() {
        let service = PersonaService(modelContext: context)
        let signal = PersonaBehavioralInference.PersonaSignal(
            key: "failureResponse=pushThrough",
            field: .failureResponse,
            proposedRaw: PersonaFailureResponse.pushThrough.rawValue,
            proposedDisplay: PersonaFailureResponse.pushThrough.displayName,
            confidence: 60,
            evidence: "test"
        )
        service.dismissSignal(signal)
        XCTAssertNil(service.currentOrCreate().failureResponseRaw)
    }
}

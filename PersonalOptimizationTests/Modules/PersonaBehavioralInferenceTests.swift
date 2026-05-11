import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class PersonaBehavioralInferenceTests: XCTestCase {

    // MARK: - Peak alertness

    func test_peakAlertness_belowThreshold_returnsNil() {
        let lifts = (0..<5).map { _ in PersonaBehavioralInference.LiftStart(hourOfDay: 9) }
        XCTAssertNil(PersonaBehavioralInference.inferPeakAlertness(from: lifts))
    }

    func test_peakAlertness_dominantMorningBucket_returnsMorning() {
        var lifts: [PersonaBehavioralInference.LiftStart] = []
        // 8 mornings, 2 evenings
        for _ in 0..<8 { lifts.append(.init(hourOfDay: 9)) }
        for _ in 0..<2 { lifts.append(.init(hourOfDay: 18)) }

        let signal = PersonaBehavioralInference.inferPeakAlertness(from: lifts)
        XCTAssertNotNil(signal)
        XCTAssertEqual(signal?.proposedRaw, PersonaPeakAlertness.morning.rawValue)
        XCTAssertEqual(signal?.field, .peakAlertness)
        XCTAssertGreaterThanOrEqual(signal?.confidence ?? 0, 60)
    }

    func test_peakAlertness_evenSplit_returnsNil() {
        // 2/bucket across 5 buckets → no bucket reaches 40%
        var lifts: [PersonaBehavioralInference.LiftStart] = []
        for hour in [6, 9, 13, 18, 23] {
            lifts.append(.init(hourOfDay: hour))
            lifts.append(.init(hourOfDay: hour))
        }
        // 10 lifts, max share = 20% → below 40% threshold
        XCTAssertNil(PersonaBehavioralInference.inferPeakAlertness(from: lifts))
    }

    func test_bucket_mapsHoursCorrectly() {
        XCTAssertEqual(PersonaBehavioralInference.bucket(forHour: 6), .earlyMorning)
        XCTAssertEqual(PersonaBehavioralInference.bucket(forHour: 9), .morning)
        XCTAssertEqual(PersonaBehavioralInference.bucket(forHour: 13), .afternoon)
        XCTAssertEqual(PersonaBehavioralInference.bucket(forHour: 18), .evening)
        XCTAssertEqual(PersonaBehavioralInference.bucket(forHour: 23), .lateNight)
        XCTAssertEqual(PersonaBehavioralInference.bucket(forHour: 2), .lateNight)
    }

    // MARK: - Recovery sensitivity

    func test_recoverySensitivity_belowThreshold_returnsNil() {
        let days = (0..<5).map { _ in
            PersonaBehavioralInference.RecoveryDay(hrvRmssd: 50, sleepHours: 8, trained: true)
        }
        XCTAssertNil(PersonaBehavioralInference.inferRecoverySensitivity(from: days))
    }

    func test_recoverySensitivity_lowListener_pushesThroughFatigue() {
        // 10 days, all low-recovery (HRV low) but always trains.
        var days: [PersonaBehavioralInference.RecoveryDay] = []
        for hrv in [30.0, 32, 34, 36, 38] {
            days.append(.init(hrvRmssd: hrv, sleepHours: nil, trained: true))
        }
        for hrv in [60.0, 65, 70, 72, 75] {
            days.append(.init(hrvRmssd: hrv, sleepHours: nil, trained: true))
        }
        let signal = PersonaBehavioralInference.inferRecoverySensitivity(from: days)
        XCTAssertNotNil(signal)
        XCTAssertEqual(signal?.proposedRaw, PersonaRecoverySensitivity.lowListener.rawValue)
    }

    func test_recoverySensitivity_highListener_skipsOnPoorRecovery() {
        // 10 days: low recovery → rarely trains; high recovery → trains often.
        var days: [PersonaBehavioralInference.RecoveryDay] = []
        for (i, hrv) in [30.0, 32, 34, 36, 38].enumerated() {
            days.append(.init(hrvRmssd: hrv, sleepHours: nil, trained: i == 0))
        }
        for hrv in [60.0, 65, 70, 72, 75] {
            days.append(.init(hrvRmssd: hrv, sleepHours: nil, trained: true))
        }
        let signal = PersonaBehavioralInference.inferRecoverySensitivity(from: days)
        XCTAssertNotNil(signal)
        XCTAssertEqual(signal?.proposedRaw, PersonaRecoverySensitivity.highListener.rawValue)
    }

    func test_recoverySensitivity_balanced_closeRates() {
        var days: [PersonaBehavioralInference.RecoveryDay] = []
        for hrv in [30.0, 32, 34, 36, 38] {
            days.append(.init(hrvRmssd: hrv, sleepHours: nil, trained: Bool.random()))
        }
        for hrv in [60.0, 65, 70, 72, 75] {
            days.append(.init(hrvRmssd: hrv, sleepHours: nil, trained: Bool.random()))
        }
        // Random — assert only that we never crash. Specific outcome will vary.
        _ = PersonaBehavioralInference.inferRecoverySensitivity(from: days)
    }

    func test_recoverySensitivity_fallsBackToSleepWhenHRVMissing() {
        var days: [PersonaBehavioralInference.RecoveryDay] = []
        // 5 short-sleep days with training, 5 long-sleep days with training → low listener.
        for s in [4.5, 5.0, 5.2, 5.5, 5.8] {
            days.append(.init(hrvRmssd: nil, sleepHours: s, trained: true))
        }
        for s in [8.0, 8.2, 8.5, 8.7, 9.0] {
            days.append(.init(hrvRmssd: nil, sleepHours: s, trained: true))
        }
        let signal = PersonaBehavioralInference.inferRecoverySensitivity(from: days)
        XCTAssertNotNil(signal)
        XCTAssertEqual(signal?.proposedRaw, PersonaRecoverySensitivity.lowListener.rawValue)
    }

    // MARK: - Failure response

    func test_failureResponse_belowThreshold_returnsNil() {
        let pairs = [
            PersonaBehavioralInference.SkipDayPair(trainedNextDay: true, nextDayDurationMinutes: 45, typicalDurationMinutes: 45)
        ]
        XCTAssertNil(PersonaBehavioralInference.inferFailureResponse(from: pairs))
    }

    func test_failureResponse_pushThroughDominant() {
        let pairs = (0..<5).map { _ in
            PersonaBehavioralInference.SkipDayPair(trainedNextDay: true, nextDayDurationMinutes: 50, typicalDurationMinutes: 45)
        }
        let signal = PersonaBehavioralInference.inferFailureResponse(from: pairs)
        XCTAssertEqual(signal?.proposedRaw, PersonaFailureResponse.pushThrough.rawValue)
    }

    func test_failureResponse_recalibrateDominant() {
        // Trained next day but at < 70% typical → recalibrate
        let pairs = (0..<5).map { _ in
            PersonaBehavioralInference.SkipDayPair(trainedNextDay: true, nextDayDurationMinutes: 25, typicalDurationMinutes: 60)
        }
        let signal = PersonaBehavioralInference.inferFailureResponse(from: pairs)
        XCTAssertEqual(signal?.proposedRaw, PersonaFailureResponse.recalibrate.rawValue)
    }

    func test_failureResponse_restDominant() {
        let pairs = (0..<5).map { _ in
            PersonaBehavioralInference.SkipDayPair(trainedNextDay: false, nextDayDurationMinutes: nil, typicalDurationMinutes: 45)
        }
        let signal = PersonaBehavioralInference.inferFailureResponse(from: pairs)
        XCTAssertEqual(signal?.proposedRaw, PersonaFailureResponse.rest.rawValue)
    }

    func test_failureResponse_noMajority_returnsNil() {
        // 1-1-1 split across 3 events
        let pairs = [
            PersonaBehavioralInference.SkipDayPair(trainedNextDay: true, nextDayDurationMinutes: 45, typicalDurationMinutes: 45),
            PersonaBehavioralInference.SkipDayPair(trainedNextDay: true, nextDayDurationMinutes: 20, typicalDurationMinutes: 45),
            PersonaBehavioralInference.SkipDayPair(trainedNextDay: false, nextDayDurationMinutes: nil, typicalDurationMinutes: 45)
        ]
        XCTAssertNil(PersonaBehavioralInference.inferFailureResponse(from: pairs))
    }

    // MARK: - Decision style

    func test_decisionStyle_belowThreshold_returnsNil() {
        let outcomes = PersonaBehavioralInference.SuggestionOutcomes(accepted: 2, dismissed: 1, snoozed: 1)
        XCTAssertNil(PersonaBehavioralInference.inferDecisionStyle(from: outcomes))
    }

    func test_decisionStyle_highAccept_advice() {
        let outcomes = PersonaBehavioralInference.SuggestionOutcomes(accepted: 8, dismissed: 2, snoozed: 0)
        let signal = PersonaBehavioralInference.inferDecisionStyle(from: outcomes)
        XCTAssertEqual(signal?.proposedRaw, PersonaDecisionStyle.advice.rawValue)
    }

    func test_decisionStyle_highDismiss_data() {
        let outcomes = PersonaBehavioralInference.SuggestionOutcomes(accepted: 1, dismissed: 9, snoozed: 0)
        let signal = PersonaBehavioralInference.inferDecisionStyle(from: outcomes)
        XCTAssertEqual(signal?.proposedRaw, PersonaDecisionStyle.data.rawValue)
    }

    func test_decisionStyle_midRange_returnsNil() {
        let outcomes = PersonaBehavioralInference.SuggestionOutcomes(accepted: 5, dismissed: 5, snoozed: 0)
        XCTAssertNil(PersonaBehavioralInference.inferDecisionStyle(from: outcomes))
    }
}

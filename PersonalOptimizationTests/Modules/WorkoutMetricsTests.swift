import XCTest
import HealthKit
@testable import PersonalOptimization

/// Pure-logic coverage for the Training metrics layer: MET calorie math,
/// activity-type mappings, distance-identifier selection, and the recap
/// formatter feeding the Training hub tiles.
final class WorkoutMetricsTests: XCTestCase {

    // MARK: - Calorie estimation

    func test_estimatedKcal_matchesCompendiumFormula() {
        // 6.5 MET × 3.5 × 93.0 kg / 200 × 60 min = 634.7 kcal (205 lbs).
        let kcal = WorkoutMetrics.estimatedKcal(met: 6.5, weightLbs: 205, minutes: 60)
        XCTAssertEqual(kcal, 6.5 * 3.5 * (205 * 0.45359237) / 200 * 60, accuracy: 0.001)
        XCTAssertEqual(kcal, 634.7, accuracy: 0.5)
    }

    func test_estimatedKcal_invalidInputsReturnZero() {
        XCTAssertEqual(WorkoutMetrics.estimatedKcal(met: 0, weightLbs: 205, minutes: 60), 0)
        XCTAssertEqual(WorkoutMetrics.estimatedKcal(met: 6.5, weightLbs: 0, minutes: 60), 0)
        XCTAssertEqual(WorkoutMetrics.estimatedKcal(met: 6.5, weightLbs: 205, minutes: 0), 0)
        XCTAssertEqual(WorkoutMetrics.estimatedKcal(met: -1, weightLbs: -5, minutes: -10), 0)
    }

    func test_metForTemplateName_keywordMatches() {
        XCTAssertEqual(WorkoutMetrics.met(forTemplateNamed: "Running"), 9.0)
        XCTAssertEqual(WorkoutMetrics.met(forTemplateNamed: "Morning walk"), 3.5)
        XCTAssertEqual(WorkoutMetrics.met(forTemplateNamed: "HIIT circuit"), 8.0)
        XCTAssertEqual(WorkoutMetrics.met(forTemplateNamed: "Yoga"), 3.0)
        XCTAssertEqual(WorkoutMetrics.met(forTemplateNamed: "Cycling"), 7.5)
        XCTAssertEqual(WorkoutMetrics.met(forTemplateNamed: "Rucking"), 6.5)
        XCTAssertEqual(WorkoutMetrics.met(forTemplateNamed: "Mystery sport"), 5.0)
    }

    // MARK: - HealthKit activity mapping

    func test_hkActivityType_mapsKnownTemplates() {
        XCTAssertEqual(WorkoutMetrics.hkActivityType(forTemplateNamed: "Running"), .running)
        XCTAssertEqual(WorkoutMetrics.hkActivityType(forTemplateNamed: "Walking"), .walking)
        XCTAssertEqual(WorkoutMetrics.hkActivityType(forTemplateNamed: "HIIT"), .highIntensityIntervalTraining)
        XCTAssertEqual(WorkoutMetrics.hkActivityType(forTemplateNamed: "Yoga"), .yoga)
        XCTAssertEqual(WorkoutMetrics.hkActivityType(forTemplateNamed: "Bike ride"), .cycling)
        XCTAssertEqual(WorkoutMetrics.hkActivityType(forTemplateNamed: "Hiking"), .hiking)
        XCTAssertEqual(WorkoutMetrics.hkActivityType(forTemplateNamed: "Rucking"), .hiking)
        XCTAssertEqual(WorkoutMetrics.hkActivityType(forTemplateNamed: "Freestyle"), .other)
    }

    func test_distanceIdentifier_perActivity() {
        XCTAssertEqual(WorkoutMetrics.distanceIdentifier(for: .swimming), .distanceSwimming)
        XCTAssertEqual(WorkoutMetrics.distanceIdentifier(for: .cycling), .distanceCycling)
        XCTAssertEqual(WorkoutMetrics.distanceIdentifier(for: .basketball), .distanceWalkingRunning)
        XCTAssertEqual(WorkoutMetrics.distanceIdentifier(for: .running), .distanceWalkingRunning)
        XCTAssertNil(WorkoutMetrics.distanceIdentifier(for: .functionalStrengthTraining))
        XCTAssertNil(WorkoutMetrics.distanceIdentifier(for: .traditionalStrengthTraining))
        XCTAssertNil(WorkoutMetrics.distanceIdentifier(for: .yoga))
    }

    // MARK: - Recap formatting

    func test_recapLine_allSegments() {
        let line = WorkoutMetrics.recapLine(durationMinutes: 42, kcal: 310.4, distanceMeters: 3380)
        XCTAssertEqual(line, "42 min · 310 kcal · 2.1 mi")
    }

    func test_recapLine_dropsMissingSegments() {
        XCTAssertEqual(WorkoutMetrics.recapLine(durationMinutes: 30, kcal: nil, distanceMeters: nil), "30 min")
        XCTAssertEqual(WorkoutMetrics.recapLine(durationMinutes: nil, kcal: 250, distanceMeters: nil), "250 kcal")
        XCTAssertNil(WorkoutMetrics.recapLine(durationMinutes: nil, kcal: nil, distanceMeters: nil))
        XCTAssertNil(WorkoutMetrics.recapLine(durationMinutes: 0, kcal: 0.4, distanceMeters: 0))
    }

    func test_milesText_shortDistancesUseYards() {
        XCTAssertEqual(WorkoutMetrics.milesText(meters: 50), "55 yd")
        XCTAssertEqual(WorkoutMetrics.milesText(meters: 1609.344), "1.0 mi")
        XCTAssertEqual(WorkoutMetrics.milesText(meters: 5000), "3.1 mi")
    }

    // MARK: - Closing kcal preference

    @MainActor
    func test_closingKcal_prefersMeasuredThenEstimate() {
        let metrics = LiveWorkoutMetrics(
            healthKit: nil,
            sessionStart: Date(),
            activityType: .basketball
        )
        // No measured energy, no weight → nil.
        XCTAssertNil(metrics.closingKcal(met: 6.5, weightLbs: nil, elapsedMinutes: 45))
        // No measured energy, weight present → MET estimate.
        let estimated = metrics.closingKcal(met: 6.5, weightLbs: 205, elapsedMinutes: 45)
        XCTAssertEqual(estimated ?? 0,
                       WorkoutMetrics.estimatedKcal(met: 6.5, weightLbs: 205, minutes: 45),
                       accuracy: 0.001)
        // Zero elapsed → estimate under 1 kcal → nil, not a junk 0-kcal row.
        XCTAssertNil(metrics.closingKcal(met: 6.5, weightLbs: 205, elapsedMinutes: 0))
    }
}

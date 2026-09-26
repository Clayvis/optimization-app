import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class InBodyCoachTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return cal
    }
    private func scan(day: Int = 1) -> InBodyValues {
        var value = InBodyValues()
        value.date = calendar.date(from: DateComponents(year: 2026, month: 1, day: day))!
        value.heightInches = 70; value.weightLb = 200; value.skeletalMuscleMassLb = 90
        value.leanBodyMassLb = 160; value.bodyFatMassLb = 40; value.bodyFatPercent = 20
        value.totalBodyWaterLb = 110; value.ecwTbwRatio = 0.354
        return value
    }
    func test_comparisonSeparatesMuscleWaterAndFat() throws {
        let first = scan()
        var next = scan(day: 15)
        next.weightLb = 202; next.skeletalMuscleMassLb = 90.5
        next.leanBodyMassLb = 161.5; next.totalBodyWaterLb = 111; next.bodyFatMassLb = 40.5
        next.ecwTbwRatio = 0.360
        let result = try BodyCompositionComparison(previous: first, current: next, calendar: calendar)
        XCTAssertEqual(result.days, 14)
        XCTAssertEqual(result.weeklyWeight, 1)
        XCTAssertEqual(result.skeletalMuscle, 0.5)
        XCTAssertEqual(result.leanMass, 1.5)
        XCTAssertEqual(result.water, 1)
        XCTAssertEqual(result.comparability, .moderate)
        XCTAssertTrue(result.segments.isEmpty)
    }
    func test_exactConfidenceBoundariesAndMissingValues() throws {
        let first = scan()
        for (ratio, expected) in [(0.357, BodyCompositionComparison.Comparability.high), (0.361, .moderate), (0.362, .low)] {
            var next = scan(day: 2); next.ecwTbwRatio = ratio
            XCTAssertEqual(try BodyCompositionComparison(previous: first, current: next, calendar: calendar).comparability, expected)
        }
        var next = scan(day: 2); next.ecwTbwRatio = nil
        XCTAssertEqual(try BodyCompositionComparison(previous: first, current: next, calendar: calendar).comparability, .unknown)
    }
    func test_sameDayReverseAndInvalidScansRejected() throws {
        XCTAssertThrowsError(try BodyCompositionComparison(previous: scan(), current: scan(), calendar: calendar))
        XCTAssertThrowsError(try BodyCompositionComparison(previous: scan(day: 3), current: scan(), calendar: calendar))
        var invalid = scan(); invalid.weightLb = .nan
        XCTAssertThrowsError(try invalid.validate())
        invalid = scan(); invalid.ecwTbwRatio = 1.2
        XCTAssertThrowsError(try invalid.validate())
    }
    func test_importIdempotentAndValidatesEntireBatch() throws {
        let container = try InMemoryContainer.make(); let context = container.mainContext
        let first = scan()
        try InBodyService.save([first], context: context)
        try InBodyService.save([first], context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InBodyScan>()), 1)
        var invalid = scan(day: 3); invalid.weightLb = -10
        XCTAssertThrowsError(try InBodyService.save([scan(day: 2), invalid], context: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InBodyScan>()), 1)
        XCTAssertThrowsError(try InBodyService.save([scan()], context: context))
    }
    func test_emptyIncompleteAndCompletedProgression() {
        XCTAssertFalse(HypertrophyRules.shouldIncreaseWeight(reps: [], plannedSets: 3, upperReps: 15))
        XCTAssertFalse(HypertrophyRules.shouldIncreaseWeight(reps: [15, 15], plannedSets: 3, upperReps: 15))
        XCTAssertFalse(HypertrophyRules.shouldIncreaseWeight(reps: [15, 15, 14], plannedSets: 3, upperReps: 15))
        XCTAssertTrue(HypertrophyRules.shouldIncreaseWeight(reps: [15, 15, 15], plannedSets: 3, upperReps: 15))
    }
    func test_pullVolumeAndRecoveryLimitAdditionalForearmSets() {
        let date = scan().date
        let rows = (0..<12).map { _ in TrainingSetEvidence(date: date, exercise: "Cable row", weight: 100, reps: 12, rir: 2) }
            + (0..<10).map { _ in TrainingSetEvidence(date: date, exercise: "Hammer curl", weight: 20, reps: 12, rir: 2) }
        let guidance = HypertrophyRules.guidance(focus: .init(), sets: rows, asOf: date, calendar: calendar,
                                               recoveryLimited: false, calfPainConstraint: true)
        let forearms = guidance.first { $0.muscle == "Forearms" }!
        XCTAssertEqual(forearms.directSets, 10)
        XCTAssertEqual(forearms.effectiveSets, 16)
        XCTAssertTrue(forearms.recommendation.contains("Do not add"))
        XCTAssertTrue(guidance.first { $0.muscle == "Calves" }!.recommendation.contains("recovery"))
    }
    func test_unknownEffortDoesNotRecommendMoreSets() {
        let date = scan().date
        let rows = [TrainingSetEvidence(date: date, exercise: "Standing calf raise", weight: 100, reps: 12, rir: nil)]
        let result = HypertrophyRules.guidance(focus: .init(), sets: rows, asOf: date, calendar: calendar,
                                             recoveryLimited: false, calfPainConstraint: false)
        XCTAssertTrue(result.first { $0.muscle == "Calves" }!.recommendation.contains("baseline"))
    }
    func test_additiveMigrationPreservesExistingData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        do {
            let schema = Schema(versionedSchema: SchemaV11.self)
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let old = try ModelContainer(for: schema, configurations: [config])
            old.mainContext.insert(UserProfile(name: "Migration test"))
            try old.mainContext.save()
        }
        let schema = AppSchema.schema()
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let migrated = try ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])
        XCTAssertEqual(try migrated.mainContext.fetch(FetchDescriptor<UserProfile>()).first?.name, "Migration test")
        try InBodyService.save([scan()], context: migrated.mainContext)
        XCTAssertEqual(try migrated.mainContext.fetchCount(FetchDescriptor<InBodyScan>()), 1)
    }
    func test_backupRoundTripPreservesScansAndRIR() throws {
        let source = try InMemoryContainer.make()
        try InBodyService.save([scan()], context: source.mainContext)
        let session = LiftSession(date: scan().date, template: "Test")
        let exercise = LiftExercise(name: "Seated calf raise", orderIndex: 0)
        let set = LiftSet(weightLbs: 50, reps: 15, orderIndex: 0)
        set.repsInReserve = 2
        exercise.sets = [set]; exercise.progressionUpperReps = 20
        session.exercises = [exercise]
        source.mainContext.insert(session)
        try source.mainContext.save()
        let data = try JSONExportService.export(modelContext: source.mainContext)
        let destination = try InMemoryContainer.make()
        try JSONImportService.restore(data: data, modelContext: destination.mainContext)
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<InBodyScan>()), 1)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<LiftSet>()).first?.repsInReserve, 2)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<LiftExercise>()).first?.progressionUpperReps, 20)
    }

    // MARK: - Coach analysis (deterministic verdict)

    private func pair(muscle: Double, fatMass: Double, fatPoints: Double, weightPerWeek: Double,
                      ecw: Double? = 0.360) throws -> BodyCompositionComparison {
        let first = scan()
        var next = first
        next.id = UUID()
        next.date = calendar.date(byAdding: .day, value: 56, to: first.date)!
        next.weightLb = first.weightLb + weightPerWeek * 8
        next.skeletalMuscleMassLb = first.skeletalMuscleMassLb + muscle
        next.leanBodyMassLb = first.leanBodyMassLb + 2 * muscle
        next.bodyFatMassLb = first.bodyFatMassLb + fatMass
        next.bodyFatPercent = first.bodyFatPercent + fatPoints
        next.ecwTbwRatio = ecw
        return try BodyCompositionComparison(previous: first, current: next, calendar: calendar)
    }

    func test_specExampleReadsAsProductiveButFastGain() throws {
        // Same shape as the spec example: muscle +1.3, fat +1.6, +0.3 points, ~0.6 lb/week, ECW/TBW +0.006.
        let result = BodyCompositionAssessment(comparison: try pair(muscle: 1.3, fatMass: 1.6, fatPoints: 0.3, weightPerWeek: 0.6),
                                               focus: HypertrophyFocus())
        XCTAssertEqual(result.headline, "Productive muscle-gaining phase")
        XCTAssertEqual(result.muscle, .rising)
        XCTAssertEqual(result.fatMass, .rising)
        XCTAssertEqual(result.bodyFatPercent, .stable)
        XCTAssertEqual(result.gainRate, .above)
        XCTAssertEqual(result.comparability, .moderate)
        XCTAssertTrue(result.recommendations[0].contains("Trim the calorie surplus"))
        XCTAssertEqual(result.recommendations.count, 1, "No focus line when the focus is off; no caution at moderate comparability.")
    }

    func test_enabledFocusNamesPrioritiesAndUnknownHydrationAddsCaution() throws {
        var focus = HypertrophyFocus()
        focus.enabled = true
        let result = BodyCompositionAssessment(comparison: try pair(muscle: 1.3, fatMass: 1.6, fatPoints: 0.3,
                                                                    weightPerWeek: 0.4, ecw: nil), focus: focus)
        XCTAssertEqual(result.gainRate, .within)
        XCTAssertTrue(result.recommendations.contains { $0.contains("thighs") && $0.contains("forearms") })
        XCTAssertTrue(result.recommendations.contains { $0.contains("Hydration differs") })
    }

    func test_fatGainWithoutMuscleAndMuscleLossHeadlines() throws {
        XCTAssertEqual(BodyCompositionAssessment(comparison: try pair(muscle: 0.2, fatMass: 2, fatPoints: 1, weightPerWeek: 0.3),
                                                 focus: HypertrophyFocus()).headline,
                       "Body fat rising without measurable muscle gain")
        XCTAssertEqual(BodyCompositionAssessment(comparison: try pair(muscle: -0.8, fatMass: 0, fatPoints: 0, weightPerWeek: 0.3),
                                                 focus: HypertrophyFocus()).headline,
                       "Estimated muscle trending down")
    }

    func test_changesInsideTheNoiseBandReadStable() throws {
        let result = BodyCompositionAssessment(comparison: try pair(muscle: 0.5, fatMass: -0.5, fatPoints: 0.5, weightPerWeek: 0.3),
                                               focus: HypertrophyFocus())
        XCTAssertEqual(result.muscle, .stable)
        XCTAssertEqual(result.fatMass, .stable)
        XCTAssertEqual(result.bodyFatPercent, .stable)
        XCTAssertEqual(result.headline, "Holding steady")
    }

    func test_slowGainWithRisingMuscleNeedsNoCalorieChange() throws {
        let result = BodyCompositionAssessment(comparison: try pair(muscle: 0.8, fatMass: -0.5, fatPoints: -0.6, weightPerWeek: 0.1),
                                               focus: HypertrophyFocus())
        XCTAssertEqual(result.gainRate, .below)
        XCTAssertEqual(result.headline, "Productive muscle-gaining phase")
        XCTAssertTrue(result.recommendations[0].contains("No calorie change"))
    }
}

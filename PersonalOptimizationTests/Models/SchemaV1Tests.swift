import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class SchemaV1Tests: XCTestCase {

    func test_schemaV1_includesAll15Models() {
        let names = Set(SchemaV1.models.map { String(describing: $0) })
        let expected: Set<String> = [
            "UserProfile", "ScheduleBlock", "DailyLog",
            "LiftSession", "LiftExercise", "LiftSet",
            "BasketballSession", "SwimSession", "LabDraw",
            "WearableEntry", "ProtocolEntry", "PomodoroSession",
            "AdminTask", "LearningStreak", "CharacterStateLog"
        ]
        XCTAssertEqual(names, expected)
    }

    func test_inMemoryContainer_initializesWithoutError() throws {
        _ = try InMemoryContainer.make()
    }

    func test_inMemoryContainer_persistsAndFetchesUserProfile() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext

        let profile = UserProfile(name: "Clay", dob: Date(timeIntervalSince1970: 764985600), sex: "male")
        context.insert(profile)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserProfile>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Clay")
        XCTAssertEqual(fetched.first?.timezone, "Asia/Tokyo")
        XCTAssertEqual(fetched.first?.fastWindowStartHour, 22)
        XCTAssertEqual(fetched.first?.bottleSizeOz, 32)
    }

    func test_inMemoryContainer_cascadeDeletesLiftSetsAndExercises() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext

        let session = LiftSession(date: Date(), template: "Lift A")
        let exercise = LiftExercise(name: "Squat", orderIndex: 0)
        let set = LiftSet(weightLbs: 225, reps: 5, orderIndex: 0)
        exercise.sets?.append(set)
        session.exercises?.append(exercise)
        context.insert(session)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<LiftSession>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LiftExercise>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LiftSet>()).count, 1)

        context.delete(session)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<LiftSession>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LiftExercise>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LiftSet>()).count, 0)
    }

    func test_dailyLog_dateIsUnique() throws {
        let container = try InMemoryContainer.make()
        let context = container.mainContext
        let day = Calendar.current.startOfDay(for: Date())

        context.insert(DailyLog(date: day))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailyLog>()).count, 1)
    }

    func test_characterState_precedenceOrderHasAllEightStates() {
        XCTAssertEqual(CharacterState.precedenceOrder.count, CharacterState.allCases.count)
        XCTAssertEqual(Set(CharacterState.precedenceOrder), Set(CharacterState.allCases))
    }
}

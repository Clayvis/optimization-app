import XCTest
import SwiftData
@testable import PersonalOptimization

@MainActor
final class SwimServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var service: SwimService!

    override func setUp() async throws {
        try await super.setUp()
        container = try InMemoryContainer.make()
        context = container.mainContext
        service = SwimService(modelContext: context)
    }

    override func tearDown() async throws {
        service = nil
        context = nil
        container = nil
        try await super.tearDown()
    }

    func test_startSession_default25m() throws {
        let s = try service.startSession(at: Date())
        XCTAssertEqual(s.poolLengthMeters, 25)
        XCTAssertEqual(s.laps, 0)
        XCTAssertEqual(s.totalMeters, 0)
    }

    func test_startSession_customPoolLength() throws {
        let s = try service.startSession(at: Date(), poolLengthMeters: 50, location: "Hansen")
        XCTAssertEqual(s.poolLengthMeters, 50)
        XCTAssertEqual(s.location, "Hansen")
    }

    func test_logLap_singleLap_updatesTotalMeters() throws {
        let s = try service.startSession(at: Date(), poolLengthMeters: 25)
        try service.logLap(in: s)
        XCTAssertEqual(s.laps, 1)
        XCTAssertEqual(s.totalMeters, 25)
    }

    func test_logLap_multipleLaps_accumulates() throws {
        let s = try service.startSession(at: Date(), poolLengthMeters: 25)
        try service.logLap(in: s, count: 10)
        try service.logLap(in: s, count: 6)
        XCTAssertEqual(s.laps, 16)
        XCTAssertEqual(s.totalMeters, 400)
    }

    func test_logLap_at50mPool_doublesPerLap() throws {
        let s = try service.startSession(at: Date(), poolLengthMeters: 50)
        try service.logLap(in: s, count: 8)
        XCTAssertEqual(s.totalMeters, 400)
    }

    func test_endSession_writesDurationAndAvgHR() throws {
        let s = try service.startSession(at: Date())
        try service.logLap(in: s, count: 20)
        try service.endSession(s, durationMinutes: 35, avgHR: 145)
        XCTAssertEqual(s.durationMinutes, 35)
        XCTAssertEqual(s.avgHR, 145)
        XCTAssertEqual(s.totalMeters, 500)
    }

    func test_currentSession_returnsActiveSession() throws {
        _ = try service.startSession(at: Date())
        XCTAssertNotNil(service.currentSession(at: Date()))
    }

    func test_currentSession_returnsNilAfterEnd() throws {
        let s = try service.startSession(at: Date())
        try service.endSession(s, durationMinutes: 30)
        XCTAssertNil(service.currentSession(at: Date()))
    }
}

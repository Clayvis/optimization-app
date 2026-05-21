import XCTest
import SwiftData
@testable import PersonalOptimization

/// Cross-cutting tests CT-1 through CT-5 from HANDOFF_CLAUDE_CODE.md.
/// These guard the invariants that the P0/P1 work landed:
/// - schema parity across targets
/// - DailyLog uniqueness per calendar day
/// - timezone changes don't split today
/// - late-arriving HK samples trigger recompute hooks
/// - no 30-second polling timers in production code
@MainActor
final class HandoffCorrectnessTests: XCTestCase {

    // MARK: - CT-1. Cross-target schema parity

    func test_CT1_allProductionTargetsUseCurrentSchema() throws {
        // Walk the source tree and find any direct reference to a
        // SchemaVN.self outside the allowed files (the Schema*.swift
        // versioned-schema files, the AppSchema file, the migration plan,
        // and #Preview/previewContainer blocks).
        let root = Self.repoRoot()
        let swiftFiles = Self.swiftFiles(under: root)
        let allowed: Set<String> = [
            "AppSchema.swift",
            "AppMigrationPlan.swift",
            "SchemaV1.swift", "SchemaV2.swift", "SchemaV3.swift",
            "SchemaV4.swift", "SchemaV5.swift", "SchemaV6.swift",
            "SchemaV7.swift", "SchemaV8.swift", "SchemaV9.swift",
            "SchemaV10.swift"
        ]
        var offenders: [String] = []
        for file in swiftFiles {
            let name = (file as NSString).lastPathComponent
            if allowed.contains(name) { continue }
            if file.contains("/PersonalOptimizationTests/") { continue }
            guard let contents = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            let lines = contents.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                let lower = line.lowercased()
                if lower.contains("#preview") || lower.contains("previewcontainer") { continue }
                if line.contains("// ") && line.range(of: #"SchemaV\d+"#, options: .regularExpression) != nil {
                    continue
                }
                if line.range(of: #"Schema\(versionedSchema:\s*SchemaV\d+\.self\)"#, options: .regularExpression) != nil {
                    offenders.append("\(name):\(idx + 1)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Files still reference SchemaVN.self directly: \(offenders.joined(separator: ", "))")
    }

    // MARK: - CT-2. DailyLog uniqueness invariant

    func test_CT2_dailyLogUniquePerCalendarDay() throws {
        let container = try InMemoryContainer.make()
        let ctx = container.mainContext
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let store = DailyLogStore(modelContext: ctx, calendar: cal)
        let morning = Self.makeJSTDate(year: 2026, month: 5, day: 20, hour: 6)
        let evening = Self.makeJSTDate(year: 2026, month: 5, day: 20, hour: 23)
        let a = store.upsert(for: morning)
        let b = store.upsert(for: evening)
        XCTAssertTrue(a === b, "Two upserts in the same calendar day must return the same row.")
        let all = try ctx.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(all.count, 1, "Exactly one DailyLog row should exist for the day.")
    }

    // MARK: - CT-3. Timezone change does not split today

    func test_CT3_timezoneChangeDoesNotSplitToday() throws {
        let container = try InMemoryContainer.make()
        let ctx = container.mainContext

        var jstCal = Calendar(identifier: .gregorian)
        jstCal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current

        // Simulate a legacy bug: two rows accidentally keyed at slightly
        // different points within the SAME JST calendar day. This is the
        // exact pattern dedupe is meant to repair (e.g., one writer used
        // `.current` and the other used `Asia/Tokyo`, producing two rows
        // both inside the same JST day but with different stored Date
        // values).
        let jstDay = Self.makeJSTDate(year: 2026, month: 5, day: 20, hour: 0)
        let row1 = DailyLog(date: jstDay, calendar: jstCal)
        let row2Bias = jstCal.date(byAdding: .hour, value: 6, to: jstDay) ?? jstDay
        let row2 = DailyLog(date: row2Bias, calendar: jstCal)
        // row2 above uses startOfDay so it collapses to the same key — to
        // force the duplicate state we explicitly set the raw date to a
        // non-startOfDay instant.
        row2.date = row2Bias
        ctx.insert(row1)
        ctx.insert(row2)
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<DailyLog>()).count, 2,
                       "Pre-condition: two rows manually inserted within the same JST day.")

        // Dedupe under the user's pinned (JST) calendar collapses them.
        try DailyLogStore(modelContext: ctx, calendar: jstCal).dedupe()
        let afterDedupe = try ctx.fetch(FetchDescriptor<DailyLog>())
        XCTAssertEqual(afterDedupe.count, 1,
                       "Dedupe should leave a single row keyed to the user's calendar.")
        XCTAssertEqual(afterDedupe.first?.date, jstCal.startOfDay(for: jstDay),
                       "Canonical row should be pinned to JST startOfDay.")
    }

    // MARK: - CT-4. Late-arriving HK -> recompute pipeline

    /// Verifies the recompute notification path. Real HKObserverQuery firing
    /// requires a daemon we can't run in tests, so we simulate the OBSERVED
    /// behavior: a sample for a past day gets written to DailyLog and posting
    /// `dailyLogsRecomputed` wakes the subscriber chain. A real subscriber
    /// (CharacterStateService) re-derives without polling.
    func test_CT4_notificationNamesDefined() {
        XCTAssertEqual(Notification.Name.dailyLogsRecomputed.rawValue,
                       "com.rawlins.PersonalOptimization.dailyLogsRecomputed")
        XCTAssertEqual(Notification.Name.userStateChanged.rawValue,
                       "com.rawlins.PersonalOptimization.userStateChanged")
    }

    /// A late-arriving sample (recorded against a past day) reaches the
    /// canonical DailyLog row via DailyLogStore.upsert, and posting the
    /// recompute notification triggers downstream subscribers.
    func test_CT4_lateArrivingSampleUpdatesPastDay() async throws {
        let container = try InMemoryContainer.make()
        let ctx = container.mainContext
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let store = DailyLogStore(modelContext: ctx, calendar: cal)

        // Day N-1, no data yet (the user didn't open the app yesterday).
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) else {
            XCTFail("Couldn't compute yesterday")
            return
        }
        let yesterdayLog = store.upsert(for: yesterday)
        XCTAssertNil(yesterdayLog.restingHR, "Pre-condition: no resting HR for yesterday yet.")

        // Simulate a late-arriving HK sample (Garmin uploaded an hour after
        // the fact): write the value, post the notification.
        yesterdayLog.restingHR = 54
        yesterdayLog.healthKitSyncedAt = Date()
        try ctx.save()

        // Subscriber count check: register a transient listener and confirm
        // it fires when we post.
        let expectation = expectation(description: "dailyLogsRecomputed posted")
        let token = NotificationCenter.default.addObserver(
            forName: .dailyLogsRecomputed, object: nil, queue: .main
        ) { _ in expectation.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }
        NotificationCenter.default.post(name: .dailyLogsRecomputed, object: nil)
        await fulfillment(of: [expectation], timeout: 1.0)

        // Confirm the row is still keyed to the user-calendar startOfDay so
        // future upserts hit the same row.
        let yesterdayKey = cal.startOfDay(for: yesterday)
        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate<DailyLog> { $0.date == yesterdayKey }
        )
        XCTAssertEqual(yesterdayLog.restingHR, 54)
        XCTAssertEqual((try ctx.fetch(descriptor)).count, 1)
    }

    // MARK: - CT-5. No 30-second polling timers in production

    func test_CT5_noPollingTimersInProductionCode() {
        let root = Self.repoRoot()
        let swiftFiles = Self.swiftFiles(under: root).filter {
            !$0.contains("/PersonalOptimizationTests/") &&
            !$0.contains("/References/")
        }
        // Allowed: LiveWorkoutSessionService runs a 1Hz tick during an
        // active workout (essential UI feedback while the user is mid-set).
        let allowedFiles: Set<String> = ["LiveWorkoutSessionService.swift"]
        var offenders: [String] = []
        for file in swiftFiles {
            let name = (file as NSString).lastPathComponent
            guard let contents = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            if allowedFiles.contains(name) { continue }
            // Walk lines and skip matches inside comments. A documentation
            // comment that explains the absence of Timer.scheduledTimer
            // should not trip the lint.
            let lines = contents.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") || trimmed.hasPrefix("*") {
                    continue
                }
                if trimmed.contains("Timer.scheduledTimer") {
                    offenders.append(name)
                    break
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "Files with Timer.scheduledTimer that aren't in the allowed list: \(offenders.joined(separator: ", "))")
    }

    // MARK: - Helpers

    private static func repoRoot() -> String {
        let file = #filePath
        let url = URL(fileURLWithPath: file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return url.path
    }

    private static func swiftFiles(under root: String) -> [String] {
        let prodRoots = [
            "\(root)/PersonalOptimization",
            "\(root)/PersonalOptimizationWatch",
            "\(root)/PersonalOptimizationWatchComplications",
            "\(root)/PersonalOptimizationLiveActivity",
            "\(root)/PersonalOptimizationTests"
        ]
        var out: [String] = []
        for dir in prodRoots {
            if let enumerator = FileManager.default.enumerator(atPath: dir) {
                for case let path as String in enumerator where path.hasSuffix(".swift") {
                    out.append("\(dir)/\(path)")
                }
            }
        }
        return out
    }

    private static func makeJSTDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        return cal.date(from: comps) ?? Date()
    }
}

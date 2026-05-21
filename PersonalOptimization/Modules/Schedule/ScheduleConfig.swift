import Foundation

struct FastingWindowSpec: Decodable, Sendable {
    let start: String  // "HH:mm"
    let end: String
}

struct Phase1FastingDefaults: Decodable, Sendable {
    let trainingDays: FastingWindowSpec
    let trainingDayNumbers: [Int]
    let otherDays: FastingWindowSpec
}

struct Phase2FastingDefaults: Decodable, Sendable {
    let all: FastingWindowSpec
}

struct FastingDefaults: Decodable, Sendable {
    let weeks_1_2: Phase1FastingDefaults
    let weeks_3_plus: Phase2FastingDefaults
}

struct HydrationTarget: Decodable, Sendable {
    let min: Double
    let max: Double
    let appliesTo: [Int]
}

struct HydrationTargetsOz: Decodable, Sendable {
    let rest: HydrationTarget
    let lift: HydrationTarget
    let basketball: HydrationTarget
    let swim: HydrationTarget

    /// Fallback used when `default_schedule.json` is unreadable (notification
    /// quick-action path, defensive Coach paths). Rest = lift = 64-96 oz, the
    /// rough sedentary baseline; basketball / swim mirror lift so a missing
    /// config never blocks logging a bottle.
    static let placeholder = HydrationTargetsOz(
        rest: HydrationTarget(min: 64, max: 96, appliesTo: [1, 2, 3, 4, 5, 6, 7]),
        lift: HydrationTarget(min: 80, max: 112, appliesTo: [1, 2, 3, 4, 5, 6, 7]),
        basketball: HydrationTarget(min: 96, max: 128, appliesTo: [1, 2, 3, 4, 5, 6, 7]),
        swim: HydrationTarget(min: 80, max: 112, appliesTo: [1, 2, 3, 4, 5, 6, 7])
    )
}


struct ScheduleConfig: Decodable, Sendable {
    let fastingDefaults: FastingDefaults
    let hydrationTargetsOz: HydrationTargetsOz
    let hydrationCutoffTime: String  // "HH:mm"
}

enum ScheduleConfigError: LocalizedError {
    case resourceMissing
    case decodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .resourceMissing: return "default_schedule.json missing from app bundle"
        case .decodingFailed(let e): return "Failed to decode schedule config: \(e.localizedDescription)"
        }
    }
}

enum ScheduleConfigLoader {
    static func load(bundle: Bundle = .main) throws -> ScheduleConfig {
        guard let url = bundle.url(forResource: "default_schedule", withExtension: "json") else {
            throw ScheduleConfigError.resourceMissing
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ScheduleConfig.self, from: data)
        } catch {
            throw ScheduleConfigError.decodingFailed(error)
        }
    }

    /// Process-lifetime cached accessor. The bundled JSON never changes at
    /// runtime, so re-parsing it from every TodayView body evaluation or
    /// every Coach prompt construction is pure overhead. First call parses;
    /// subsequent calls return the in-memory ScheduleConfig.
    /// MainActor-isolated since the most common callers (Views, Coach)
    /// already live there; background tasks should explicitly await the
    /// hop or use `load(bundle:)` directly.
    @MainActor private static var mainActorCache: ScheduleConfig?

    @MainActor
    static func loadCached(bundle: Bundle = .main) throws -> ScheduleConfig {
        if let mainActorCache { return mainActorCache }
        let config = try load(bundle: bundle)
        mainActorCache = config
        return config
    }

    /// Invalidates the cached config. Tests use this in setUp() to force a
    /// re-parse so they can swap the bundle.
    @MainActor
    static func resetCache() {
        mainActorCache = nil
    }
}

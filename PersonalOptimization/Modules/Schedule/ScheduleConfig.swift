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
}

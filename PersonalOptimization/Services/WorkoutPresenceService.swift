import Foundation
import Observation

/// Lightweight, privacy-safe presence signal for an in-progress workout.
/// The paired Watch sends start/end events immediately; persistence keeps the
/// phone aware across a foreground transition without storing workout detail.
@MainActor
@Observable
final class WorkoutPresenceService {
    static let shared = WorkoutPresenceService()

    private(set) var isActive = false
    private(set) var workoutType: String?
    private(set) var startedAt: Date?

    private let defaults: UserDefaults
    private let activeKey = "workoutPresence.active"
    private let typeKey = "workoutPresence.type"
    private let startKey = "workoutPresence.startedAt"
    private let staleAfter: TimeInterval = 6 * 60 * 60

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedStart = defaults.object(forKey: startKey) as? Date
        if defaults.bool(forKey: activeKey),
           let savedStart,
           Date().timeIntervalSince(savedStart) < staleAfter {
            isActive = true
            workoutType = defaults.string(forKey: typeKey)
            startedAt = savedStart
        } else {
            clear()
        }
    }

    func handle(_ event: WatchConnectivityEvent) {
        switch event.kind {
        case .workoutStarted:
            start(type: event.payload["template"] ?? event.payload["type"] ?? "workout")
        case .workoutEnded:
            end()
        default:
            break
        }
    }

    func start(type: String, at date: Date = Date()) {
        isActive = true
        workoutType = type
        startedAt = date
        defaults.set(true, forKey: activeKey)
        defaults.set(type, forKey: typeKey)
        defaults.set(date, forKey: startKey)
        NotificationCenter.default.post(name: .workoutPresenceChanged, object: nil)
    }

    func end() {
        clear()
        NotificationCenter.default.post(name: .workoutPresenceChanged, object: nil)
    }

    var coachSummary: String {
        guard isActive else { return "No live workout signal." }
        let type = workoutType ?? "workout"
        let elapsed = startedAt.map { max(0, Int(Date().timeIntervalSince($0) / 60)) } ?? 0
        return "Workout in progress: \(type), approximately \(elapsed) minutes elapsed. Do not prescribe a second workout; coach the current session, hydration, pacing, or recovery."
    }

    private func clear() {
        isActive = false
        workoutType = nil
        startedAt = nil
        defaults.removeObject(forKey: activeKey)
        defaults.removeObject(forKey: typeKey)
        defaults.removeObject(forKey: startKey)
    }
}

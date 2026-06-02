import Foundation
import SwiftData
import os

/// Subscribes to `dailyLogsRecomputed` and `userStateChanged` so the
/// persistent rollups (StreakCounter rows) stay in sync after late-arriving
/// HealthKit samples or watch-side events land. Wire once at app launch.
///
/// Why this exists: HealthKitSyncService.syncRange posts
/// `dailyLogsRecomputed`. CharacterStateService subscribes directly because
/// it has its own observable surface. But StreakCounter rows are
/// SwiftData-backed — they need an explicit `recompute(domain:asOf:)` call
/// to refresh. Without this listener, late-arriving samples updated DailyLog
/// but the user's streak counters stayed stale until the next foreground
/// hydration / fast / learning write.
@MainActor
final class ReactiveRecomputeService {
    static let shared = ReactiveRecomputeService()

    private var modelContainer: ModelContainer?
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger.persistence
    /// Throttle: ignore back-to-back fires within this window. HK observers
    /// can fan out heavily — a single Garmin sync delivers samples in a
    /// burst that triggers dailyLogsRecomputed up to a dozen times within
    /// seconds. 15s window keeps the main actor free between bursts. The
    /// recompute itself runs synchronously on main because StreakService is
    /// @MainActor and the heavy fetches are already predicate-bounded
    /// after Item 5, so per-domain runtime is bounded.
    private let throttleWindow: TimeInterval = 15
    private var lastRunAt: Date?

    private init() {}

    func start(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        stop()
        // HealthKit fan-out is bursty, so the HK-sourced signal is throttled.
        observers.append(NotificationCenter.default.addObserver(
            forName: .dailyLogsRecomputed, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.runIfNotThrottled() }
        })
        // A foreground log (water, fast, learning, lift) is a rare, deliberate
        // user action, so recompute the streak counters immediately with no
        // throttle. This is what makes the streak chips and master metric move
        // the instant the user taps, rather than on the next HealthKit sync.
        observers.append(NotificationCenter.default.addObserver(
            forName: .userStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.run() }
        })
    }

    func stop() {
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()
    }

    /// Test-only hook: clears the throttle state so a subsequent fire is
    /// not silently swallowed by the 15s window. Not exposed in Release.
    #if DEBUG
    func resetThrottleForTesting() {
        lastRunAt = nil
    }
    #endif

    private func runIfNotThrottled() {
        if let last = lastRunAt, Date().timeIntervalSince(last) < throttleWindow {
            return
        }
        run()
    }

    /// Recomputes every streak domain from source. Call directly for foreground
    /// user actions (no throttle); `runIfNotThrottled` gates the bursty HK path.
    private func run() {
        lastRunAt = Date()
        guard let container = modelContainer else { return }
        let context = container.mainContext

        // Recompute every streak domain so a foreground log, or a late-arriving
        // HK workout / sleep / weight sample, updates the persistent counter the
        // UI reads from.
        let targets = try? ScheduleConfigLoader.loadCached().hydrationTargetsOz  // MARK: try? justified - best-effort decode/fetch; nil result is acceptable.
        let streakService = StreakService(
            modelContext: context,
            hydrationTargets: targets
        )
        for domain in StreakDomain.allCases {
            _ = try? streakService.recompute(domain: domain)  // MARK: try? justified - best-effort; failure logged inside the called function.
        }
        logger.info("ReactiveRecomputeService recomputed \(StreakDomain.allCases.count, privacy: .public) streak domains.")
    }
}

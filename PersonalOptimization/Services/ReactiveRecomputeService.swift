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
    /// can fan out; we don't need to spend the CPU twice in 5 seconds.
    private let throttleWindow: TimeInterval = 5
    private var lastRunAt: Date?

    private init() {}

    func start(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        stop()
        observers.append(NotificationCenter.default.addObserver(
            forName: .dailyLogsRecomputed, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.runIfNotThrottled() }
        })
    }

    func stop() {
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()
    }

    private func runIfNotThrottled() {
        if let last = lastRunAt, Date().timeIntervalSince(last) < throttleWindow {
            return
        }
        lastRunAt = Date()
        guard let container = modelContainer else { return }
        let context = container.mainContext

        // Recompute every streak domain so a late-arriving HK workout, sleep,
        // or weight sample updates the persistent counter the UI reads from.
        let targets = try? ScheduleConfigLoader.load().hydrationTargetsOz
        let streakService = StreakService(
            modelContext: context,
            hydrationTargets: targets
        )
        for domain in StreakDomain.allCases {
            _ = try? streakService.recompute(domain: domain)
        }
        logger.info("ReactiveRecomputeService recomputed \(StreakDomain.allCases.count, privacy: .public) streak domains after dailyLogsRecomputed.")
    }
}

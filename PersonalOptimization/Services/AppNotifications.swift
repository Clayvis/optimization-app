import Foundation

extension Notification.Name {
    /// Fired by HealthKitSyncService whenever it materially updates one or more
    /// DailyLog rows. Listeners (StreakService, CharacterStateService,
    /// TrendAnalyticsService) should rederive their cached values from source.
    static let dailyLogsRecomputed = Notification.Name("com.rawlins.PersonalOptimization.dailyLogsRecomputed")

    /// Fired when a user-state-changing event happens (water logged, fast
    /// transitioned, workout finished). Distinct from dailyLogsRecomputed,
    /// which is HealthKit-sourced and can spam.
    static let userStateChanged = Notification.Name("com.rawlins.PersonalOptimization.userStateChanged")
}

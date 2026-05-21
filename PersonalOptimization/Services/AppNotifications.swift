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

    /// Fired when iOS receives a Handoff NSUserActivity from the paired
    /// watch (or vice versa). `object` is a `HandoffPayload`. Listeners
    /// in tab/screen code can route the user to the matching session
    /// screen with the template pre-filled.
    static let handoffActivityContinued = Notification.Name("com.rawlins.PersonalOptimization.handoffActivityContinued")
}

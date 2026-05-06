import Foundation
import UserNotifications
import os

// MARK: - Identifiers

enum NotificationIdentifier {
    static let fastStartCategory = "fast.start"
    static let fastEndCategory = "fast.end"
    static let hydrationCategory = "hydration"
    static let learningCategory = "learning"

    static let actionLog8oz = "log_8oz"
    static let actionLog16oz = "log_16oz"
    static let actionLog24oz = "log_24oz"
    static let actionLog32oz = "log_32oz"
    static let actionSkip = "skip"
}

// MARK: - Suppression rules

enum NotificationSuppressionRules {

    /// Returns true if a hydration ping at `time` should be suppressed.
    /// Pure function: sleep window check, hydration cutoff, morning intake bypass.
    static func shouldSuppressHydration(
        at time: Date,
        timezone: TimeZone,
        morningIntakeOz: Double,
        cutoffTime: String = "21:00"
    ) -> Bool {
        let minutes = minutesFromMidnight(time, timezone: timezone)

        // Sleep window: 22:00 (1320) through next day 07:00 (420).
        // The window wraps midnight: minutes >= 1320 OR minutes < 420.
        if minutes >= 22 * 60 || minutes < 7 * 60 {
            return true
        }

        // Hydration cutoff (default 21:00).
        if let cutoffMinutes = parseTimeMinutes(cutoffTime), minutes >= cutoffMinutes {
            return true
        }

        // Pre-10:00 with morning intake already logged: no need to nag.
        if minutes < 10 * 60 && morningIntakeOz >= 16 {
            return true
        }

        return false
    }

    private static func minutesFromMidnight(_ date: Date, timezone: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let comps = cal.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private static func parseTimeMinutes(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }
}

// MARK: - Center protocol (for test doubles)

protocol NotificationCenterProtocol: AnyObject, Sendable {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func removePendingNotificationRequests(withIdentifiers: [String])
    func pendingNotificationRequests() async -> [UNNotificationRequest]
}

final class LiveNotificationCenter: NotificationCenterProtocol, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        await center.pendingNotificationRequests()
    }
}

// MARK: - Service

@MainActor
final class NotificationService {

    static let shared = NotificationService()

    private let center: NotificationCenterProtocol
    private let logger = Logger.app
    private var authorizationRequested = false

    init(center: NotificationCenterProtocol = LiveNotificationCenter()) {
        self.center = center
    }

    /// Idempotently requests authorization and registers notification categories.
    @discardableResult
    func register() async throws -> Bool {
        if authorizationRequested {
            return true
        }
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        authorizationRequested = true
        registerCategories()
        logger.info("Notification authorization granted=\(granted, privacy: .public)")
        return granted
    }

    private func registerCategories() {
        let log8 = UNNotificationAction(
            identifier: NotificationIdentifier.actionLog8oz,
            title: "8 oz",
            options: [.authenticationRequired]
        )
        let log16 = UNNotificationAction(
            identifier: NotificationIdentifier.actionLog16oz,
            title: "16 oz",
            options: [.authenticationRequired]
        )
        let log24 = UNNotificationAction(
            identifier: NotificationIdentifier.actionLog24oz,
            title: "24 oz",
            options: [.authenticationRequired]
        )
        let log32 = UNNotificationAction(
            identifier: NotificationIdentifier.actionLog32oz,
            title: "32 oz",
            options: [.authenticationRequired]
        )
        let skip = UNNotificationAction(
            identifier: NotificationIdentifier.actionSkip,
            title: "Skip",
            options: []
        )

        let hydration = UNNotificationCategory(
            identifier: NotificationIdentifier.hydrationCategory,
            actions: [log8, log16, log24, log32, skip],
            intentIdentifiers: [],
            options: []
        )

        let fastStart = UNNotificationCategory(
            identifier: NotificationIdentifier.fastStartCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        let fastEnd = UNNotificationCategory(
            identifier: NotificationIdentifier.fastEndCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        let learning = UNNotificationCategory(
            identifier: NotificationIdentifier.learningCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([hydration, fastStart, fastEnd, learning])
    }

    // MARK: - Scheduling

    @discardableResult
    func scheduleFastStart(at date: Date, label: String) async throws -> String {
        let id = "fast.start.\(date.timeIntervalSince1970)"
        let content = UNMutableNotificationContent()
        content.title = IdentityCopy.Notification.fastStartTitle
        content.body = IdentityCopy.Notification.fastStartBody(label: label)
        content.categoryIdentifier = NotificationIdentifier.fastStartCategory
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await center.add(request)
        return id
    }

    @discardableResult
    func scheduleFastEnd(at date: Date, label: String) async throws -> String {
        let id = "fast.end.\(date.timeIntervalSince1970)"
        let content = UNMutableNotificationContent()
        content.title = IdentityCopy.Notification.fastEndTitle
        content.body = IdentityCopy.Notification.fastEndBody(label: label)
        content.categoryIdentifier = NotificationIdentifier.fastEndCategory
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await center.add(request)
        return id
    }

    /// Schedules a hydration reminder. Returns the request identifier or nil if suppressed.
    @discardableResult
    func scheduleHydrationReminder(
        at date: Date,
        progressOz: Double,
        targetMaxOz: Double,
        timezone: TimeZone,
        morningIntakeOz: Double,
        cutoffTime: String = "21:00"
    ) async throws -> String? {
        if NotificationSuppressionRules.shouldSuppressHydration(
            at: date, timezone: timezone, morningIntakeOz: morningIntakeOz, cutoffTime: cutoffTime
        ) {
            logger.info("Suppressed hydration reminder at \(date, privacy: .public)")
            return nil
        }

        let id = "hydration.\(date.timeIntervalSince1970)"
        let content = UNMutableNotificationContent()
        content.title = IdentityCopy.Notification.hydrationTitle
        content.body = IdentityCopy.Notification.hydrationBody(progressOz: progressOz, targetMaxOz: targetMaxOz)
        content.categoryIdentifier = NotificationIdentifier.hydrationCategory
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await center.add(request)
        return id
    }

    @discardableResult
    func scheduleLearningReminder(at date: Date,
                                  moduleName: String,
                                  targetMinutes: Int) async throws -> String {
        let id = "learning.\(moduleName).\(date.timeIntervalSince1970)"
        let content = UNMutableNotificationContent()
        content.title = IdentityCopy.Notification.learningTitle(moduleName: moduleName)
        content.body = IdentityCopy.Notification.learningBody(moduleName: moduleName, targetMinutes: targetMinutes)
        content.categoryIdentifier = NotificationIdentifier.learningCategory
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await center.add(request)
        return id
    }

    func cancel(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

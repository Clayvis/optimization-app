import Foundation
import UserNotifications
import SwiftData
import os

/// Handles user interactions with delivered notifications. Wired as the
/// UNUserNotificationCenterDelegate during app launch. Routes hydration
/// action buttons (8 / 16 / 24 / 32 oz, Skip) into HydrationService.
/// Fast / learning categories currently route through the default tap so
/// the app opens; quick actions can be added later without changing the
/// handler shape.
@MainActor
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationActionHandler()

    private let logger = Logger.app
    private var modelContainer: ModelContainer?

    func attach(to center: UNUserNotificationCenter = .current(), modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        center.delegate = self
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show alerts while foregrounded so the user sees the same banner they
    /// would on the lock screen. Sound stays off in foreground to avoid
    /// double-trigger with any in-app feedback haptic.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionId = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        await MainActor.run {
            handle(actionId: actionId, category: category)
        }
    }

    /// Pure routing logic, exposed for tests so they don't need to construct
    /// the un-constructible UNNotificationResponse.
    func handle(actionId: String, category: String) {
        logger.info("Notification action category=\(category, privacy: .public) action=\(actionId, privacy: .public)")
        guard let container = modelContainer else {
            logger.warning("Notification action received but no model container attached")
            return
        }
        let context = container.mainContext

        switch category {
        case NotificationIdentifier.hydrationCategory:
            handleHydrationAction(actionId, context: context)
        case NotificationIdentifier.fastStartCategory,
             NotificationIdentifier.fastEndCategory,
             NotificationIdentifier.learningCategory:
            // Default tap opens the app; tab routing belongs to RootView
            // via onContinueUserActivity / scene-state. No quick actions
            // defined for these categories yet.
            break
        default:
            break
        }
    }

    private func handleHydrationAction(_ actionId: String, context: ModelContext) {
        let oz: Double
        switch actionId {
        case NotificationIdentifier.actionLog8oz: oz = 8
        case NotificationIdentifier.actionLog16oz: oz = 16
        case NotificationIdentifier.actionLog24oz: oz = 24
        case NotificationIdentifier.actionLog32oz: oz = 32
        case NotificationIdentifier.actionSkip:
            logger.info("Hydration reminder dismissed via Skip")
            return
        default:
            return
        }
        // MARK: - try? justified because ScheduleConfig is a bundled resource;
        // a parse failure leaves `targets` nil and HydrationService still
        // logs the entry against today's DailyLog using its built-in defaults.
        let targets = try? ScheduleConfigLoader.loadCached().hydrationTargetsOz
        let service = HydrationService(modelContext: context, targets: targets ?? .placeholder)
        do {
            _ = try service.logBottle(oz: oz)
            NotificationCenter.default.post(name: .userStateChanged, object: nil)
            logger.info("Logged \(Int(oz), privacy: .public) oz via notification action")
        } catch {
            logger.warning("Hydration quick-log failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

import Foundation
import SwiftData
import ActivityKit

/// One schedule block, reduced to what the status line needs.
struct StatusBlock: Equatable, Sendable {
    let activity: String
    let startTime: String   // "HH:mm"
    let endTime: String
    let module: String?
}

/// What the Lock Screen says, and the moment it stops being true.
struct ActiveStatusContent: Equatable, Sendable {
    let message: String?
    let freshUntil: Date?
}

/// The Lock Screen / Dynamic Island status that replaces habit reminders.
/// A snapshot of real progress, updated on foreground, confirmed logs and
/// Health deliveries. ActivityKit cannot run the app on a local reminder
/// schedule while it is suspended, so the content carries its own freshness
/// deadline and turns stale instead of showing an outdated schedule.
@MainActor
enum ActiveStatusService {
    static func refresh(context: ModelContext, startIfNeeded: Bool, asOf: Date = Date()) async {
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing"),
              !ProcessInfo.processInfo.arguments.contains("--unit-testing") else { return }
        let snapshot = ProtocolGoalSnapshot.make(modelContext: context, asOf: asOf)
        let calendar = UserCalendar.current(modelContext: context)
        let day = calendar.startOfDay(for: asOf)
        let log = context.fetchOrEmpty(FetchDescriptor<DailyLog>(predicate: #Predicate {
            $0.date == day && $0.supersededAt == nil
        })).first
        let blocks = ScheduleService(modelContext: context).todayBlocks(for: asOf).map {
            StatusBlock(activity: $0.activity, startTime: $0.startTime, endTime: $0.endTime, module: $0.module)
        }
        let minutes: [LearningModule: Int] = [
            .japanese: log?.japaneseMinutes ?? 0,
            .guitar: log?.guitarMinutes ?? 0,
            .music: log?.musicMinutes ?? 0
        ]
        let content = compose(blocks: blocks, practiceMinutes: minutes,
                              moveKcal: log?.activeEnergyBurnedKcal, asOf: asOf, calendar: calendar)
        await DailyGoalLiveActivityController.shared.refreshInstance(
            completedDomains: snapshot.completedDomains, totalDomains: snapshot.totalDomains,
            streak: snapshot.streak, startIfNeeded: startIfNeeded,
            statusMessage: content.message, freshUntil: content.freshUntil,
            asOf: asOf, calendar: calendar)
    }

    /// Pure. The schedule line is the block happening now, else the next one;
    /// the content is fresh only until that block changes. Practice lines come
    /// from the user's own schedule plus anything already logged today, never
    /// a fixed list, so a tester without Japanese or guitar blocks never sees
    /// those targets.
    static func compose(blocks: [StatusBlock],
                        practiceMinutes: [LearningModule: Int],
                        moveKcal: Double?,
                        asOf: Date,
                        calendar: Calendar) -> ActiveStatusContent {
        let clock = calendar.dateComponents([.hour, .minute], from: asOf)
        let now = (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
        func moment(_ minutes: Int) -> Date? {
            calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: asOf)
        }
        let timed = blocks.compactMap { block -> (block: StatusBlock, start: Int, end: Int)? in
            guard let start = ScheduleService.parseTimeToMinutes(block.startTime),
                  let end = ScheduleService.parseTimeToMinutes(block.endTime) else { return nil }
            return (block, start, end)
        }.sorted { $0.start < $1.start }

        var parts: [String] = []
        var freshUntil: Date?
        if let current = timed.first(where: { now >= $0.start && now < $0.end }) {
            parts.append("Now: \(current.block.activity)")
            freshUntil = moment(current.end)
        } else if let next = timed.first(where: { $0.start > now }) {
            parts.append("Next: \(next.block.activity) at \(next.block.startTime)")
            freshUntil = moment(next.start)
        }

        var modules: [LearningModule] = []
        for entry in timed {
            if let raw = entry.block.module, let module = LearningModule(rawValue: raw), !modules.contains(module) {
                modules.append(module)
            }
        }
        for module in LearningModule.allCases where (practiceMinutes[module] ?? 0) > 0 && !modules.contains(module) {
            modules.append(module)
        }
        for module in modules {
            parts.append("\(module.displayName) \(practiceMinutes[module] ?? 0)/\(module.defaultDailyTargetMinutes) min")
        }
        if let kcal = moveKcal, kcal.isFinite {
            parts.append("Move \(Int(kcal.rounded())) kcal")
        }
        return ActiveStatusContent(message: parts.isEmpty ? nil : parts.joined(separator: " · "),
                                   freshUntil: freshUntil)
    }
}

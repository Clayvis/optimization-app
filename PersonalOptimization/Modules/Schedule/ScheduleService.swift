import Foundation
import SwiftData
import os

@MainActor
final class ScheduleService {
    private let modelContext: ModelContext
    private let timezone: TimeZone

    init(modelContext: ModelContext, timezone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) {
        self.modelContext = modelContext
        self.timezone = timezone
    }

    /// Returns template blocks for the ISO weekday of `date`, sorted ascending by startTime.
    func todayBlocks(for date: Date) -> [ScheduleBlock] {
        let weekday = isoWeekday(for: date)
        let descriptor = FetchDescriptor<ScheduleBlock>(
            predicate: #Predicate<ScheduleBlock> { $0.dayOfWeek == weekday && $0.isOverride == false },
            sortBy: [SortDescriptor(\.startTime)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Returns the block whose [start, end) range contains `date`.
    func currentBlock(at date: Date) -> ScheduleBlock? {
        let blocks = todayBlocks(for: date)
        let nowMinutes = minutesFromMidnight(at: date)
        return blocks.first { block in
            guard let s = ScheduleService.parseTimeToMinutes(block.startTime),
                  let e = ScheduleService.parseTimeToMinutes(block.endTime) else { return false }
            return nowMinutes >= s && nowMinutes < e
        }
    }

    /// Returns the next block starting strictly after `date` on the same ISO weekday.
    func nextBlock(after date: Date) -> ScheduleBlock? {
        let blocks = todayBlocks(for: date)
        let nowMinutes = minutesFromMidnight(at: date)
        return blocks.first { block in
            guard let s = ScheduleService.parseTimeToMinutes(block.startTime) else { return false }
            return s > nowMinutes
        }
    }

    /// Time interval until the next block boundary (start or end) on the same ISO weekday.
    /// Returns nil if no upcoming boundary today.
    func timeUntilNextTransition(from date: Date) -> TimeInterval? {
        let blocks = todayBlocks(for: date)
        let nowMinutes = minutesFromMidnight(at: date)

        var boundaries: [Int] = []
        for b in blocks {
            if let s = ScheduleService.parseTimeToMinutes(b.startTime), s > nowMinutes {
                boundaries.append(s)
            }
            if let e = ScheduleService.parseTimeToMinutes(b.endTime), e > nowMinutes {
                boundaries.append(e)
            }
        }
        guard let nextBoundary = boundaries.min() else { return nil }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let secondsIntoMinute = Double(cal.component(.second, from: date))
        let minutesDelta = Double(nextBoundary - nowMinutes)
        return minutesDelta * 60 - secondsIntoMinute
    }

    // MARK: - Helpers

    func minutesFromMidnight(at date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let comps = cal.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    /// Returns ISO 8601 weekday: Monday=1, Sunday=7.
    func isoWeekday(for date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let raw = cal.component(.weekday, from: date)
        return raw == 1 ? 7 : raw - 1
    }

    /// Parses "HH:mm" into total minutes from midnight. Returns nil on malformed input.
    static func parseTimeToMinutes(_ s: String) -> Int? {
        let parts = s.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}

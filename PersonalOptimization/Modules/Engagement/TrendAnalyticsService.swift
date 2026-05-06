import Foundation
import SwiftData
import os

/// Training domains analytics can split on.
enum TrainingDomain: String, Codable, CaseIterable, Sendable {
    case lift
    case basketball
    case swim
    case learning
    case fasting
    case hydration
}

/// Closed date range with day-resolution semantics. Half-inclusive (start <= d < end+1day).
struct DateRange: Sendable, Equatable {
    let start: Date
    let end: Date

    static func lastNDays(_ n: Int, asOf: Date = Date(), timezone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current) -> DateRange {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        let endDay = cal.startOfDay(for: asOf)
        let startDay = cal.date(byAdding: .day, value: -(n - 1), to: endDay) ?? endDay
        return DateRange(start: startDay, end: endDay)
    }
}

/// Compact historical summary handed to Coach prompts. Stays under ~500 tokens
/// when serialized to plain text via `summaryForPrompt`.
struct CoachContextHistorical: Sendable {
    var rangeDescription: String
    var dailyAdherenceMean: Double           // 0.0-1.0
    var dailyAdherence7dRolling: [Double]    // last seven values, oldest first
    var workoutsPerWeekMean: Double
    var workoutsPerWeekTrend: Double         // delta last-half vs first-half
    var liftVolumeWeekOverWeek: Double       // pct change last week vs prior week
    var hydrationMissRatio: Double           // 0.0-1.0 of days under target
    var fastingCompletionRate: Double        // 0.0-1.0
    var learningMinutesPerWeekMean: Double
    var detectedPatternHeadlines: [String]   // top-3 by confidence

    var summaryForPrompt: String {
        var lines: [String] = []
        lines.append("Range: \(rangeDescription).")
        lines.append("Daily adherence mean: \(formatPct(dailyAdherenceMean)).")
        if !dailyAdherence7dRolling.isEmpty {
            let last7 = dailyAdherence7dRolling.suffix(7).map { formatPct($0) }.joined(separator: ", ")
            lines.append("Last 7d adherence: \(last7).")
        }
        lines.append("Workouts/week mean: \(String(format: "%.1f", workoutsPerWeekMean)) (trend \(formatTrend(workoutsPerWeekTrend))).")
        lines.append("Lift volume w/w: \(formatTrend(liftVolumeWeekOverWeek)).")
        lines.append("Hydration miss ratio: \(formatPct(hydrationMissRatio)).")
        lines.append("Fasting completion: \(formatPct(fastingCompletionRate)).")
        lines.append("Learning minutes/week mean: \(Int(learningMinutesPerWeekMean)).")
        if !detectedPatternHeadlines.isEmpty {
            lines.append("Patterns: \(detectedPatternHeadlines.joined(separator: " | "))")
        }
        return lines.joined(separator: "\n")
    }

    private func formatPct(_ d: Double) -> String {
        return "\(Int((d * 100).rounded()))%"
    }

    private func formatTrend(_ d: Double) -> String {
        let pct = Int((d * 100).rounded())
        if pct >= 0 { return "+\(pct)%" }
        return "\(pct)%"
    }
}

/// Pure-aggregation analytics. Every method runs against the SwiftData store
/// and returns deterministic outputs for testing. No networking; no Coach
/// prompts here. CoachService composes these summaries with live state.
@MainActor
final class TrendAnalyticsService {
    private let modelContext: ModelContext
    private let timezone: TimeZone
    private let hydrationTargets: HydrationTargetsOz?
    private let logger = Logger.coach

    init(modelContext: ModelContext,
         timezone: TimeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current,
         hydrationTargets: HydrationTargetsOz? = nil) {
        self.modelContext = modelContext
        self.timezone = timezone
        self.hydrationTargets = hydrationTargets
    }

    // MARK: - Public API

    /// Daily protocol-adherence ratio per day in `range`. Reads ActivityArchive
    /// rows when available; falls back to DailySummaryService for missing days.
    func dailyAdherence(over range: DateRange) -> [Date: Double] {
        let days = enumerateDays(in: range)
        let archives = archives(in: range)
        let archiveByDay = Dictionary(uniqueKeysWithValues: archives.map { ($0.date, $0.masterMetric) })
        let summaryService = DailySummaryService(
            modelContext: modelContext,
            timezone: timezone,
            hydrationTargets: hydrationTargets
        )
        var out: [Date: Double] = [:]
        for day in days {
            if let cached = archiveByDay[day] {
                out[day] = cached
                continue
            }
            let summary = summaryService.todayProtocol(asOf: day)
            out[day] = summary.scheduledCount > 0
                ? Double(summary.completedCount) / Double(summary.scheduledCount)
                : 0
        }
        return out
    }

    /// Daily volume (or domain-equivalent metric) by date. Lift uses lbs;
    /// basketball uses session count; swim uses meters; learning uses minutes;
    /// fasting uses hours; hydration uses oz.
    func volumeProgression(domain: TrainingDomain, over range: DateRange) -> [Date: Double] {
        let days = enumerateDays(in: range)
        var out: [Date: Double] = Dictionary(uniqueKeysWithValues: days.map { ($0, 0.0) })

        switch domain {
        case .lift:
            let lifts = (try? modelContext.fetch(FetchDescriptor<LiftSession>())) ?? []
            for s in lifts {
                let day = startOfDay(for: s.date)
                guard out[day] != nil else { continue }
                out[day]! += s.totalVolumeLbs
            }
        case .basketball:
            let sessions = (try? modelContext.fetch(FetchDescriptor<BasketballSession>())) ?? []
            for s in sessions {
                let day = startOfDay(for: s.date)
                guard out[day] != nil else { continue }
                out[day]! += 1
            }
        case .swim:
            let sessions = (try? modelContext.fetch(FetchDescriptor<SwimSession>())) ?? []
            for s in sessions {
                let day = startOfDay(for: s.date)
                guard out[day] != nil else { continue }
                out[day]! += s.totalMeters
            }
        case .learning:
            let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
            for log in logs {
                let day = startOfDay(for: log.date)
                guard out[day] != nil else { continue }
                out[day]! += Double(log.japaneseMinutes + log.guitarMinutes + log.courseworkMinutes)
            }
        case .fasting:
            let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
            for log in logs {
                let day = startOfDay(for: log.date)
                guard out[day] != nil else { continue }
                guard let start = log.fastStart, let end = log.fastEnd else { continue }
                out[day]! = max(0, end.timeIntervalSince(start) / 3600)
            }
        case .hydration:
            let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
            for log in logs {
                let day = startOfDay(for: log.date)
                guard out[day] != nil else { continue }
                out[day]! = log.waterOz
            }
        }
        return out
    }

    /// Runs all detection rules over `range` and returns the patterns above the
    /// minimum confidence threshold. Pure: does not write rows. Caller persists
    /// what it wants.
    func patternsDetected(over range: DateRange, minConfidence: Double = 0.5) -> [DetectedPattern] {
        var patterns: [DetectedPattern] = []
        if let p = detectScheduleDrift(over: range), p.confidence >= minConfidence { patterns.append(p) }
        if let p = detectVolumeDecline(over: range), p.confidence >= minConfidence { patterns.append(p) }
        if let p = detectHydrationCorrelation(over: range), p.confidence >= minConfidence { patterns.append(p) }
        if let p = detectSleepImpact(over: range), p.confidence >= minConfidence { patterns.append(p) }
        if let p = detectFastingConsistency(over: range), p.confidence >= minConfidence { patterns.append(p) }
        if let p = detectLearningStreakDecay(over: range), p.confidence >= minConfidence { patterns.append(p) }
        return patterns.sorted { $0.confidence > $1.confidence }
    }

    /// Compact historical summary fed into Coach v2 prompts. Stays terse.
    func summaryForCoach(over range: DateRange) -> CoachContextHistorical {
        let adherence = dailyAdherence(over: range)
        let mean = adherence.values.reduce(0, +) / Double(max(adherence.count, 1))
        let last7 = enumerateDays(in: DateRange.lastNDays(7, asOf: range.end, timezone: timezone))
            .compactMap { adherence[$0] }

        let workoutsByWeek = workoutsPerWeek(in: range)
        let workoutsValues = Array(workoutsByWeek.values)
        let workoutsSum = Double(workoutsValues.reduce(0, +))
        let workoutsMean = workoutsSum / Double(max(workoutsValues.count, 1))
        let workoutsTrend = trendBetweenHalves(workoutsValues)

        let liftWeekly = liftVolumeByWeek(in: range)
        let liftWoW: Double = {
            let sorted = liftWeekly.sorted(by: { $0.key < $1.key }).map { $0.value }
            guard sorted.count >= 2, sorted[sorted.count - 2] > 0 else { return 0 }
            return (sorted.last! - sorted[sorted.count - 2]) / sorted[sorted.count - 2]
        }()

        let hydrationMiss = hydrationMissRatio(in: range)
        let fastingRate = fastingCompletionRate(in: range)
        let learningWeekly = learningMinutesByWeek(in: range)
        let learningMean = learningWeekly.values.reduce(0, +) / Double(max(learningWeekly.count, 1))

        let patterns = patternsDetected(over: range)
        let headlines = Array(patterns.prefix(3)).map { $0.summary }

        return CoachContextHistorical(
            rangeDescription: rangeDescription(range),
            dailyAdherenceMean: mean,
            dailyAdherence7dRolling: last7,
            workoutsPerWeekMean: workoutsMean,
            workoutsPerWeekTrend: workoutsTrend,
            liftVolumeWeekOverWeek: liftWoW,
            hydrationMissRatio: hydrationMiss,
            fastingCompletionRate: fastingRate,
            learningMinutesPerWeekMean: learningMean,
            detectedPatternHeadlines: headlines
        )
    }

    // MARK: - Pattern detectors

    /// Schedule drift: > 50% of recent training-block dates land on a different
    /// weekday than the same block ran during the prior month.
    private func detectScheduleDrift(over range: DateRange) -> DetectedPattern? {
        let workoutEvents = (try? modelContext.fetch(FetchDescriptor<WorkoutEvent>())) ?? []
        let inRange = workoutEvents.filter { $0.completed && range.contains($0.date) }
        guard inRange.count >= 4 else { return nil }
        var weekdayCounts: [Int: Int] = [:]
        for ev in inRange {
            let wd = isoWeekday(for: ev.date)
            weekdayCounts[wd, default: 0] += 1
        }
        let total = inRange.count
        let topShare = (weekdayCounts.values.max() ?? 0)
        let entropy = computeEntropy(counts: Array(weekdayCounts.values), total: total)
        // High entropy = lots of weekdays, indicating drift. Threshold tuned.
        guard entropy > 1.6 else { return nil }
        let confidence = min(1.0, (entropy - 1.6) / 0.8)
        return DetectedPattern(
            detectedAt: range.end,
            patternType: .scheduleDrift,
            confidence: confidence,
            summary: "Workouts spread across many weekdays in last \(daysCount(in: range))d.",
            detail: "Top weekday share \(topShare)/\(total). Entropy \(String(format: "%.2f", entropy)). Schedule may need refit.",
            actionableSuggestion: "Reflect: are you happy with the current schedule, or would you rather pin training to fewer specific days?"
        )
    }

    /// Volume decline: lift volume in last 7 days is < 70% of prior 7 days mean.
    private func detectVolumeDecline(over range: DateRange) -> DetectedPattern? {
        let liftDaily = volumeProgression(domain: .lift, over: range)
        let sortedDays = liftDaily.keys.sorted()
        guard sortedDays.count >= 14 else { return nil }
        let last7 = sortedDays.suffix(7).map { liftDaily[$0] ?? 0 }
        let priorEnd = sortedDays.count - 7
        let priorStart = max(0, priorEnd - 7)
        let prior7 = sortedDays[priorStart..<priorEnd].map { liftDaily[$0] ?? 0 }
        let last7Mean = last7.reduce(0, +) / 7
        let prior7Mean = prior7.reduce(0, +) / Double(max(prior7.count, 1))
        guard prior7Mean > 100 else { return nil }
        let ratio = last7Mean / prior7Mean
        guard ratio < 0.7 else { return nil }
        let confidence = min(1.0, (0.7 - ratio) / 0.5)
        return DetectedPattern(
            detectedAt: range.end,
            patternType: .volumeDecline,
            confidence: confidence,
            summary: "Lift volume down \(Int((1 - ratio) * 100))% vs prior week.",
            detail: "Last 7d: \(Int(last7Mean)) lb/day. Prior 7d: \(Int(prior7Mean)) lb/day.",
            actionableSuggestion: "Take a deload-aware look at sleep and HRV. If both are intact, consider re-loading next session."
        )
    }

    /// Hydration vs adherence correlation: above-target hydration days have
    /// higher adherence than below-target days.
    private func detectHydrationCorrelation(over range: DateRange) -> DetectedPattern? {
        let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
        let adherence = dailyAdherence(over: range)
        var above: [Double] = []
        var below: [Double] = []
        for log in logs {
            let day = startOfDay(for: log.date)
            guard let adh = adherence[day] else { continue }
            let target = hydrationTargetMin(for: day)
            if log.waterOz >= target { above.append(adh) } else { below.append(adh) }
        }
        guard above.count >= 3 && below.count >= 3 else { return nil }
        let aboveMean = above.reduce(0, +) / Double(above.count)
        let belowMean = below.reduce(0, +) / Double(below.count)
        let delta = aboveMean - belowMean
        guard delta >= 0.15 else { return nil }
        let confidence = min(1.0, delta / 0.4)
        return DetectedPattern(
            detectedAt: range.end,
            patternType: .hydrationCorrelation,
            confidence: confidence,
            summary: "Adherence \(Int(delta * 100))% higher on hydrated days.",
            detail: "Hydrated days adherence \(Int(aboveMean * 100))% vs non-hydrated \(Int(belowMean * 100))%.",
            actionableSuggestion: "Front-load hydration in the morning to lock in the day's protocol."
        )
    }

    /// Sleep impact: low-sleep nights (< 6h) precede days with adherence < 0.5.
    private func detectSleepImpact(over range: DateRange) -> DetectedPattern? {
        let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
        let logsByDay = Dictionary(uniqueKeysWithValues: logs.map { (startOfDay(for: $0.date), $0) })
        let adherence = dailyAdherence(over: range)
        let sortedDays = adherence.keys.sorted()
        var lowSleepLowAdh = 0
        var lowSleepTotal = 0
        for day in sortedDays {
            let prior = calendar().date(byAdding: .day, value: -1, to: day) ?? day
            guard let priorLog = logsByDay[startOfDay(for: prior)],
                  let sleepHours = priorLog.sleepHours else { continue }
            if sleepHours < 6 {
                lowSleepTotal += 1
                if (adherence[day] ?? 0) < 0.5 { lowSleepLowAdh += 1 }
            }
        }
        guard lowSleepTotal >= 3 else { return nil }
        let ratio = Double(lowSleepLowAdh) / Double(lowSleepTotal)
        guard ratio >= 0.5 else { return nil }
        return DetectedPattern(
            detectedAt: range.end,
            patternType: .sleepImpact,
            confidence: min(1.0, (ratio - 0.5) * 2 + 0.5),
            summary: "Low-sleep nights precede missed days \(Int(ratio * 100))% of the time.",
            detail: "On \(lowSleepTotal) nights with <6h sleep, \(lowSleepLowAdh) days following hit adherence under 50%.",
            actionableSuggestion: "Treat sleep < 6h as a deload signal: scale workouts down rather than skip entirely."
        )
    }

    /// Fasting consistency: completion rate trending down over time.
    private func detectFastingConsistency(over range: DateRange) -> DetectedPattern? {
        let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
        let inRange = logs.filter { range.contains($0.date) }
        guard inRange.count >= 14 else { return nil }
        let sorted = inRange.sorted(by: { $0.date < $1.date })
        let mid = sorted.count / 2
        let firstHalf = sorted.prefix(mid)
        let secondHalf = sorted.suffix(mid)
        let firstRate = Double(firstHalf.filter { $0.fastEnd != nil }.count) / Double(max(firstHalf.count, 1))
        let secondRate = Double(secondHalf.filter { $0.fastEnd != nil }.count) / Double(max(secondHalf.count, 1))
        let delta = secondRate - firstRate
        guard abs(delta) >= 0.2 else { return nil }
        let direction = delta > 0 ? "rising" : "declining"
        return DetectedPattern(
            detectedAt: range.end,
            patternType: .fastingConsistency,
            confidence: min(1.0, abs(delta) * 2),
            summary: "Fasting completion \(direction) (\(Int(firstRate * 100))% → \(Int(secondRate * 100))%).",
            detail: "Across \(sorted.count) days. \(direction.capitalized).",
            actionableSuggestion: delta < 0
                ? "Re-anchor your fast end to a clear post-event trigger (after morning walk, after first meeting)."
                : "Lock in the rhythm. The trend is real."
        )
    }

    /// Learning streak decay: learning-minutes per week trending down.
    private func detectLearningStreakDecay(over range: DateRange) -> DetectedPattern? {
        let weekly = learningMinutesByWeek(in: range)
        guard weekly.count >= 3 else { return nil }
        let sorted = weekly.sorted(by: { $0.key < $1.key }).map { $0.value }
        let firstHalf = sorted.prefix(sorted.count / 2)
        let secondHalf = sorted.suffix(sorted.count / 2)
        let firstMean = firstHalf.reduce(0, +) / Double(max(firstHalf.count, 1))
        let secondMean = secondHalf.reduce(0, +) / Double(max(secondHalf.count, 1))
        guard firstMean > 30, (secondMean / firstMean) < 0.6 else { return nil }
        let drop = 1 - (secondMean / firstMean)
        return DetectedPattern(
            detectedAt: range.end,
            patternType: .learningStreakDecay,
            confidence: min(1.0, drop),
            summary: "Learning minutes down \(Int(drop * 100))% vs early window.",
            detail: "First half mean \(Int(firstMean)) min/wk. Second half mean \(Int(secondMean)) min/wk.",
            actionableSuggestion: "Stack a 10-min Japanese block onto an existing trigger. Identity, not goal."
        )
    }

    // MARK: - Aggregations

    private func workoutsPerWeek(in range: DateRange) -> [Date: Int] {
        let events = (try? modelContext.fetch(FetchDescriptor<WorkoutEvent>())) ?? []
        let inRange = events.filter { $0.completed && range.contains($0.date) }
        var byWeek: [Date: Int] = [:]
        for ev in inRange {
            let weekStart = mondayOfWeek(containing: ev.date)
            byWeek[weekStart, default: 0] += 1
        }
        return byWeek
    }

    private func liftVolumeByWeek(in range: DateRange) -> [Date: Double] {
        let lifts = (try? modelContext.fetch(FetchDescriptor<LiftSession>())) ?? []
        let inRange = lifts.filter { range.contains($0.date) }
        var byWeek: [Date: Double] = [:]
        for s in inRange {
            let weekStart = mondayOfWeek(containing: s.date)
            byWeek[weekStart, default: 0] += s.totalVolumeLbs
        }
        return byWeek
    }

    private func learningMinutesByWeek(in range: DateRange) -> [Date: Double] {
        let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
        let inRange = logs.filter { range.contains($0.date) }
        var byWeek: [Date: Double] = [:]
        for log in inRange {
            let weekStart = mondayOfWeek(containing: log.date)
            byWeek[weekStart, default: 0] += Double(log.japaneseMinutes + log.guitarMinutes + log.courseworkMinutes)
        }
        return byWeek
    }

    private func hydrationMissRatio(in range: DateRange) -> Double {
        let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
        let inRange = logs.filter { range.contains($0.date) }
        guard !inRange.isEmpty else { return 0 }
        let misses = inRange.filter { $0.waterOz < hydrationTargetMin(for: $0.date) }.count
        return Double(misses) / Double(inRange.count)
    }

    private func fastingCompletionRate(in range: DateRange) -> Double {
        let logs = (try? modelContext.fetch(FetchDescriptor<DailyLog>())) ?? []
        let inRange = logs.filter { range.contains($0.date) }
        guard !inRange.isEmpty else { return 0 }
        let done = inRange.filter { $0.fastEnd != nil }.count
        return Double(done) / Double(inRange.count)
    }

    // MARK: - Helpers

    private func archives(in range: DateRange) -> [ActivityArchive] {
        let descriptor = FetchDescriptor<ActivityArchive>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).filter { range.contains($0.date) }
    }

    private func enumerateDays(in range: DateRange) -> [Date] {
        let cal = calendar()
        var days: [Date] = []
        var cursor = startOfDay(for: range.start)
        let stop = startOfDay(for: range.end)
        while cursor <= stop {
            days.append(cursor)
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    private func mondayOfWeek(containing date: Date) -> Date {
        let cal = calendar()
        let weekday = isoWeekday(for: date)
        let delta = -(weekday - 1)
        let day = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: delta, to: day) ?? day
    }

    private func isoWeekday(for date: Date) -> Int {
        let raw = calendar().component(.weekday, from: date)
        return raw == 1 ? 7 : raw - 1
    }

    private func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        return cal
    }

    private func startOfDay(for date: Date) -> Date {
        calendar().startOfDay(for: date)
    }

    private func hydrationTargetMin(for day: Date) -> Double {
        guard let targets = hydrationTargets else { return 64 }
        let weekday = isoWeekday(for: day)
        if targets.basketball.appliesTo.contains(weekday) { return targets.basketball.min }
        if targets.swim.appliesTo.contains(weekday) { return targets.swim.min }
        if targets.lift.appliesTo.contains(weekday) { return targets.lift.min }
        return targets.rest.min
    }

    private func computeEntropy(counts: [Int], total: Int) -> Double {
        guard total > 0 else { return 0 }
        var h = 0.0
        for c in counts {
            guard c > 0 else { continue }
            let p = Double(c) / Double(total)
            h -= p * log2(p)
        }
        return h
    }

    private func trendBetweenHalves(_ values: [Int]) -> Double {
        guard values.count >= 2 else { return 0 }
        let sorted = values
        let mid = sorted.count / 2
        let first = sorted.prefix(mid)
        let second = sorted.suffix(mid)
        let firstMean = Double(first.reduce(0, +)) / Double(max(first.count, 1))
        let secondMean = Double(second.reduce(0, +)) / Double(max(second.count, 1))
        guard firstMean > 0 else { return 0 }
        return (secondMean - firstMean) / firstMean
    }

    private func daysCount(in range: DateRange) -> Int {
        return enumerateDays(in: range).count
    }

    private func rangeDescription(_ range: DateRange) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timezone
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: range.start)) – \(formatter.string(from: range.end))"
    }
}

extension DateRange {
    func contains(_ date: Date) -> Bool {
        date >= start && date <= end.addingTimeInterval(86399)
    }
}

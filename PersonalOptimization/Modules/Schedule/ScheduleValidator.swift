import Foundation

/// Pure-Swift validation for AI-generated schedule drafts. No I/O, no SwiftData,
/// no async. Runs twice in the M4.1 generation pipeline: gating the API
/// response (retry loop with feedback) and gating the user's manual edits in
/// the diff view (warning banner, not block).
///
/// All inputs are value types. Errors are typed and carry block indices so
/// callers can highlight the offender in the UI or quote it back to Claude.
enum ScheduleValidator {

    // MARK: - Errors

    enum ValidationError: LocalizedError, Equatable {
        case overlap(blockA: Int, blockB: Int, day: Int)
        case sleepWindowIntersect(blockIndex: Int, day: Int)
        case weeklyVolumeExceeded(domain: String, count: Int, max: Int)
        case invalidModule(blockIndex: Int, value: String)
        case invalidAnchor(blockIndex: Int, value: String)
        case invalidWeekday(blockIndex: Int, value: Int)
        case invalidTimeFormat(blockIndex: Int, field: String, value: String)
        case timeRangeInverted(blockIndex: Int, start: String, end: String)

        var errorDescription: String? {
            switch self {
            case .overlap(let a, let b, let day):
                return "Blocks \(a) and \(b) overlap on day \(day)."
            case .sleepWindowIntersect(let i, let day):
                return "Block \(i) on day \(day) crosses the sleep window."
            case .weeklyVolumeExceeded(let domain, let count, let max):
                return "Weekly \(domain) volume \(count) exceeds limit \(max)."
            case .invalidModule(let i, let value):
                return "Block \(i) has invalid module '\(value)'."
            case .invalidAnchor(let i, let value):
                return "Block \(i) has unknown anchor event '\(value)'."
            case .invalidWeekday(let i, let value):
                return "Block \(i) has invalid ISO weekday \(value) (must be 1-7)."
            case .invalidTimeFormat(let i, let field, let value):
                return "Block \(i).\(field) = '\(value)' is not HH:mm."
            case .timeRangeInverted(let i, let start, let end):
                return "Block \(i) has endTime \(end) before startTime \(start)."
            }
        }
    }

    // MARK: - Constraints input

    struct Constraints {
        let sleepWindowStartHour: Int    // 22 default
        let sleepWindowEndHour: Int      // 6 default; if end < start, window wraps midnight
        let weeklyLiftMax: Int           // 6 default
        let knownModules: Set<String>    // explicit allowlist; null module is always valid
        let knownAnchors: Set<String>    // explicit allowlist; null anchor is always valid

        static let `default` = Constraints(
            sleepWindowStartHour: 22,
            sleepWindowEndHour: 6,
            weeklyLiftMax: 6,
            knownModules: ["lift_a", "lift_b", "basketball", "swim", "japanese", "guitar"],
            knownAnchors: ["after_kid_dropoff", "after_coffee", "after_work", "after_dinner", "before_bed"]
        )
    }

    // MARK: - Input block shape

    /// Minimal block shape the validator operates on. Identical-by-shape with
    /// `ScheduleBlockDraft` (T6) and any other DTO we want to validate before
    /// it touches SwiftData.
    struct Block: Equatable {
        let dayOfWeek: Int
        let startTime: String
        let endTime: String
        let type: String
        let module: String?
        let anchorEvent: String?
    }

    // MARK: - Public surface

    /// Validates all rules. Throws the first error encountered for callers that
    /// only need a boolean accept/reject. Use `collect(_:against:)` to gather
    /// every error in one pass (for the retry prompt and the diff-view warnings).
    static func validate(_ blocks: [Block], against constraints: Constraints) throws {
        let errors = collect(blocks, against: constraints)
        if let first = errors.first { throw first }
    }

    /// Returns every error found. Order: per-block syntactic errors (weekday,
    /// time format, range, module, anchor) first, then cross-block (overlap,
    /// sleep, weekly volume).
    static func collect(_ blocks: [Block], against constraints: Constraints) -> [ValidationError] {
        var errors: [ValidationError] = []

        for (i, block) in blocks.enumerated() {
            if !(1...7).contains(block.dayOfWeek) {
                errors.append(.invalidWeekday(blockIndex: i, value: block.dayOfWeek))
            }
            if parseMinutes(block.startTime) == nil {
                errors.append(.invalidTimeFormat(blockIndex: i, field: "startTime", value: block.startTime))
            }
            if parseMinutes(block.endTime) == nil {
                errors.append(.invalidTimeFormat(blockIndex: i, field: "endTime", value: block.endTime))
            }
            if let s = parseMinutes(block.startTime), let e = parseMinutes(block.endTime), e <= s {
                errors.append(.timeRangeInverted(blockIndex: i, start: block.startTime, end: block.endTime))
            }
            if let module = block.module, !module.isEmpty, !constraints.knownModules.contains(module) {
                errors.append(.invalidModule(blockIndex: i, value: module))
            }
            if let anchor = block.anchorEvent, !anchor.isEmpty, !constraints.knownAnchors.contains(anchor) {
                errors.append(.invalidAnchor(blockIndex: i, value: anchor))
            }
            if let s = parseMinutes(block.startTime), let e = parseMinutes(block.endTime), e > s,
               intersectsSleep(startMin: s, endMin: e, constraints: constraints) {
                errors.append(.sleepWindowIntersect(blockIndex: i, day: block.dayOfWeek))
            }
        }

        // Cross-block: same-day overlap. Index-quadratic with skip on syntactic-bad blocks.
        let perDay = Dictionary(grouping: blocks.enumerated().filter { _, b in
            (1...7).contains(b.dayOfWeek)
                && parseMinutes(b.startTime) != nil
                && parseMinutes(b.endTime) != nil
        }, by: { $0.element.dayOfWeek })

        for (day, indexed) in perDay {
            let sorted = indexed.sorted { left, right in
                (parseMinutes(left.element.startTime) ?? 0) < (parseMinutes(right.element.startTime) ?? 0)
            }
            for i in 0..<sorted.count {
                guard let aEnd = parseMinutes(sorted[i].element.endTime) else { continue }
                for j in (i + 1)..<sorted.count {
                    guard let bStart = parseMinutes(sorted[j].element.startTime) else { continue }
                    if bStart < aEnd {
                        errors.append(.overlap(blockA: sorted[i].offset, blockB: sorted[j].offset, day: day))
                    } else {
                        break
                    }
                }
            }
        }

        // Weekly volume: lift_a + lift_b.
        let liftCount = blocks.filter { $0.module == "lift_a" || $0.module == "lift_b" }.count
        if liftCount > constraints.weeklyLiftMax {
            errors.append(.weeklyVolumeExceeded(domain: "lift", count: liftCount, max: constraints.weeklyLiftMax))
        }

        return errors
    }

    /// Renders an error list into the multi-line feedback string used by the
    /// retry prompt: human-readable, one error per line.
    static func summarize(_ errors: [ValidationError]) -> String {
        guard !errors.isEmpty else { return "No validation errors." }
        return "The previous response had these problems:\n"
            + errors.map { "- " + ($0.errorDescription ?? String(describing: $0)) }.joined(separator: "\n")
            + "\nReturn a corrected schedule. Keep all valid blocks unchanged."
    }

    // MARK: - Helpers

    /// "HH:mm" 24-hour → minutes-from-midnight. Returns nil on malformed input.
    static func parseMinutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]),
              (0...23).contains(h),
              (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    /// Sleep window can wrap midnight (start=22:00, end=06:00 → window is
    /// 22:00-24:00 ∪ 00:00-06:00). Returns true when [startMin, endMin)
    /// intersects either piece.
    private static func intersectsSleep(startMin: Int, endMin: Int, constraints: Constraints) -> Bool {
        let s = constraints.sleepWindowStartHour * 60
        let e = constraints.sleepWindowEndHour * 60
        if s == e { return false }

        if s < e {
            // Non-wrapping window, e.g., 22:00-23:00.
            return overlaps(aStart: startMin, aEnd: endMin, bStart: s, bEnd: e)
        }
        // Wrapping: union of [s, 1440) and [0, e).
        return overlaps(aStart: startMin, aEnd: endMin, bStart: s, bEnd: 1440)
            || overlaps(aStart: startMin, aEnd: endMin, bStart: 0, bEnd: e)
    }

    private static func overlaps(aStart: Int, aEnd: Int, bStart: Int, bEnd: Int) -> Bool {
        return aStart < bEnd && bStart < aEnd
    }
}

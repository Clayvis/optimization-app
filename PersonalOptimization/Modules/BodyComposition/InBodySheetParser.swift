import CoreGraphics
import Foundation

/// One run of text read from a photo of an InBody result sheet. Geometry is
/// in image pixels with the origin at the top left, so distances and angles
/// are true to the page even when the photo is tilted.
struct RecognizedTextLine: Equatable, Sendable {
    var text: String
    var center: CGPoint
    var width: CGFloat
    var height: CGFloat
    /// Baseline angle in radians; 0 is level, negative rises to the right.
    var angle: CGFloat

    init(text: String, center: CGPoint, width: CGFloat, height: CGFloat, angle: CGFloat = 0) {
        self.text = text
        self.center = center
        self.width = width
        self.height = height
        self.angle = angle
    }

    /// Box given by its top-left corner, as a page is read. For fixtures.
    init(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 20) {
        self.init(text: text, center: CGPoint(x: x + width / 2, y: y + height / 2), width: width, height: height)
    }
}

/// Scan values the photo reader can fill.
enum InBodyField: String, CaseIterable, Sendable {
    case date, height, weight, skeletalMuscle, leanBodyMass, bodyFatMass, bodyFatPercent
    case totalBodyWater, ecwTbwRatio, visceralFatArea, basalMetabolicRate
    case rightArm, leftArm, trunk, rightLeg, leftLeg
}

/// What a photo produced: values to prefill and which of them were read.
/// Nothing here is saved; the editor shows it for the user to check.
struct InBodyPhotoReading: Identifiable, Equatable, Sendable {
    var id = UUID()
    var values: InBodyValues
    var read: Set<InBodyField>
    /// The sheet printed kilograms; masses were converted to pounds.
    var convertedFromKilograms: Bool
    /// Fields read differently between passes, or that break the sheet's own
    /// arithmetic, with the values seen. The editor asks for a closer look.
    var uncertain: [InBodyField: [Double]] = [:]

    /// Later pages fill only what earlier pages lacked.
    func merged(with other: InBodyPhotoReading) -> InBodyPhotoReading {
        var result = self
        for field in other.read.subtracting(read) {
            InBodySheetParser.copy(field, from: other.values, to: &result.values)
            result.read.insert(field)
            result.uncertain[field] = other.uncertain[field]
        }
        result.convertedFromKilograms = convertedFromKilograms || other.convertedFromKilograms
        return result
    }
}

/// Maps the text of an InBody result sheet (270, 570 and 770 layouts, English
/// or Japanese, pounds or kilograms) to scan values. Pure and deterministic.
///
/// Printed values sit beside their label, under a column header (height,
/// test date, the body-composition table), or inside a chart (visceral fat
/// area). Rows are compared along the page's own text angle. Graph scales,
/// normal ranges in parentheses, the segmental-fat, control and history
/// sections, and implausible numbers are ignored; a field that cannot be read
/// stays blank rather than guessed.
enum InBodySheetParser {
    static let poundsPerKilogram = 2.204_622_62

    static func parse(_ recognized: [RecognizedTextLine], now: Date = Date(), calendar: Calendar = .current) -> InBodyPhotoReading {
        var values = InBodyValues()
        values.date = now
        let page = Page(recognized)
        let unit = page.massUnit
        var read = Set<InBodyField>()
        for spec in FieldSpec.all {
            guard let value = page.value(for: spec, unit: unit) else { continue }
            set(spec.field, value, on: &values)
            read.insert(spec.field)
        }
        if let date = page.testDate(calendar: calendar, now: now) {
            values.date = date
            read.insert(.date)
        }
        if let height = page.heightInches() {
            values.heightInches = height
            read.insert(.height)
        }
        return InBodyPhotoReading(values: values, read: read, convertedFromKilograms: unit == .kilograms && !read.isEmpty)
    }

    // MARK: - Field table

    enum MassUnit: Sendable { case pounds, kilograms }

    fileprivate enum Kind { case mass, percent, ratio, area, energy }
    fileprivate enum Below { case column, chart }
    fileprivate enum Section { case lean, excluded, other }

    fileprivate struct FieldSpec {
        let field: InBodyField
        /// Regular expressions on the lowercased line; a match marks a label.
        let labels: [String]
        /// Substrings that disqualify a line as this label.
        let excludes: [String]
        let kind: Kind
        /// Plausible range in the stored unit (lb, %, ratio, cm², kcal).
        let range: ClosedRange<Double>
        /// Where a value printed under the label can be: centered under a
        /// column header, or anywhere in a chart under it (decimal numbers
        /// only, so axis ticks never count).
        var below: Below?
        /// Printed with a decimal point, unlike graph scale ticks.
        var decimal = true
        /// Read only inside a segmental lean section.
        var segment = false

        static let all: [FieldSpec] = [
            FieldSpec(field: .weight, labels: [#"^weight\b"#, "^体重"],
                      excludes: ["control", "target", "ideal", "standard", "目標", "標準", "適正", "コントロール"],
                      kind: .mass, range: 50...700, below: .column),
            FieldSpec(field: .skeletalMuscle, labels: [#"^smm\b"#, "skeletal muscle mass", "骨格筋量"],
                      excludes: ["index", "smi"], kind: .mass, range: 15...250),
            FieldSpec(field: .leanBodyMass, labels: ["lean body mass", #"^lbm\b"#, "fat free mass", #"^ffm\b"#, "除脂肪量"],
                      excludes: ["control", "segmental", "index", "ffmi", "leg lean", "コントロール", "部位別"],
                      kind: .mass, range: 40...450, below: .column),
            FieldSpec(field: .bodyFatMass, labels: ["body fat mass", #"^bfm\b"#, "体脂肪量"],
                      excludes: ["control", "segmental", "コントロール", "部位別"], kind: .mass, range: 1...400),
            FieldSpec(field: .bodyFatPercent, labels: [#"^pbf\b"#, "percent body fat", "body fat percentage", "体脂肪率"],
                      excludes: ["segmental", "部位別"], kind: .percent, range: 2...75),
            FieldSpec(field: .totalBodyWater, labels: ["total body water", #"^tbw\b"#, "体水分量"],
                      excludes: ["ecw", "/lbm", "tbw/", "/ffm"], kind: .mass, range: 20...300, below: .column),
            FieldSpec(field: .ecwTbwRatio, labels: [#"ecw\s*/\s*tbw"#, "ecw ratio", "細胞外水分比"],
                      excludes: ["analysis", "分析"], kind: .ratio, range: 0.30...0.45),
            FieldSpec(field: .visceralFatArea, labels: ["visceral fat area", #"^vfa\b"#, "内臓脂肪面積"],
                      excludes: ["level", "レベル"], kind: .area, range: 5...400, below: .chart),
            FieldSpec(field: .basalMetabolicRate, labels: ["basal metabolic rate", #"^bmr\b"#, "基礎代謝量"],
                      excludes: [], kind: .energy, range: 700...4500, decimal: false),
            FieldSpec(field: .rightArm, labels: [#"^right arm\b"#, "^右腕"], excludes: [], kind: .mass, range: 1.5...40, segment: true),
            FieldSpec(field: .leftArm, labels: [#"^left arm\b"#, "^左腕"], excludes: [], kind: .mass, range: 1.5...40, segment: true),
            FieldSpec(field: .trunk, labels: [#"^trunk\b"#, "^体幹"], excludes: [], kind: .mass, range: 15...160, segment: true),
            FieldSpec(field: .rightLeg, labels: [#"^right leg\b"#, "^右脚", "^右足"], excludes: [], kind: .mass, range: 5...90, segment: true),
            FieldSpec(field: .leftLeg, labels: [#"^left leg\b"#, "^左脚", "^左足"], excludes: [], kind: .mass, range: 5...90, segment: true),
        ]
    }

    fileprivate static let leanHeaders = ["segmental lean", "segmental muscle", "部位別筋肉量"]
    fileprivate static let excludedHeaders = ["segmental fat", "部位別体脂肪", "部位別脂肪", "control", "コントロール",
                                              "history", "履歴", "impedance", "インピーダンス", "reactance",
                                              "phase angle", "位相角"]
    fileprivate static let otherHeaders = ["body composition analysis", "体成分分析", "muscle-fat analysis",
                                           "muscle fat analysis", "筋肉・脂肪", "obesity analysis", "肥満",
                                           "ecw/tbw analysis", "research parameters", "研究項目"]

    // MARK: - Values

    static func set(_ field: InBodyField, _ value: Double, on values: inout InBodyValues) {
        switch field {
        case .date: break
        case .height: values.heightInches = value
        case .weight: values.weightLb = value
        case .skeletalMuscle: values.skeletalMuscleMassLb = value
        case .leanBodyMass: values.leanBodyMassLb = value
        case .bodyFatMass: values.bodyFatMassLb = value
        case .bodyFatPercent: values.bodyFatPercent = value
        case .totalBodyWater: values.totalBodyWaterLb = value
        case .ecwTbwRatio: values.ecwTbwRatio = value
        case .visceralFatArea: values.visceralFatAreaCm2 = value
        case .basalMetabolicRate: values.basalMetabolicRateKcal = value
        case .rightArm: values.rightArmLb = value
        case .leftArm: values.leftArmLb = value
        case .trunk: values.trunkLb = value
        case .rightLeg: values.rightLegLb = value
        case .leftLeg: values.leftLegLb = value
        }
    }

    /// A numeric field's value; nil for the date.
    static func value(of field: InBodyField, in values: InBodyValues) -> Double? {
        switch field {
        case .date: return nil
        case .height: return values.heightInches
        case .weight: return values.weightLb
        case .skeletalMuscle: return values.skeletalMuscleMassLb
        case .leanBodyMass: return values.leanBodyMassLb
        case .bodyFatMass: return values.bodyFatMassLb
        case .bodyFatPercent: return values.bodyFatPercent
        case .totalBodyWater: return values.totalBodyWaterLb
        case .ecwTbwRatio: return values.ecwTbwRatio
        case .visceralFatArea: return values.visceralFatAreaCm2
        case .basalMetabolicRate: return values.basalMetabolicRateKcal
        case .rightArm: return values.rightArmLb
        case .leftArm: return values.leftArmLb
        case .trunk: return values.trunkLb
        case .rightLeg: return values.rightLegLb
        case .leftLeg: return values.leftLegLb
        }
    }

    // MARK: - Combining reads

    /// Combines reads of one photo at different sizes. Recognition of printed
    /// digits varies with scale (a "4" at one size reads as a "1" at another), so
    /// each field keeps the value most passes agree on, ties going to the
    /// earlier (sharper) pass, and any disagreement is flagged for review.
    static func consensus(_ passes: [InBodyPhotoReading]) -> InBodyPhotoReading? {
        guard var result = passes.first else { return nil }
        result.read = []
        result.uncertain = [:]
        for field in InBodyField.allCases {
            let readers = passes.filter { $0.read.contains(field) }
            guard let first = readers.first else { continue }
            result.read.insert(field)
            if field == .date {
                result.values.date = first.values.date
                continue
            }
            var seen: [Double] = []
            var counts: [Double: Int] = [:]
            for reader in readers {
                guard let value = value(of: field, in: reader.values) else { continue }
                if counts[value] == nil { seen.append(value) }
                counts[value, default: 0] += 1
            }
            guard var chosen = seen.first else { continue }
            for value in seen where (counts[value] ?? 0) > (counts[chosen] ?? 0) { chosen = value }
            set(field, chosen, on: &result.values)
            if seen.count > 1 { result.uncertain[field] = seen }
        }
        result.convertedFromKilograms = passes.contains { $0.convertedFromKilograms }
        checkArithmetic(&result)
        return result
    }

    /// InBody prints weight = lean body mass + body-fat mass, and percent body
    /// fat = fat mass / weight. Split reads that fit the sum are settled; values
    /// that still don't add up are flagged. Nothing is derived to fill a blank.
    static func checkArithmetic(_ reading: inout InBodyPhotoReading) {
        let tolerance = 0.25
        guard reading.read.isSuperset(of: [.weight, .leanBodyMass, .bodyFatMass]) else { return }
        func settle(_ field: InBodyField, expected: Double) {
            guard let options = reading.uncertain[field],
                  let match = options.first(where: { abs($0 - expected) <= tolerance }) else { return }
            set(field, match, on: &reading.values)
            reading.uncertain[field] = nil
        }
        settle(.leanBodyMass, expected: reading.values.weightLb - reading.values.bodyFatMassLb)
        settle(.bodyFatMass, expected: reading.values.weightLb - reading.values.leanBodyMassLb)
        settle(.weight, expected: reading.values.leanBodyMassLb + reading.values.bodyFatMassLb)
        let values = reading.values
        if abs(values.weightLb - values.leanBodyMassLb - values.bodyFatMassLb) > tolerance {
            for field in [InBodyField.weight, .leanBodyMass, .bodyFatMass] where reading.uncertain[field] == nil {
                reading.uncertain[field] = value(of: field, in: values).map { [$0] }
            }
        }
        guard reading.read.contains(.bodyFatPercent), values.weightLb > 0 else { return }
        let percent = values.bodyFatMassLb / values.weightLb * 100
        settle(.bodyFatPercent, expected: percent)
        if abs(reading.values.bodyFatPercent - percent) > tolerance, reading.uncertain[.bodyFatPercent] == nil {
            reading.uncertain[.bodyFatPercent] = [reading.values.bodyFatPercent]
        }
    }

    static func copy(_ field: InBodyField, from source: InBodyValues, to target: inout InBodyValues) {
        switch field {
        case .date: target.date = source.date
        case .height: target.heightInches = source.heightInches
        case .weight: target.weightLb = source.weightLb
        case .skeletalMuscle: target.skeletalMuscleMassLb = source.skeletalMuscleMassLb
        case .leanBodyMass: target.leanBodyMassLb = source.leanBodyMassLb
        case .bodyFatMass: target.bodyFatMassLb = source.bodyFatMassLb
        case .bodyFatPercent: target.bodyFatPercent = source.bodyFatPercent
        case .totalBodyWater: target.totalBodyWaterLb = source.totalBodyWaterLb
        case .ecwTbwRatio: target.ecwTbwRatio = source.ecwTbwRatio
        case .visceralFatArea: target.visceralFatAreaCm2 = source.visceralFatAreaCm2
        case .basalMetabolicRate: target.basalMetabolicRateKcal = source.basalMetabolicRateKcal
        case .rightArm: target.rightArmLb = source.rightArmLb
        case .leftArm: target.leftArmLb = source.leftArmLb
        case .trunk: target.trunkLb = source.trunkLb
        case .rightLeg: target.rightLegLb = source.rightLegLb
        case .leftLeg: target.leftLegLb = source.leftLegLb
        }
    }

    // MARK: - Text

    /// Half-width characters, "201. 3" as "201.3" (InBody printers space the
    /// decimals), a letter O read inside a number as zero ("10. Oin"), and one
    /// wave dash for ranges.
    static func normalize(_ raw: String) -> String {
        var text = raw.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? raw
        text = text.replacingOccurrences(of: "〜", with: "~")
        text = text.replacingOccurrences(of: #"(\d)\s*\.\s*[oO](?![a-hj-z])"#, with: "$1.0", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?<=\d)[oO](?=\d)"#, with: "0", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(\d)\s*\.\s+(\d)"#, with: "$1.$2", options: .regularExpression)
        return text
    }

    struct NumberToken: Equatable {
        var value: Double
        var hasDecimal: Bool
        var unit: MassUnit?
    }

    /// Positive numbers outside parentheses and ranges, with any mass unit
    /// printed right after them. "1,905" reads as 1905.
    static func numbers(in text: String) -> [NumberToken] {
        var cleaned = text.replacingOccurrences(of: #"\([^()]*\d[^()]*\)"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\d+(?:\.\d+)?\s*[~～]\s*\d+(?:\.\d+)?"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\d+(?:\.\d+)?\s*[-–]\s*\d+(?:\.\d+)?"#, with: " ", options: .regularExpression)
        guard let pattern = try? NSRegularExpression(  // MARK: try? justified - constant pattern, validated by tests.
            pattern: #"([-−]?)(?<![\d.,])(\d{1,3}(?:,\d{3})+|\d+)(\.\d+)?(?![\d])\s*(lbs?|kg)?\b"#,
            options: [.caseInsensitive]) else { return [] }
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        return pattern.matches(in: cleaned, range: range).compactMap { match in
            func group(_ index: Int) -> String? {
                Range(match.range(at: index), in: cleaned).map { String(cleaned[$0]) }
            }
            guard group(1)?.isEmpty ?? true, let whole = group(2) else { return nil }
            let fraction = group(3) ?? ""
            guard let value = Double(whole.replacingOccurrences(of: ",", with: "") + fraction) else { return nil }
            let unit = group(4).map { $0.lowercased() == "kg" ? MassUnit.kilograms : MassUnit.pounds }
            return NumberToken(value: value, hasDecimal: !fraction.isEmpty, unit: unit)
        }
    }

    /// Date and time printed on the sheet: "11.02.2026 07:45", "2026.11.02",
    /// "2026/11/02", "2026年11月2日". Four-digit years only.
    static func parseDate(_ text: String, calendar: Calendar) -> Date? {
        let text = normalize(text)
        var year = 0, month = 0, day = 0
        if let m = captures(#"(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日"#, in: text)
            ?? captures(#"(\d{4})[./-](\d{1,2})[./-](\d{1,2})"#, in: text) {
            (year, month, day) = (m[0], m[1], m[2])
        } else if let m = captures(#"(?<!\d)(\d{1,2})[./-](\d{1,2})[./-](\d{4})"#, in: text) {
            // US order unless the first number cannot be a month.
            (year, month, day) = m[0] > 12 ? (m[2], m[1], m[0]) : (m[2], m[0], m[1])
        } else {
            return nil
        }
        var components = DateComponents(year: year, month: month, day: day)
        if let time = captures(#"(?<!\d)(\d{1,2}):(\d{2})(?!\d)"#, in: text), time[0] < 24, time[1] < 60 {
            components.hour = time[0]
            components.minute = time[1]
        } else {
            components.hour = 12
        }
        guard (2000...2100).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }

    /// Height in inches from "5ft 11.0in", "5 ft. 10 in.", "5'10\"" or "178.0cm".
    static func parseHeightInches(_ text: String) -> Double? {
        let text = normalize(text).lowercased()
        var inches: Double?
        if let m = decimalCaptures(#"(\d)\s*(?:ft|feet|')\.?\s*(\d{1,2}(?:\.\d+)?)\s*(?:in|inch|"|”)"#, in: text) {
            inches = m[0] * 12 + m[1]
        } else if let m = decimalCaptures(#"(\d{2,3}(?:\.\d+)?)\s*cm\b"#, in: text) {
            inches = (m[0] / 2.54 * 10).rounded() / 10
        }
        guard let inches, (40...100).contains(inches) else { return nil }
        return inches
    }

    private static func captures(_ pattern: String, in text: String) -> [Int]? {
        decimalCaptures(pattern, in: text)?.map { Int($0) }
    }

    private static func decimalCaptures(_ pattern: String, in text: String) -> [Double]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),  // MARK: try? justified - constant patterns, validated by tests.
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        var values: [Double] = []
        for index in 1..<match.numberOfRanges {
            guard let range = Range(match.range(at: index), in: text), let value = Double(text[range]) else { return nil }
            values.append(value)
        }
        return values
    }

    // MARK: - Page geometry

    /// Lines in the page's own frame: `u` runs along the rows, `v` down the page.
    fileprivate struct Line {
        let text: String
        let lower: String
        let u: CGFloat
        let v: CGFloat
        let width: CGFloat
        let height: CGFloat
        let numbers: [NumberToken]
        var uMin: CGFloat { u - width / 2 }
        var uMax: CGFloat { u + width / 2 }
    }

    fileprivate struct Candidate {
        let value: Double
        let rank: Int          // 0 beside the label, 1 under it
        let penalty: Int       // 1 when a decimal was expected and this has none
        let distance: CGFloat  // in label heights
    }

    fileprivate struct Page {
        let lines: [Line]
        let sections: [Section?]
        /// Column of each line: index of the nearest section-header left edge
        /// at or before it. Sheets print two columns of sections.
        let columns: [Int]
        let pageWidth: CGFloat
        let hasLeanSection: Bool

        init(_ recognized: [RecognizedTextLine]) {
            // The median angle of the longer lines is the page's tilt.
            let angles = recognized.filter { $0.width >= 2.5 * $0.height }.map(\.angle).sorted()
            let tilt = angles.isEmpty ? 0 : angles[angles.count / 2]
            let (c, s) = (cos(tilt), sin(tilt))
            let placed = recognized.map { line in
                Page.line(InBodySheetParser.normalize(line.text),
                          u: line.center.x * c + line.center.y * s, v: -line.center.x * s + line.center.y * c,
                          width: line.width, height: max(line.height, 1))
            }
            lines = Page.joiningSplitDecimals(placed)
            let minU = lines.map(\.uMin).min() ?? 0
            let maxU = lines.map(\.uMax).max() ?? 1
            pageWidth = max(maxU - minU, 1)
            let kinds: [Section?] = lines.map { line in
                if InBodySheetParser.leanHeaders.contains(where: { line.lower.contains($0) }) { return .lean }
                if InBodySheetParser.excludedHeaders.contains(where: { line.lower.contains($0) }) { return .excluded }
                if InBodySheetParser.otherHeaders.contains(where: { line.lower.contains($0) }) { return .other }
                return nil
            }
            hasLeanSection = kinds.contains(.lean)
            // Column edges: header left edges, merged when within 5% of the page.
            let allLines = lines
            let margin = 0.05 * pageWidth
            var edges: [CGFloat] = []
            for edge in allLines.indices.filter({ kinds[$0] != nil }).map({ allLines[$0].uMin }).sorted() {
                if let last = edges.last, edge - last < margin { continue }
                edges.append(edge)
            }
            let columnEdges = edges
            let lineColumns = allLines.map { line in
                columnEdges.lastIndex { $0 <= line.uMin + margin } ?? 0
            }
            columns = lineColumns
            // Each line belongs to the nearest header above it in its column.
            sections = allLines.indices.map { index in
                if let own = kinds[index] { return own }
                let line = allLines[index]
                var best: (gap: CGFloat, kind: Section)?
                for (headerIndex, kind) in kinds.enumerated() {
                    guard let kind, lineColumns[headerIndex] == lineColumns[index] else { continue }
                    let gap = line.v - allLines[headerIndex].v
                    guard gap > 0.3 * line.height else { continue }
                    if best.map({ gap < $0.gap }) ?? true { best = (gap, kind) }
                }
                return best?.kind
            }
        }

        private static func line(_ text: String, u: CGFloat, v: CGFloat, width: CGFloat, height: CGFloat) -> Line {
            Line(text: text, lower: text.lowercased(), u: u, v: v, width: width, height: height,
                 numbers: InBodySheetParser.numbers(in: text))
        }

        /// The printer's wide gap after a decimal point can split "22. 84" into
        /// "22." and "84"; rejoin them when they sit side by side on a row.
        private static func joiningSplitDecimals(_ input: [Line]) -> [Line] {
            var lines = input
            var index = 0
            while index < lines.count {
                let left = lines[index]
                if left.text.trimmingCharacters(in: .whitespaces).range(of: #"\d\.$"#, options: .regularExpression) != nil,
                   let partner = lines.indices.first(where: { other in
                       let right = lines[other]
                       let gap = right.uMin - left.uMax
                       return other != index
                           && right.text.trimmingCharacters(in: .whitespaces).range(of: #"^\d+"#, options: .regularExpression) != nil
                           && abs(right.v - left.v) < 0.6 * max(left.height, right.height)
                           && gap > -0.5 * left.height && gap < 2.5 * left.height
                   }) {
                    let right = lines[partner]
                    let (uMin, uMax) = (left.uMin, max(left.uMax, right.uMax))
                    lines[index] = line(left.text.trimmingCharacters(in: .whitespaces) + right.text.trimmingCharacters(in: .whitespaces),
                                        u: (uMin + uMax) / 2, v: (left.v + right.v) / 2,
                                        width: uMax - uMin, height: max(left.height, right.height))
                    lines.remove(at: partner)
                    if partner < index { index -= 1 }
                    continue
                }
                index += 1
            }
            return lines
        }

        /// Pounds unless kilograms dominate ("kg/m²" is the BMI unit, not mass).
        var massUnit: MassUnit {
            let text = lines.map(\.lower).joined(separator: " ")
            let kilograms = matches(#"\bkg\b(?!\s*/)"#, in: text)
            let pounds = matches(#"\blbs?\b"#, in: text)
            return kilograms > pounds ? .kilograms : .pounds
        }

        private func matches(_ pattern: String, in text: String) -> Int {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }  // MARK: try? justified - constant pattern.
            return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        }

        private func isLabel(_ line: Line, _ spec: FieldSpec) -> Bool {
            guard !spec.excludes.contains(where: { line.lower.contains($0) }) else { return false }
            return spec.labels.contains { line.lower.range(of: $0, options: .regularExpression) != nil }
        }

        /// Labels: never in skipped sections, and segment labels only in the
        /// segmental lean section when the sheet has one.
        private func allowed(_ index: Int, for spec: FieldSpec) -> Bool {
            switch sections[index] {
            case .excluded: return false
            case .lean: return true
            case .other, nil: return !(spec.segment && hasLeanSection)
            }
        }

        func value(for spec: FieldSpec, unit: MassUnit) -> Double? {
            var best: [Candidate] = []
            for (index, label) in lines.enumerated() where isLabel(label, spec) && allowed(index, for: spec) {
                if let candidate = bestCandidate(for: spec, labelIndex: index, unit: unit) { best.append(candidate) }
            }
            // A whole number where a decimal is printed is a graph tick, so the
            // decimal check outranks where the number sits.
            guard let top = best.map({ ($0.penalty, $0.rank) }).min(by: { $0 < $1 }) else { return nil }
            let finalists = best.filter { ($0.penalty, $0.rank) == top }
            // Values printed twice on a sheet agree; prefer the value most labels found.
            let votes = Dictionary(grouping: finalists) { ($0.value * 100).rounded() }
            let winner = finalists.max { lhs, rhs in
                let (l, r) = (votes[(lhs.value * 100).rounded()]?.count ?? 0, votes[(rhs.value * 100).rounded()]?.count ?? 0)
                return l != r ? l < r : lhs.distance > rhs.distance
            }
            return winner?.value
        }

        private func convert(_ token: NumberToken, spec: FieldSpec, unit: MassUnit) -> Double? {
            var value = token.value
            if spec.kind == .mass, (token.unit ?? unit) == .kilograms {
                value = (value * InBodySheetParser.poundsPerKilogram * 10).rounded() / 10
            }
            return spec.range.contains(value) ? value : nil
        }

        private func bestCandidate(for spec: FieldSpec, labelIndex: Int, unit: MassUnit) -> Candidate? {
            let label = lines[labelIndex]
            var candidates: [Candidate] = []
            func consider(_ tokens: [NumberToken], rank: Int, distance: CGFloat) {
                for token in tokens {
                    guard let value = convert(token, spec: spec, unit: unit) else { continue }
                    candidates.append(Candidate(value: value, rank: rank,
                                                penalty: spec.decimal && !token.hasDecimal ? 1 : 0, distance: distance))
                }
            }
            // Beside the label: the rest of its own line, then the row to its right.
            if let labelEnd = spec.labels.lazy.compactMap({ label.lower.range(of: $0, options: .regularExpression) }).first {
                consider(InBodySheetParser.numbers(in: String(label.lower[labelEnd.upperBound...])), rank: 0, distance: 0)
            }
            var row = (v: label.v, height: label.height)
            var percentRow: CGFloat?
            if spec.segment, let pounds = anchor(near: label, pattern: #"^\(?\s*(lbs?|kg|1b|ib)\s*\)?$"#) {
                // Segment rows print pounds and percent of normal as two sub-rows,
                // each value just above its own bar. Aim half a row above each
                // "(lb)"/"(%)" marker and keep numbers nearer the pound target.
                row = (pounds.v, pounds.height)
                if let percent = anchor(near: label, pattern: #"^\(?\s*%\s*\)?$"#),
                   case let pitch = percent.v - pounds.v, pitch > 0.5 * pounds.height, pitch < 3 * pounds.height {
                    row.v = pounds.v - pitch / 2
                    percentRow = percent.v - pitch / 2
                }
            }
            for (index, line) in lines.enumerated()
            where index != labelIndex && sections[index] != .excluded && columns[index] == columns[labelIndex] {
                guard line.numbers.count < 3 else { continue }  // graph scales
                let along = line.u - label.u
                let across = line.v - row.v
                if along > 0, line.uMin > label.uMin, along < 0.75 * pageWidth,
                   abs(across) <= max(row.height, label.height) {
                    // Nearer the percent-of-normal row: not the pound value.
                    if let percentRow, abs(line.v - percentRow) <= abs(across) { continue }
                    consider(line.numbers, rank: 0, distance: abs(across) / label.height)
                } else if let below = spec.below, line.v > label.v + 0.5 * label.height,
                          line.v - label.v < 12 * label.height, isUnder(line, label, below) {
                    let tokens = below == .chart ? line.numbers.filter(\.hasDecimal) : line.numbers
                    consider(tokens, rank: 1, distance: (line.v - label.v) / label.height)
                }
            }
            return candidates.min { ($0.penalty, $0.rank, $0.distance) < ($1.penalty, $1.rank, $1.distance) }
        }

        /// Column values are centered under their header; chart values can sit
        /// anywhere within a label's width to either side.
        private func isUnder(_ line: Line, _ label: Line, _ below: Below) -> Bool {
            switch below {
            case .column:
                return line.u > label.uMin - 0.15 * label.width && line.u < label.uMax + 0.15 * label.width
            case .chart:
                return line.uMax > label.uMin - label.width && line.uMin < label.uMax + label.width
            }
        }

        /// The unit marker just right of a label on its row, if printed.
        private func anchor(near label: Line, pattern: String) -> Line? {
            lines.filter { line in
                line.lower.trimmingCharacters(in: .whitespaces).range(of: pattern, options: .regularExpression) != nil
                    && line.u > label.u && line.uMin - label.uMax < 0.25 * pageWidth
                    && abs(line.v - label.v) < 1.6 * label.height
            }.min { abs($0.v - label.v) < abs($1.v - label.v) }
        }

        // MARK: Header values

        func testDate(calendar: Calendar, now: Date) -> Date? {
            let latest = now.addingTimeInterval(86_400)
            let labels = [#"test date"#, #"date\s*/\s*time"#, "測定日時", "測定日", "検査日"]
            for (index, label) in lines.enumerated()
            where labels.contains(where: { label.lower.range(of: $0, options: .regularExpression) != nil }) {
                let nearby = lines.enumerated().filter { other in
                    guard sections[other.offset] != .excluded else { return false }
                    let line = other.element
                    let beside = line.u >= label.u && abs(line.v - label.v) <= 0.8 * label.height
                    let below = line.v > label.v && line.v - label.v < 4 * label.height
                        && line.uMax > label.uMin - label.width && line.uMin < label.uMax + label.width
                    return other.offset == index || beside || below
                }.sorted { abs($0.element.v - label.v) < abs($1.element.v - label.v) }
                for candidate in nearby {
                    if let date = InBodySheetParser.parseDate(candidate.element.text, calendar: calendar), date <= latest { return date }
                }
            }
            // Unlabeled: the latest full date outside the history section.
            return lines.indices.filter { sections[$0] != .excluded }
                .compactMap { InBodySheetParser.parseDate(lines[$0].text, calendar: calendar) }
                .filter { $0 <= latest }.max()
        }

        func heightInches() -> Double? {
            for label in lines where label.lower.range(of: #"^height\b|^身長"#, options: .regularExpression) != nil {
                let nearby = lines.filter { line in
                    let beside = line.u >= label.u && abs(line.v - label.v) <= 0.8 * label.height
                    let below = line.v > label.v && line.v - label.v < 4 * label.height
                        && line.uMax > label.uMin - label.width && line.uMin < label.uMax + label.width
                    return beside || below
                }.sorted { abs($0.v - label.v) < abs($1.v - label.v) }
                if let height = nearby.lazy.compactMap({ InBodySheetParser.parseHeightInches($0.text) }).first {
                    return height
                }
            }
            return nil
        }
    }
}

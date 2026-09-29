import XCTest
import CoreGraphics
import UIKit
@testable import PersonalOptimization

/// Reading an InBody result sheet from recognized text. Fixtures are
/// synthetic (InBodySampleSheet); no real scan values appear in tests.
final class InBodySheetParserTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    private func sample() -> InBodyPhotoReading {
        InBodySheetParser.parse(InBodySampleSheet.lines, now: now, calendar: calendar)
    }

    func test_sampleSheetReadsEveryValueAndSkipsDistractors() throws {
        let reading = sample()
        XCTAssertEqual(reading.read, Set(InBodyField.allCases))
        let values = reading.values
        XCTAssertEqual(values.date, date(2026, 3, 14, 9, 5), "The spaced date under Test Date / Time")
        XCTAssertEqual(values.heightInches, 70.0)
        XCTAssertEqual(values.weightLb, 200.0, "Not the history column's 198.1")
        XCTAssertEqual(values.skeletalMuscleMassLb, 88.2, "Not a whole-number scale tick")
        XCTAssertEqual(values.leanBodyMassLb, 155.0, "The column value, not the control section's +2.0")
        XCTAssertEqual(values.bodyFatMassLb, 45.0, "Not the control section's -12.5")
        XCTAssertEqual(values.bodyFatPercent, 22.5, "Not a decimal scale tick above it")
        XCTAssertEqual(values.totalBodyWaterLb, 113.0, "Under its column, not the intracellular cell beside it")
        XCTAssertEqual(values.ecwTbwRatio, 0.379, "Not the scale line or a segment's ratio")
        XCTAssertEqual(values.visceralFatAreaCm2, 95.6, "The chart value, not an axis tick")
        XCTAssertEqual(values.basalMetabolicRateKcal, 1850, "Thousands separator")
        XCTAssertEqual(values.rightArmLb, 8.21, "Segmental lean, not segmental fat")
        XCTAssertEqual(values.leftArmLb, 8.15)
        XCTAssertEqual(values.trunkLb, 66.3, "Pounds, not the 104.2 percent-of-normal row")
        XCTAssertEqual(values.rightLegLb, 22.84, "A decimal split across two text runs")
        XCTAssertEqual(values.leftLegLb, 22.61, "A decimal printed with a space")
        XCTAssertFalse(reading.convertedFromKilograms)
        XCTAssertTrue(reading.uncertain.isEmpty)
        XCTAssertNoThrow(try values.validate())
    }

    func test_tiltedPhotoKeepsRowsTogether() {
        let angle: CGFloat = 0.035  // about 2 degrees
        let pivot = CGPoint(x: 900, y: 950)
        let tilted = InBodySampleSheet.lines.map { line -> RecognizedTextLine in
            var copy = line
            let (dx, dy) = (line.center.x - pivot.x, line.center.y - pivot.y)
            copy.center = CGPoint(x: pivot.x + dx * cos(angle) - dy * sin(angle),
                                  y: pivot.y + dx * sin(angle) + dy * cos(angle))
            copy.angle = angle
            return copy
        }
        let reading = InBodySheetParser.parse(tilted, now: now, calendar: calendar)
        XCTAssertEqual(reading.read, Set(InBodyField.allCases))
        XCTAssertEqual(reading.values.skeletalMuscleMassLb, 88.2)
        XCTAssertEqual(reading.values.bodyFatPercent, 22.5)
        XCTAssertEqual(reading.values.trunkLb, 66.3)
        XCTAssertEqual(reading.values.visceralFatAreaCm2, 95.6)
    }

    func test_japaneseKilogramSheetConvertsToPounds() {
        let lines: [RecognizedTextLine] = [
            .init("身長", x: 560, y: 100, width: 50),
            .init("178.0cm", x: 560, y: 130, width: 80),
            .init("測定日時", x: 900, y: 100, width: 120),
            .init("2026.03.14 09:05", x: 900, y: 130, width: 170),
            .init("体成分分析", x: 300, y: 200, width: 150, height: 26),
            .init("体水分量", x: 300, y: 250, width: 90),
            .init("(kg)", x: 470, y: 250, width: 35),
            .init("51.3", x: 560, y: 248, width: 45),
            .init("除脂肪量", x: 800, y: 230, width: 90),
            .init("70.3", x: 815, y: 290, width: 45),
            .init("体脂肪量", x: 300, y: 330, width: 90),
            .init("(kg)", x: 470, y: 330, width: 35),
            .init("20.4", x: 560, y: 328, width: 45),
            .init("体重", x: 300, y: 420, width: 50),
            .init("(kg)", x: 470, y: 420, width: 35),
            .init("90.7", x: 700, y: 416, width: 45),
            .init("骨格筋量", x: 300, y: 470, width: 90),
            .init("40.0", x: 650, y: 466, width: 45),
            .init("体脂肪率", x: 300, y: 520, width: 90),
            .init("(%)", x: 470, y: 520, width: 30),
            .init("22.5", x: 600, y: 516, width: 45),
            .init("基礎代謝量", x: 1000, y: 300, width: 110),
            .init("1653 kcal", x: 1150, y: 298, width: 90),
        ]
        let reading = InBodySheetParser.parse(lines, now: now, calendar: calendar)
        XCTAssertTrue(reading.convertedFromKilograms)
        XCTAssertEqual(reading.values.weightLb, 200.0)
        XCTAssertEqual(reading.values.skeletalMuscleMassLb, 88.2)
        XCTAssertEqual(reading.values.bodyFatMassLb, 45.0)
        XCTAssertEqual(reading.values.leanBodyMassLb, 155.0)
        XCTAssertEqual(reading.values.totalBodyWaterLb, 113.1)
        XCTAssertEqual(reading.values.bodyFatPercent, 22.5, "Percent is not a mass")
        XCTAssertEqual(reading.values.basalMetabolicRateKcal, 1653)
        XCTAssertEqual(reading.values.heightInches, 70.1)
        XCTAssertEqual(reading.values.date, date(2026, 3, 14, 9, 5))
    }

    func test_numbersIgnoreRangesAndSignsAndReadSpacedDecimals() {
        let normalized = InBodySheetParser.normalize("Weight (lb) 201. 3 (160.0~210.0)")
        XCTAssertEqual(InBodySheetParser.numbers(in: normalized).map(\.value), [201.3])
        XCTAssertEqual(InBodySheetParser.numbers(in: "1,905 kcal").map(\.value), [1905])
        XCTAssertEqual(InBodySheetParser.numbers(in: "-4.8 lb"), [])
        XCTAssertEqual(InBodySheetParser.numbers(in: "10.0~20.0"), [])
        XCTAssertEqual(InBodySheetParser.numbers(in: "90.7kg").first?.unit, .kilograms)
        XCTAssertEqual(InBodySheetParser.normalize("5ft 11. Oin"), "5ft 11.0in", "A letter O read inside a number")
        XCTAssertEqual(InBodySheetParser.normalize("1O6.2"), "106.2")
    }

    func test_datesInSheetFormats() {
        XCTAssertEqual(InBodySheetParser.parseDate("11. 02. 2026 07:45", calendar: calendar), date(2026, 11, 2, 7, 45))
        XCTAssertEqual(InBodySheetParser.parseDate("2026/11/02", calendar: calendar), date(2026, 11, 2))
        XCTAssertEqual(InBodySheetParser.parseDate("23.11.2026", calendar: calendar), date(2026, 11, 23),
                       "Day first when the first number cannot be a month")
        XCTAssertEqual(InBodySheetParser.parseDate("2026年11月2日 8:05", calendar: calendar), date(2026, 11, 2, 8, 5))
        XCTAssertNil(InBodySheetParser.parseDate("11.02.26 07:45", calendar: calendar), "Two-digit years are history columns")
        XCTAssertNil(InBodySheetParser.parseDate("13.13.2026", calendar: calendar))
        XCTAssertNil(InBodySheetParser.parseDate("02.30.2026", calendar: calendar), "No rollover into March")
    }

    func test_heightsInFeetAndCentimeters() {
        XCTAssertEqual(InBodySheetParser.parseHeightInches("5ft 11.0in"), 71.0)
        XCTAssertEqual(InBodySheetParser.parseHeightInches("5 ft. 10 in."), 70.0)
        XCTAssertEqual(InBodySheetParser.parseHeightInches("5'10\""), 70.0)
        XCTAssertEqual(InBodySheetParser.parseHeightInches("178.0cm"), 70.1)
        XCTAssertNil(InBodySheetParser.parseHeightInches("32"), "A bare number is not a height")
    }

    func test_unrelatedTextReadsNothing() {
        let reading = InBodySheetParser.parse([
            .init("Grocery list", x: 10, y: 10, width: 120),
            .init("Milk 2.5", x: 10, y: 40, width: 80),
        ], now: now, calendar: calendar)
        XCTAssertTrue(reading.read.isEmpty)
    }

    // MARK: - Combining passes

    func test_passesThatDisagreeAreFlaggedWithBothReadings() throws {
        var first = sample()
        var second = sample()
        first.values.visceralFatAreaCm2 = 35.6
        second.values.visceralFatAreaCm2 = 95.6
        second.read.remove(.height)
        let combined = try XCTUnwrap(InBodySheetParser.consensus([first, second]))
        XCTAssertEqual(combined.values.visceralFatAreaCm2, 35.6, "A tie keeps the sharper first pass")
        XCTAssertEqual(combined.uncertain[.visceralFatArea], [35.6, 95.6])
        XCTAssertEqual(combined.values.heightInches, 70.0, "Read by one pass only")
        XCTAssertEqual(combined.uncertain.count, 1)
    }

    func test_sheetArithmeticSettlesASplitRead() throws {
        var first = sample()
        let second = sample()
        first.values.leanBodyMassLb = 152.0  // a misread; 200.0 - 45.0 = 155.0
        let combined = try XCTUnwrap(InBodySheetParser.consensus([first, second]))
        XCTAssertEqual(combined.values.leanBodyMassLb, 155.0)
        XCTAssertNil(combined.uncertain[.leanBodyMass])
    }

    func test_valuesThatDoNotAddUpAreFlagged() throws {
        var misread = sample()
        misread.values.leanBodyMassLb = 150.0
        misread.values.bodyFatPercent = 25.0
        let combined = try XCTUnwrap(InBodySheetParser.consensus([misread]))
        XCTAssertEqual(combined.uncertain[.leanBodyMass], [150.0])
        XCTAssertEqual(combined.uncertain[.weight], [200.0])
        XCTAssertEqual(combined.uncertain[.bodyFatPercent], [25.0])
    }

    func test_laterPagesOnlyFillGaps() {
        var firstPage = sample()
        firstPage.read.remove(.rightArm)
        firstPage.values.rightArmLb = nil
        var secondPage = sample()
        secondPage.values.weightLb = 199.0
        secondPage.values.rightArmLb = 8.3
        let merged = firstPage.merged(with: secondPage)
        XCTAssertEqual(merged.values.weightLb, 200.0)
        XCTAssertEqual(merged.values.rightArmLb, 8.3)
        XCTAssertTrue(merged.read.contains(.rightArm))
    }
}

/// End to end through Vision on a rendered sample sheet (simulator CPU).
final class InBodySheetRecognizerTests: XCTestCase {
    func test_renderedSampleSheetReadsThroughVision() throws {
        let reading = try InBodySheetRecognizer.read(imageData: [InBodySampleSheet.pngData()], now: Date(), calendar: .current)
        XCTAssertEqual(reading.values.weightLb, 200.0)
        XCTAssertEqual(reading.values.skeletalMuscleMassLb, 88.2)
        XCTAssertEqual(reading.values.leanBodyMassLb, 155.0)
        XCTAssertEqual(reading.values.bodyFatMassLb, 45.0)
        XCTAssertEqual(reading.values.bodyFatPercent, 22.5)
        XCTAssertEqual(reading.values.trunkLb, 66.3)
        XCTAssertEqual(reading.values.rightLegLb, 22.84)
        XCTAssertEqual(reading.values.date, Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9, minute: 5)))
        XCTAssertEqual(reading.read, Set(InBodyField.allCases))
    }


    func test_dataThatIsNotAnImageIsRejected() {
        XCTAssertThrowsError(try InBodySheetRecognizer.read(imageData: [Data("not an image".utf8)], now: Date(), calendar: .current)) {
            XCTAssertEqual($0 as? InBodyPhotoError, .unreadableImage)
        }
    }

    func test_blankPageFindsNothing() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 400))
        let blank = renderer.pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
        }
        XCTAssertThrowsError(try InBodySheetRecognizer.read(imageData: [blank], now: Date(), calendar: .current)) {
            XCTAssertEqual($0 as? InBodyPhotoError, .noValuesFound)
        }
    }
}

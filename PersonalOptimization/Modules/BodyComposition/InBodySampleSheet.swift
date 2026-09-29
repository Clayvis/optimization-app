#if DEBUG
import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// A synthetic InBody 770-style result sheet with made-up values, laid out
/// like the printout: header row, body-composition table, graph rows with
/// scales, pound and percent sub-rows, a chart, and the control, segmental
/// fat and history sections that must be ignored. Debug builds only: parser
/// fixtures, and the UI-test photo path (`--ui-testing-inbody-photo`).
enum InBodySampleSheet {
    static let size = CGSize(width: 1800, height: 1900)
    /// Vertical rules between the body-composition table's columns.
    static let tableColumnBorders: [CGFloat] = [660, 825, 1005]

    /// Expected values: 200.0 lb = 155.0 lean + 45.0 fat; 22.5 % body fat.
    static let lines: [RecognizedTextLine] = [
        // Header row: values print under their labels.
        .init("Height", x: 560, y: 240, width: 60),
        .init("5ft 10.0in", x: 580, y: 272, width: 110),
        .init("Age", x: 700, y: 234, width: 40),
        .init("41", x: 720, y: 266, width: 25),
        .init("Test Date / Time", x: 880, y: 222, width: 150),
        .init("03. 14. 2026 09:05", x: 900, y: 256, width: 175),
        // Body composition table: cumulative columns print under their headers.
        .init("Body Composition Analysis", x: 340, y: 320, width: 330, height: 26),
        .init("Values", x: 570, y: 360, width: 60),
        .init("Total Body Water", x: 680, y: 358, width: 120),
        .init("Lean Body Mass", x: 850, y: 354, width: 130),
        .init("Weight", x: 1030, y: 350, width: 55),
        .init("Intracellular Water", x: 340, y: 392, width: 140),
        .init("(lb)", x: 500, y: 392, width: 30),
        .init("70.1", x: 595, y: 386, width: 45, height: 22),
        .init("113.0", x: 725, y: 398, width: 60, height: 22),
        .init("Extracellular Water", x: 340, y: 432, width: 140),
        .init("(lb)", x: 500, y: 432, width: 30),
        .init("42.9", x: 595, y: 426, width: 45, height: 22),
        .init("155.0", x: 880, y: 410, width: 60, height: 22),
        .init("Dry Lean Mass", x: 340, y: 472, width: 110),
        .init("(lb)", x: 500, y: 472, width: 30),
        .init("42.0", x: 595, y: 466, width: 45, height: 22),
        .init("200.0", x: 1035, y: 424, width: 60, height: 22),
        .init("Body Fat Mass", x: 340, y: 512, width: 110),
        .init("(lb)", x: 500, y: 512, width: 30),
        .init("45.0", x: 595, y: 506, width: 45, height: 22),
        .init("(20.1~40.2)", x: 645, y: 510, width: 80, height: 14),
        // Muscle-fat graphs: whole-number scales, value at the bar's end.
        .init("Muscle-Fat Analysis", x: 330, y: 560, width: 250, height: 26),
        .init("55 70 85 100 115 130 145 160 175 190 205 %", x: 560, y: 600, width: 580, height: 14),
        .init("Weight", x: 330, y: 630, width: 70),
        .init("(lb)", x: 500, y: 630, width: 30),
        .init("200.0", x: 840, y: 612, width: 60, height: 22),
        .init("70", x: 565, y: 658, width: 20, height: 14),
        .init("80", x: 620, y: 658, width: 20, height: 14),
        .init("90", x: 675, y: 658, width: 20, height: 14),
        .init("100", x: 725, y: 658, width: 28, height: 14),
        .init("SMM", x: 330, y: 676, width: 45),
        .init("Skeletal Muscle Mass", x: 330, y: 700, width: 150, height: 14),
        .init("(lb)", x: 500, y: 680, width: 30),
        .init("88.2", x: 790, y: 664, width: 50, height: 22),
        .init("Body Fat Mass", x: 330, y: 730, width: 110),
        .init("(lb)", x: 500, y: 730, width: 30),
        .init("45.0", x: 700, y: 714, width: 45, height: 22),
        // Obesity graphs: decimal scale ticks just above the value.
        .init("Obesity Analysis", x: 315, y: 780, width: 210, height: 26),
        .init("0.0", x: 545, y: 880, width: 22, height: 12),
        .init("5.0", x: 590, y: 880, width: 22, height: 12),
        .init("10.0", x: 635, y: 880, width: 28, height: 12),
        .init("15.0", x: 685, y: 880, width: 28, height: 12),
        .init("20.0", x: 735, y: 880, width: 28, height: 12),
        .init("25.0", x: 870, y: 878, width: 28, height: 12),
        .init("30.0", x: 925, y: 876, width: 28, height: 12),
        .init("PBF", x: 315, y: 892, width: 40),
        .init("Percent Body Fat", x: 315, y: 916, width: 120, height: 14),
        .init("(%)", x: 485, y: 892, width: 25),
        .init("22.5", x: 800, y: 894, width: 45, height: 22),
        // Segmental lean: pounds above percent of normal; per-segment ECW/TBW at right.
        .init("Segmental Lean Analysis", x: 300, y: 955, width: 330, height: 26),
        .init("ECW/TBW", x: 1075, y: 962, width: 75, height: 16),
        .init("Right Arm", x: 313, y: 1032, width: 105, height: 22),
        .init("(lb)", x: 490, y: 1030, width: 30),
        .init("(%)", x: 490, y: 1054, width: 30),
        .init("55", x: 560, y: 1004, width: 20, height: 12),
        .init("8.21", x: 850, y: 1018, width: 45),
        .init("98.7", x: 730, y: 1042, width: 45),
        .init("0.371", x: 1100, y: 1015, width: 55),
        .init("Left Arm", x: 313, y: 1097, width: 95, height: 22),
        .init("(lb)", x: 490, y: 1095, width: 30),
        .init("(%)", x: 490, y: 1119, width: 30),
        .init("8.15", x: 860, y: 1083, width: 45),
        .init("97.9", x: 735, y: 1107, width: 45),
        .init("0.370", x: 1100, y: 1080, width: 55),
        .init("Trunk", x: 313, y: 1162, width: 60, height: 22),
        .init("(lb)", x: 490, y: 1160, width: 30),
        .init("(%)", x: 490, y: 1184, width: 30),
        .init("66.3", x: 860, y: 1148, width: 45),
        .init("104.2", x: 725, y: 1172, width: 55),
        .init("0.368", x: 1100, y: 1145, width: 55),
        .init("Right Leg", x: 313, y: 1227, width: 100, height: 22),
        .init("(lb)", x: 490, y: 1225, width: 30),
        .init("(%)", x: 490, y: 1249, width: 30),
        .init("22.", x: 820, y: 1213, width: 30),
        .init("84", x: 858, y: 1213, width: 25),
        .init("95.1", x: 720, y: 1237, width: 45),
        .init("Left Leg", x: 313, y: 1292, width: 90, height: 22),
        .init("(lb)", x: 490, y: 1290, width: 30),
        .init("(%)", x: 490, y: 1314, width: 30),
        .init("22. 61", x: 825, y: 1278, width: 60),
        .init("94.4", x: 720, y: 1302, width: 45),
        // Whole-body ECW/TBW: a many-number scale line above the value.
        .init("ECW/TBW Analysis", x: 305, y: 1360, width: 270, height: 26),
        .init("0.320 0.340 0.360 0.380 0.390 0.400 0.410 0.420 0.430 0.440 0.450", x: 540, y: 1420, width: 620, height: 12),
        .init("ECW/TBW", x: 310, y: 1445, width: 110, height: 22),
        .init("0.379", x: 680, y: 1448, width: 60, height: 22),
        // History: an older test's values, never read.
        .init("Body Composition History", x: 300, y: 1510, width: 350, height: 26),
        .init("Weight", x: 305, y: 1575, width: 70),
        .init("(lb)", x: 500, y: 1575, width: 30),
        .init("198.1", x: 540, y: 1570, width: 60, height: 22),
        .init("PBF", x: 300, y: 1715, width: 40),
        .init("23.9", x: 545, y: 1712, width: 45, height: 22),
        .init("03.14.26 09:05", x: 535, y: 1860, width: 120, height: 16),
        // Right column: visceral fat chart (whole-number axis ticks).
        .init("Visceral Fat Area", x: 1190, y: 318, width: 175, height: 22),
        .init("VFA(cm2)", x: 1190, y: 345, width: 90, height: 16),
        .init("200", x: 1205, y: 360, width: 30, height: 14),
        .init("150", x: 1205, y: 410, width: 30, height: 14),
        .init("100", x: 1205, y: 460, width: 30, height: 14),
        .init("50", x: 1210, y: 510, width: 22, height: 14),
        .init("95.6", x: 1375, y: 440, width: 45, height: 22),
        .init("20 40 60 80 Age", x: 1320, y: 570, width: 250, height: 14),
        // Control section: signed targets that look like values.
        .init("Body Fat - Lean Body Mass Control", x: 1205, y: 600, width: 330, height: 22),
        .init("Body Fat Mass", x: 1207, y: 645, width: 130),
        .init("-12.5 lb", x: 1470, y: 640, width: 70),
        .init("Lean Body Mass", x: 1207, y: 675, width: 140),
        .init("+2.0 lb", x: 1480, y: 670, width: 60),
        // Segmental fat: same segment names as segmental lean.
        .init("Segmental Fat Analysis", x: 1210, y: 735, width: 260, height: 22),
        .init("Right Arm", x: 1215, y: 790, width: 80),
        .init("( 2.4 lb )", x: 1320, y: 788, width: 70),
        .init("180.2%", x: 1520, y: 786, width: 60),
        .init("Trunk", x: 1215, y: 850, width: 50),
        .init("( 18.6lb )", x: 1320, y: 848, width: 80),
        .init("195.3%", x: 1540, y: 846, width: 60),
        .init("Research Parameters", x: 1225, y: 935, width: 240, height: 22),
        .init("Basal Metabolic Rate", x: 1225, y: 965, width: 170),
        .init("1,850 kcal", x: 1420, y: 960, width: 100),
        .init("TBW/LBM", x: 1228, y: 1030, width: 80),
        .init("72.9 %", x: 1425, y: 1025, width: 70),
        .init("SMI", x: 1230, y: 1062, width: 35),
        .init("8.1 kg/m2", x: 1440, y: 1058, width: 90),
        .init("Impedance", x: 1250, y: 1430, width: 110, height: 22),
        .init("Z(Ω) 1 kHz 301.2 310.4 22.1 330.0 331.5", x: 1260, y: 1470, width: 400, height: 16),
    ]

    #if canImport(UIKit)
    /// The sheet drawn as a PNG, black on white, for end-to-end reading.
    static func pngData() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            for x in tableColumnBorders {
                context.fill(CGRect(x: x, y: 330, width: 2, height: 210))
            }
            for line in lines {
                // Size each line to its box (system glyphs average about 0.55 em)
                // so neighbors never overlap and positions match `lines`. Not a
                // monospaced font: its slashed zero reads as an 8.
                let fitted = min(line.height * 1.05, line.width / (CGFloat(max(line.text.count, 1)) * 0.55))
                let font = UIFont.systemFont(ofSize: max(10, fitted), weight: .regular)
                let origin = CGPoint(x: line.center.x - line.width / 2, y: line.center.y - line.height / 2)
                NSAttributedString(string: line.text, attributes: [.font: font, .foregroundColor: UIColor.black])
                    .draw(at: origin)
            }
        }
    }
    #endif
}
#endif

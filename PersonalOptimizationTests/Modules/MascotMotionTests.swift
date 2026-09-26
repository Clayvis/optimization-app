import XCTest
import SwiftUI
@testable import PersonalOptimization

@MainActor
final class MascotMotionTests: XCTestCase {
    func test_renderFourSequencesForVisualReview() throws {
        for state in ["neutral", "training", "recovering", "celebrating"] {
            let renderer = ImageRenderer(content:
                MascotIllustration(stateName: state, palette: .ninjaFemale,
                    motion: .sample(state: state, elapsed: 1.2))
                    .frame(width: 300, height: 300).background(.white))
            let data = try XCTUnwrap(renderer.uiImage?.pngData())
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("phase2-mascot-\(state).png")
            try data.write(to: url)
            print("Motion review: \(url.path)")
        }
    }

    func test_idleBlinksAndInvalidTimeIsStill() {
        typealias Motion = MascotIllustration.Motion
        XCTAssertEqual(Motion.sample(state: "neutral", elapsed: .infinity), Motion())
        XCTAssertEqual(Motion.sample(state: "neutral", elapsed: -1), Motion())
        XCTAssertLessThan(Motion.sample(state: "neutral", elapsed: 2.8).eyeOpen, 0.1)
        XCTAssertEqual(Motion.sample(state: "neutral", elapsed: 3.2).eyeOpen, 1)
    }
    func test_trainingMovesArmsAndLegsRecoveryIsGentle() {
        let active = MascotIllustration.Motion.sample(state: "training", elapsed: 1)
        XCTAssertGreaterThan(active.leftArm, 30)
        XCTAssertLessThan(active.rightArm, -30)
        XCTAssertNotEqual(active.leftLeg, 0)
        let rest = MascotIllustration.Motion.sample(state: "recovering", elapsed: 1)
        XCTAssertEqual(rest.lift, 0)
        XCTAssertEqual(rest.leftLeg, 0)
        XCTAssertLessThan(abs(rest.leftArm), 5)
    }
    func test_celebrationSettlesAfterOneSequence() {
        let jump = MascotIllustration.Motion.sample(state: "celebrating", elapsed: 1.2)
        XCTAssertGreaterThan(jump.lift, 5)
        let settled = MascotIllustration.Motion.sample(state: "celebrating", elapsed: 3)
        XCTAssertEqual(settled.lift, 0)
        XCTAssertEqual(settled.leftArm, 0)
    }
}

import XCTest
@testable import PersonalOptimization

final class HandoffServiceTests: XCTestCase {

    // MARK: - HandoffActivityType stability

    func test_activityType_rawValues_stable() {
        // These strings ship in user-device Info.plist NSUserActivityTypes
        // and are referenced by paired devices in flight. Changing any of
        // them silently orphans an in-progress Handoff banner.
        XCTAssertEqual(HandoffActivityType.lift.rawValue,
                       "com.rawlins.PersonalOptimization.activity.lift")
        XCTAssertEqual(HandoffActivityType.basketball.rawValue,
                       "com.rawlins.PersonalOptimization.activity.basketball")
        XCTAssertEqual(HandoffActivityType.swim.rawValue,
                       "com.rawlins.PersonalOptimization.activity.swim")
        XCTAssertEqual(HandoffActivityType.customActivity.rawValue,
                       "com.rawlins.PersonalOptimization.activity.custom")
        XCTAssertEqual(HandoffActivityType.learning.rawValue,
                       "com.rawlins.PersonalOptimization.activity.learning")
    }

    func test_activityType_displayTitle_humanReadable() {
        XCTAssertEqual(HandoffActivityType.lift.displayTitle, "Lift")
        XCTAssertEqual(HandoffActivityType.basketball.displayTitle, "Basketball")
        XCTAssertEqual(HandoffActivityType.swim.displayTitle, "Swim")
        XCTAssertEqual(HandoffActivityType.customActivity.displayTitle, "Workout")
        XCTAssertEqual(HandoffActivityType.learning.displayTitle, "Learning")
    }

    // MARK: - userInfo builder

    func test_userInfo_includesSessionID_andTemplate() {
        let id = UUID()
        let info = HandoffService.userInfo(for: .lift, sessionID: id, template: "Lift A")
        XCTAssertEqual(info["sessionID"], id.uuidString)
        XCTAssertEqual(info["template"], "Lift A")
    }

    func test_userInfo_dropsNilFields() {
        let info = HandoffService.userInfo(for: .lift)
        XCTAssertTrue(info.isEmpty, "Empty userInfo when nothing to attach.")
    }

    func test_userInfo_includesOnlyTemplate_whenNoSession() {
        let info = HandoffService.userInfo(for: .basketball, template: "Pickup")
        XCTAssertEqual(info["template"], "Pickup")
        XCTAssertNil(info["sessionID"])
    }

    // MARK: - HandoffPayload parsing

    func test_payload_parsesValidActivity() {
        let id = UUID()
        let payload = HandoffPayload(
            activityType: HandoffActivityType.lift.rawValue,
            userInfo: ["sessionID": id.uuidString, "template": "Lift B"]
        )
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.type, .lift)
        XCTAssertEqual(payload?.sessionID, id)
        XCTAssertEqual(payload?.template, "Lift B")
    }

    func test_payload_returnsNilForUnknownType() {
        let payload = HandoffPayload(
            activityType: "com.rawlins.PersonalOptimization.activity.bogus",
            userInfo: nil
        )
        XCTAssertNil(payload)
    }

    func test_payload_tolerates_missingUserInfo() {
        let payload = HandoffPayload(activityType: HandoffActivityType.swim.rawValue, userInfo: nil)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.type, .swim)
        XCTAssertNil(payload?.sessionID)
        XCTAssertNil(payload?.template)
    }

    func test_payload_tolerates_malformedSessionID() {
        let payload = HandoffPayload(
            activityType: HandoffActivityType.lift.rawValue,
            userInfo: ["sessionID": "not-a-uuid"]
        )
        XCTAssertNotNil(payload)
        XCTAssertNil(payload?.sessionID, "Malformed UUID becomes nil instead of crashing.")
    }
}

import XCTest
@testable import PersonalOptimization

/// Coverage for the WC event payload encoding. The WCSession lifecycle itself
/// can't be exercised on the host (no paired peer in CI) but the event types
/// must round-trip cleanly so the watch and phone speak the same dictionary.
final class WatchConnectivityServiceTests: XCTestCase {

    func test_event_roundtrip_through_jsonDictionary() throws {
        let original = WatchConnectivityEvent(
            kind: .waterLogged,
            payload: ["oz": "16", "beverage": "water"],
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(original)
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("Encoding produced non-dictionary JSON")
        }

        // Re-encode like the receiver would after pulling the message dict
        // off the wire, then decode back into the typed event.
        let reEncoded = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(WatchConnectivityEvent.self, from: reEncoded)

        XCTAssertEqual(decoded.kind, original.kind)
        XCTAssertEqual(decoded.payload, original.payload)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, original.timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    func test_eventKind_allCases_haveDistinctRawValues() {
        let kinds: [WatchConnectivityEvent.Kind] = [
            .workoutStarted, .workoutEnded, .waterLogged,
            .fastStarted, .fastEnded, .learningLogged
        ]
        let raws = Set(kinds.map { $0.rawValue })
        XCTAssertEqual(raws.count, kinds.count, "Event kind raw values must be unique")
    }

    func test_event_emptyPayload_encodesAndDecodes() throws {
        let event = WatchConnectivityEvent(kind: .fastStarted)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(WatchConnectivityEvent.self, from: data)
        XCTAssertEqual(decoded.kind, .fastStarted)
        XCTAssertTrue(decoded.payload.isEmpty)
    }
}

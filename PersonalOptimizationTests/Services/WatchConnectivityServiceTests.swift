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

    // MARK: - Failure-mode tests via WCSessionTransport seam

    func test_send_dropsWhenNotActivated() throws {
        let fake = FakeWCTransport()
        fake.isActivated = false
        fake.isReachable = true
        WatchConnectivityService.shared.setTransportForTesting(fake)
        defer { WatchConnectivityService.shared.setTransportForTesting(nil) }

        WatchConnectivityService.shared.send(.init(kind: .waterLogged, payload: ["oz": "16"]))
        XCTAssertTrue(fake.sentMessages.isEmpty, "sendMessage must not be called when session is not activated.")
    }

    func test_send_dropsWhenUnreachable() throws {
        let fake = FakeWCTransport()
        fake.isActivated = true
        fake.isReachable = false
        WatchConnectivityService.shared.setTransportForTesting(fake)
        defer { WatchConnectivityService.shared.setTransportForTesting(nil) }

        WatchConnectivityService.shared.send(.init(kind: .waterLogged, payload: ["oz": "16"]))
        XCTAssertTrue(fake.sentMessages.isEmpty, "sendMessage must not be called when peer is unreachable.")
    }

    func test_send_succeedsWhenActivatedAndReachable() throws {
        let fake = FakeWCTransport()
        fake.isActivated = true
        fake.isReachable = true
        WatchConnectivityService.shared.setTransportForTesting(fake)
        defer { WatchConnectivityService.shared.setTransportForTesting(nil) }

        WatchConnectivityService.shared.send(.init(kind: .waterLogged, payload: ["oz": "16"]))
        XCTAssertEqual(fake.sentMessages.count, 1)
        XCTAssertEqual(fake.sentMessages.first?["kind"] as? String, "waterLogged")
    }

    func test_send_invokesErrorHandlerOnTransportError() throws {
        let fake = FakeWCTransport()
        fake.isActivated = true
        fake.isReachable = true
        fake.errorToReturn = NSError(domain: "wc.test", code: 1)
        WatchConnectivityService.shared.setTransportForTesting(fake)
        defer { WatchConnectivityService.shared.setTransportForTesting(nil) }

        // sendMessage will hand the synthetic error to the errorHandler; the
        // service logs it. We just confirm the call happened (so the error
        // handler is reachable) and the surface doesn't crash.
        WatchConnectivityService.shared.send(.init(kind: .waterLogged))
        XCTAssertEqual(fake.sentMessages.count, 1)
        XCTAssertTrue(fake.errorHandlerCalled, "errorHandler must fire when transport reports failure.")
    }

    func test_injectIncomingEvent_appearsOnStream() async throws {
        let event = WatchConnectivityEvent(kind: .workoutEnded, payload: ["minutes": "45"])
        // Subscribe to the next event before injecting.
        let expectation = expectation(description: "received injected event")
        let collector = Task { @MainActor in
            for await received in WatchConnectivityService.shared.lastEventStream {
                if received.kind == .workoutEnded, received.payload["minutes"] == "45" {
                    expectation.fulfill()
                    return
                }
            }
        }
        // Inject after a small delay so the subscriber is registered.
        try await Task.sleep(for: .milliseconds(50))
        WatchConnectivityService.shared.injectIncomingEventForTesting(event)
        await fulfillment(of: [expectation], timeout: 2.0)
        collector.cancel()
    }
}

/// Fake transport used by the failure-mode tests. Records sendMessage calls
/// and lets the test choose which conditions to simulate.
final class FakeWCTransport: WCSessionTransport, @unchecked Sendable {
    var isActivated: Bool = true
    var isReachable: Bool = true
    var sentMessages: [[String: Any]] = []
    var errorToReturn: Error?
    var errorHandlerCalled: Bool = false

    func sendMessage(_ message: [String: Any],
                     replyHandler: (([String: Any]) -> Void)?,
                     errorHandler: ((Error) -> Void)?) {
        sentMessages.append(message)
        if let error = errorToReturn {
            errorHandlerCalled = true
            errorHandler?(error)
        }
    }
}

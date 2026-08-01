import CoreGraphics
import XCTest
@testable import Clicker
import ClickerCore

final class EventRecorderTests: XCTestCase {
    func testStopReturnsFinalDuration() {
        var now: CGEventTimestamp = 1_000_000_000
        let eventTap = StubEventTapSession()
        let recorder = EventRecorder(
            eventTap: eventTap,
            timestampNow: { now }
        )

        XCTAssertTrue(recorder.start(stopShortcut: .defaultValue))
        now = 3_250_000_000

        let capture: RecordingCapture = recorder.stop()

        XCTAssertEqual(capture.events, [])
        XCTAssertEqual(capture.duration, 2.25, accuracy: 0.000_001)
    }

    func testEventTimestampUsesNanosecondsInTheCutoffMonotonicDomain() throws {
        var now: CGEventTimestamp = 2_000_000_000
        let eventTap = StubEventTapSession()
        let recorder = EventRecorder(
            eventTap: eventTap,
            timestampNow: { now }
        )
        XCTAssertTrue(recorder.start(stopShortcut: .defaultValue))

        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: 40, y: 80),
            mouseButton: .left
        ))
        event.timestamp = 2_250_000_000
        now = 9_000_000_000
        eventTap.emit(type: .mouseMoved, event: event)
        now = 3_000_000_000

        let capture = recorder.stop()

        XCTAssertEqual(capture.events.count, 1)
        XCTAssertEqual(capture.events[0].t, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(capture.duration, 1, accuracy: 0.000_001)
    }

    func testInjectedTimeConverterDrivesEventsAndFinalDuration() throws {
        var now: CGEventTimestamp = 100
        let eventTap = StubEventTapSession()
        let recorder = EventRecorder(
            eventTap: eventTap,
            timestampNow: { now },
            elapsedTime: { start, end in
                TimeInterval(end - start) / 100
            }
        )
        XCTAssertTrue(recorder.start(stopShortcut: .defaultValue))

        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: .zero,
            mouseButton: .left
        ))
        event.timestamp = 125
        eventTap.emit(type: .mouseMoved, event: event)
        now = 150

        let capture = recorder.stop()

        XCTAssertEqual(capture.events[0].t, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(capture.duration, 0.5, accuracy: 0.000_001)
    }

    func testCutoffAtMenuInteractionTimestampExcludesLaterCapturedEvents() throws {
        var now: CGEventTimestamp = 1_000_000_000
        let eventTap = StubEventTapSession()
        let recorder = EventRecorder(
            eventTap: eventTap,
            timestampNow: { now }
        )
        XCTAssertTrue(recorder.start(stopShortcut: .defaultValue))

        eventTap.emit(
            type: .mouseMoved,
            event: try mouseEvent(timestamp: 1_200_000_000)
        )
        eventTap.emit(
            type: .leftMouseDown,
            event: try mouseEvent(timestamp: 1_400_000_000, type: .leftMouseDown)
        )
        now = 1_500_000_000

        let cutoff = recorder.cutoff(at: 1_300_000_000)

        XCTAssertEqual(cutoff.eventCount, 1)
        XCTAssertEqual(cutoff.duration, 0.3, accuracy: 0.000_001)
    }

    func testDefaultEscapeRequestsStopOnceAndIsNotRecorded() async throws {
        let eventTap = StubEventTapSession()
        let recorder = EventRecorder(eventTap: eventTap)
        let requested = expectation(description: "default shortcut requests stop")
        requested.assertForOverFulfill = true
        recorder.onStopRequest = { requested.fulfill() }
        XCTAssertTrue(recorder.start(stopShortcut: .defaultValue))

        eventTap.emit(type: .keyDown, event: try keyEvent(keyCode: 53))
        eventTap.emit(type: .keyDown, event: try keyEvent(keyCode: 53))
        eventTap.emit(type: .keyUp, event: try keyEvent(keyCode: 53, keyDown: false))

        await fulfillment(of: [requested], timeout: 1)
        XCTAssertTrue(recorder.stop().events.isEmpty)
    }

    func testCustomCombinationRequiresExactSupportedModifiersAndIsNotRecorded() async throws {
        let eventTap = StubEventTapSession()
        let recorder = EventRecorder(eventTap: eventTap)
        let requested = expectation(description: "custom shortcut requests stop")
        requested.assertForOverFulfill = true
        recorder.onStopRequest = { requested.fulfill() }
        let shortcut = RecordingStopShortcut(
            keyCode: 1,
            modifierFlags: KeyCodeMap.maskOption | KeyCodeMap.maskCommand
        )
        XCTAssertTrue(recorder.start(stopShortcut: shortcut))

        eventTap.emit(type: .keyDown, event: try keyEvent(keyCode: 1, flags: [.maskAlternate]))
        eventTap.emit(
            type: .keyDown,
            event: try keyEvent(keyCode: 1, flags: [.maskAlternate, .maskCommand])
        )
        eventTap.emit(
            type: .keyUp,
            event: try keyEvent(
                keyCode: 1,
                keyDown: false,
                flags: [.maskAlternate, .maskCommand]
            )
        )

        await fulfillment(of: [requested], timeout: 1)
        XCTAssertEqual(recorder.stop().events.count, 1)
    }

    private func mouseEvent(
        timestamp: CGEventTimestamp,
        type: CGEventType = .mouseMoved
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: .zero,
            mouseButton: .left
        ))
        event.timestamp = timestamp
        return event
    }

    private func keyEvent(
        keyCode: CGKeyCode,
        keyDown: Bool = true,
        flags: CGEventFlags = []
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: keyDown
        ))
        event.flags = flags
        return event
    }
}

private final class StubEventTapSession: EventTapSession {
    private(set) var isRunning = false
    private var handler: ((CGEventType, CGEvent) -> Void)?

    func start(handler: @escaping (CGEventType, CGEvent) -> Void) -> Bool {
        self.handler = handler
        isRunning = true
        return true
    }

    func stop() {
        isRunning = false
        handler = nil
    }

    func emit(type: CGEventType, event: CGEvent) {
        handler?(type, event)
    }
}

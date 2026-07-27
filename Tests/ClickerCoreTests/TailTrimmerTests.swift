import XCTest
@testable import ClickerCore

final class TailTrimmerTests: XCTestCase {
    func ev(_ t: TimeInterval, _ kind: EventKind, x: Double = 0, y: Double = 0,
            keyCode: UInt16 = 0, flags: UInt64 = 0, chars: String = "") -> RecordedEvent {
        RecordedEvent(
            t: t,
            kind: kind,
            x: x,
            y: y,
            keyCode: keyCode,
            flags: flags,
            chars: chars
        )
    }

    func testTrimHotKeyStopCompatibilityWrapper() {
        let stopFlags = KeyCodeMap.maskOption | KeyCodeMap.maskCommand
        let events = [
            ev(0, .leftDown, x: 1, y: 1),
            ev(0.1, .leftUp, x: 1, y: 1),
            ev(1.0, .flagsChanged, keyCode: 58, flags: KeyCodeMap.maskOption),
            ev(1.1, .flagsChanged, keyCode: 55, flags: stopFlags),
            ev(1.2, .keyDown, keyCode: 15, flags: stopFlags),
            ev(1.3, .keyUp, keyCode: 15, flags: stopFlags),
        ]

        let trimmed = TailTrimmer.trimHotKeyStop(
            events,
            stopKeyCode: 15,
            stopFlags: stopFlags
        )

        XCTAssertEqual(trimmed.count, 2)
        XCTAssertEqual(trimmed.last?.kind, .leftUp)
    }

    func testTrimHotKeyStopKeepsUnrelatedKeys() {
        let stopFlags = KeyCodeMap.maskOption | KeyCodeMap.maskCommand
        let events = [
            ev(0, .keyDown, keyCode: 4),
            ev(0.1, .keyUp, keyCode: 4),
            ev(1.2, .keyDown, keyCode: 15, flags: stopFlags),
        ]

        let trimmed = TailTrimmer.trimHotKeyStop(
            events,
            stopKeyCode: 15,
            stopFlags: stopFlags
        )

        XCTAssertEqual(trimmed.count, 2)
        XCTAssertEqual(trimmed.first?.keyCode, 4)
    }

    func testHotKeyCaptureTrimPreservesPlainSameKeyAcceptsExtraFlagsAndRetainsIdle() {
        let stopFlags = KeyCodeMap.maskOption | KeyCodeMap.maskCommand
        let extraFlags = stopFlags | KeyCodeMap.maskShift
        let plainDown = ev(0.1, .keyDown, keyCode: 15, chars: "r")
        let plainUp = ev(0.2, .keyUp, keyCode: 15)
        let capture = RecordingCapture(
            events: [
                plainDown,
                plainUp,
                ev(1.0, .flagsChanged, keyCode: 58, flags: KeyCodeMap.maskOption),
                ev(1.1, .flagsChanged, keyCode: 55, flags: stopFlags),
                ev(1.2, .keyDown, keyCode: 15, flags: extraFlags, chars: "r"),
                ev(1.3, .keyUp, keyCode: 15, flags: extraFlags),
                ev(1.4, .flagsChanged, keyCode: 55, flags: KeyCodeMap.maskOption),
                ev(1.5, .flagsChanged, keyCode: 58),
            ],
            duration: 1.5
        )

        let trimmed = TailTrimmer.trimHotKeyStop(
            capture,
            stopKeyCode: 15,
            stopFlags: stopFlags
        )

        XCTAssertEqual(trimmed.events, [plainDown, plainUp])
        XCTAssertEqual(trimmed.duration, 1.0, accuracy: 0.000_001)
    }

    func testHotKeyCaptureTrimRemovesRepeatedStopDownsFromModifierSequenceStart() {
        let stopFlags = KeyCodeMap.maskOption | KeyCodeMap.maskCommand
        let keptEvents = [
            ev(0, .leftDown, x: 1, y: 1),
            ev(0.1, .leftUp, x: 1, y: 1),
        ]
        let capture = RecordingCapture(
            events: keptEvents + [
                ev(0.8, .flagsChanged, keyCode: 58, flags: KeyCodeMap.maskOption),
                ev(0.9, .flagsChanged, keyCode: 55, flags: stopFlags),
                ev(1.0, .keyDown, keyCode: 15, flags: stopFlags, chars: "r"),
                ev(1.1, .flagsChanged, keyCode: 55, flags: stopFlags | KeyCodeMap.maskShift),
                ev(1.2, .keyDown, keyCode: 15, flags: stopFlags | KeyCodeMap.maskShift,
                   chars: "r"),
                ev(1.3, .keyDown, keyCode: 15, flags: stopFlags, chars: "r"),
                ev(1.4, .keyUp, keyCode: 15, flags: stopFlags),
                ev(1.5, .flagsChanged, keyCode: 55, flags: KeyCodeMap.maskOption),
                ev(1.6, .flagsChanged, keyCode: 58),
            ],
            duration: 1.6
        )

        let trimmed = TailTrimmer.trimHotKeyStop(
            capture,
            stopKeyCode: 15,
            stopFlags: stopFlags
        )

        XCTAssertEqual(trimmed.events, keptEvents)
        XCTAssertEqual(trimmed.duration, 0.8, accuracy: 0.000_001)
    }

    func testHotKeyCaptureTrimRemovesRepeatedCompleteStopPairsFromModifierStart() {
        let stopFlags = KeyCodeMap.maskOption | KeyCodeMap.maskCommand
        let keptEvents = [
            ev(0, .leftDown, x: 1, y: 1),
            ev(0.1, .leftUp, x: 1, y: 1),
        ]
        let capture = RecordingCapture(
            events: keptEvents + [
                ev(0.8, .flagsChanged, keyCode: 58, flags: KeyCodeMap.maskOption),
                ev(0.9, .flagsChanged, keyCode: 55, flags: stopFlags),
                ev(1.0, .keyDown, keyCode: 15, flags: stopFlags, chars: "r"),
                ev(1.05, .keyUp, keyCode: 15, flags: stopFlags),
                ev(1.1, .keyDown, keyCode: 15, flags: stopFlags, chars: "r"),
                ev(1.15, .keyUp, keyCode: 15, flags: stopFlags),
                ev(1.2, .flagsChanged, keyCode: 55, flags: KeyCodeMap.maskOption),
                ev(1.3, .flagsChanged, keyCode: 58),
            ],
            duration: 1.3
        )

        let trimmed = TailTrimmer.trimHotKeyStop(
            capture,
            stopKeyCode: 15,
            stopFlags: stopFlags
        )

        XCTAssertEqual(trimmed.events, keptEvents)
        XCTAssertEqual(trimmed.duration, 0.8, accuracy: 0.000_001)
    }

    func testHotKeyTrimAcceptsModifierReleaseBeforeStopKeyUp() {
        let stopFlags = KeyCodeMap.maskOption | KeyCodeMap.maskCommand
        let keptEvents = [
            ev(0, .leftDown, x: 1, y: 1),
            ev(0.1, .leftUp, x: 1, y: 1),
        ]
        let capture = RecordingCapture(
            events: keptEvents + [
                ev(0.8, .flagsChanged, keyCode: 58, flags: KeyCodeMap.maskOption),
                ev(0.9, .flagsChanged, keyCode: 55, flags: stopFlags),
                ev(1.0, .keyDown, keyCode: 15, flags: stopFlags, chars: "r"),
                ev(1.1, .flagsChanged, keyCode: 55, flags: KeyCodeMap.maskOption),
                ev(1.2, .flagsChanged, keyCode: 58),
                ev(1.3, .keyUp, keyCode: 15),
            ],
            duration: 1.3
        )

        let trimmed = TailTrimmer.trimHotKeyStop(
            capture,
            stopKeyCode: 15,
            stopFlags: stopFlags
        )

        XCTAssertEqual(trimmed.events, keptEvents)
        XCTAssertEqual(trimmed.duration, 0.8, accuracy: 0.000_001)
    }

    func testHotKeyTrimStopsAtReleasedEarlierModifierGesture() {
        let stopFlags = KeyCodeMap.maskOption | KeyCodeMap.maskCommand
        let keptEvents = [
            ev(0, .leftDown, x: 1, y: 1),
            ev(0.1, .leftUp, x: 1, y: 1),
            ev(0.5, .flagsChanged, keyCode: 58, flags: KeyCodeMap.maskOption),
            ev(0.6, .flagsChanged, keyCode: 58),
        ]
        let capture = RecordingCapture(
            events: keptEvents + [
                ev(0.8, .flagsChanged, keyCode: 58, flags: KeyCodeMap.maskOption),
                ev(0.9, .flagsChanged, keyCode: 55, flags: stopFlags),
                ev(1.0, .keyDown, keyCode: 15, flags: stopFlags, chars: "r"),
                ev(1.1, .keyUp, keyCode: 15, flags: stopFlags),
                ev(1.2, .flagsChanged, keyCode: 55, flags: KeyCodeMap.maskOption),
                ev(1.3, .flagsChanged, keyCode: 58),
            ],
            duration: 1.3
        )

        let trimmed = TailTrimmer.trimHotKeyStop(
            capture,
            stopKeyCode: 15,
            stopFlags: stopFlags
        )

        XCTAssertEqual(trimmed.events, keptEvents)
        XCTAssertEqual(trimmed.duration, 0.8, accuracy: 0.000_001)
    }

    func testHotKeyCaptureTrimWithoutMatchingChordIsUnchanged() {
        let stopFlags = KeyCodeMap.maskOption | KeyCodeMap.maskCommand
        let capture = RecordingCapture(
            events: [
                ev(0.1, .keyDown, keyCode: 15, flags: KeyCodeMap.maskCommand, chars: "r"),
                ev(0.2, .keyUp, keyCode: 15, flags: KeyCodeMap.maskCommand),
            ],
            duration: 0.5
        )

        XCTAssertEqual(
            TailTrimmer.trimHotKeyStop(
                capture,
                stopKeyCode: 15,
                stopFlags: stopFlags
            ),
            capture
        )
    }

    func testHotKeyCaptureTrimRequiresMatchingKeyCode() {
        let stopFlags = KeyCodeMap.maskOption | KeyCodeMap.maskCommand
        let capture = RecordingCapture(
            events: [
                ev(0.1, .keyDown, keyCode: 14, flags: stopFlags, chars: "e"),
                ev(0.2, .keyUp, keyCode: 14, flags: stopFlags),
            ],
            duration: 0.5
        )

        XCTAssertEqual(
            TailTrimmer.trimHotKeyStop(
                capture,
                stopKeyCode: 15,
                stopFlags: stopFlags
            ),
            capture
        )
    }

    func testCutoffTrimsPrefixAndSetsExactDuration() {
        let events = [
            ev(0.1, .mouseMove, x: 1, y: 1),
            ev(0.2, .leftDown, x: 2, y: 2),
            ev(0.3, .leftUp, x: 2, y: 2),
            ev(2.0, .mouseMove, x: 9, y: 9),
        ]
        let capture = RecordingCapture(events: events, duration: 3)

        let trimmed = TailTrimmer.trim(
            capture,
            at: RecordingCutoff(eventCount: 3, duration: 1.25)
        )

        XCTAssertEqual(trimmed.events, Array(events.prefix(3)))
        XCTAssertEqual(trimmed.duration, 1.25, accuracy: 0.000_001)
    }

    func testCutoffClampsEventCountAndSanitizesDuration() {
        let events = [
            ev(0.1, .mouseMove, x: 1, y: 1),
            ev(0.2, .mouseMove, x: 2, y: 2),
        ]
        let capture = RecordingCapture(events: events, duration: 1)

        let tooLarge = TailTrimmer.trim(
            capture,
            at: RecordingCutoff(eventCount: 20, duration: 0.75)
        )
        XCTAssertEqual(tooLarge.events, events)
        XCTAssertEqual(tooLarge.duration, 0.75, accuracy: 0.000_001)

        let negative = TailTrimmer.trim(
            capture,
            at: RecordingCutoff(eventCount: -2, duration: -.infinity)
        )
        XCTAssertTrue(negative.events.isEmpty)
        XCTAssertEqual(negative.duration, 0)
    }

    func testTrimMenuBarStop() {
        let events = [
            ev(0, .leftDown, x: 100, y: 500),
            ev(0.1, .leftUp, x: 100, y: 500),
            ev(0.5, .mouseMove, x: 200, y: 300),
            ev(0.6, .mouseMove, x: 500, y: 50),
            ev(0.7, .mouseMove, x: 800, y: 10),
            ev(0.8, .leftDown, x: 800, y: 10),
            ev(0.9, .leftUp, x: 800, y: 10),
        ]
        let trimmed = TailTrimmer.trimMenuBarStop(events)
        XCTAssertEqual(trimmed.count, 2)
        XCTAssertEqual(trimmed.last?.kind, .leftUp)
        XCTAssertEqual(trimmed.last?.x, 100)
    }

    func testTrimMenuBarStopNoTrailingClick() {
        let events = [ev(0, .mouseMove, x: 1, y: 1)]
        XCTAssertEqual(TailTrimmer.trimMenuBarStop(events).count, 1)
    }

    func testEmpty() {
        XCTAssertTrue(
            TailTrimmer.trimHotKeyStop([], stopKeyCode: 15, stopFlags: 0).isEmpty
        )
        XCTAssertTrue(TailTrimmer.trimMenuBarStop([]).isEmpty)

        let emptyCapture = RecordingCapture(events: [], duration: 0.2)
        XCTAssertEqual(
            TailTrimmer.trimHotKeyStop(
                emptyCapture,
                stopKeyCode: 15,
                stopFlags: 0
            ),
            emptyCapture
        )
    }
}

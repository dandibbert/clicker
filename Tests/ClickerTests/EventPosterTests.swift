import CoreGraphics
import XCTest
@testable import Clicker
import ClickerCore

final class EventPosterTests: XCTestCase {
    func testKeyDownConstructionPreservesAutorepeatAndKeyboardPayload() throws {
        for isRepeat in [false, true] {
            let event = try XCTUnwrap(EventPoster.makeEvent(for: .keyDown(
                keyCode: 4,
                flags: KeyCodeMap.maskShift,
                chars: "A🙂界🚀Z",
                isRepeat: isRepeat
            )))

            XCTAssertEqual(event.type, .keyDown)
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), 4)
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventAutorepeat), isRepeat ? 1 : 0)
            XCTAssertEqual(event.flags.rawValue, KeyCodeMap.maskShift)
            XCTAssertEqual(unicodeString(from: event), "A🙂界🚀Z")
            XCTAssertEqual(
                event.getIntegerValueField(.eventSourceUserData),
                EventRecorder.syntheticMarker
            )
        }
    }

    func testShortcutConstructionPreservesAutorepeatWithoutUnicodeOverride() throws {
        let event = try XCTUnwrap(EventPoster.makeEvent(for: .keyDown(
            keyCode: 8,
            flags: KeyCodeMap.maskCommand,
            chars: "",
            isRepeat: true
        )))

        XCTAssertEqual(event.type, .keyDown)
        XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), 8)
        XCTAssertEqual(event.getIntegerValueField(.keyboardEventAutorepeat), 1)
        XCTAssertEqual(event.flags.rawValue, KeyCodeMap.maskCommand)
    }

    func testKeyDownDefaultsToNonrepeat() throws {
        let event = try XCTUnwrap(EventPoster.makeEvent(for: .keyDown(
            keyCode: 0,
            flags: 0,
            chars: "a"
        )))

        XCTAssertEqual(event.getIntegerValueField(.keyboardEventAutorepeat), 0)
    }

    func testConstructionMarksEveryActionWithoutPostingIt() throws {
        let flags = KeyCodeMap.maskShift
        let actions: [(StepAction, CGEventType)] = [
            (.mouseMove(x: 1, y: 2, flags: flags), .mouseMoved),
            (.mouseDown(x: 1, y: 2, button: .left, clickCount: 2, flags: flags), .leftMouseDown),
            (.mouseDown(x: 1, y: 2, button: .right, clickCount: 2, flags: flags), .rightMouseDown),
            (.mouseUp(x: 1, y: 2, button: .left, clickCount: 2, flags: flags), .leftMouseUp),
            (.mouseUp(x: 1, y: 2, button: .right, clickCount: 2, flags: flags), .rightMouseUp),
            (.mouseDrag(x: 1, y: 2, button: .left, flags: flags), .leftMouseDragged),
            (.mouseDrag(x: 1, y: 2, button: .right, flags: flags), .rightMouseDragged),
            (.keyDown(keyCode: 4, flags: flags, chars: "h"), .keyDown),
            (.keyUp(keyCode: 4, flags: flags), .keyUp),
            (.scroll(x: 1, y: 2, dx: 3, dy: 4, flags: flags), .scrollWheel),
        ]

        for (action, type) in actions {
            let event = try XCTUnwrap(EventPoster.makeEvent(for: action))
            XCTAssertEqual(event.type, type)
            XCTAssertEqual(event.flags.rawValue, flags)
            XCTAssertEqual(
                event.getIntegerValueField(.eventSourceUserData),
                EventRecorder.syntheticMarker
            )
            switch action {
            case .mouseDown, .mouseUp:
                XCTAssertEqual(event.getIntegerValueField(.mouseEventClickState), 2)
                XCTAssertEqual(event.location, CGPoint(x: 1, y: 2))
            case .mouseMove, .mouseDrag, .scroll:
                XCTAssertEqual(event.location, CGPoint(x: 1, y: 2))
            case .keyDown, .keyUp:
                XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), 4)
            }
        }
    }

    func testScrollDeltaMapsNonFiniteValuesToZero() {
        XCTAssertEqual(EventPoster.scrollDelta(.nan), 0)
        XCTAssertEqual(EventPoster.scrollDelta(.infinity), 0)
        XCTAssertEqual(EventPoster.scrollDelta(-.infinity), 0)
    }

    func testScrollDeltaTruncatesAndClampsToInt32Range() {
        XCTAssertEqual(EventPoster.scrollDelta(12.9), 12)
        XCTAssertEqual(EventPoster.scrollDelta(-12.9), -12)
        XCTAssertEqual(EventPoster.scrollDelta(Double(Int32.max) + 1_000), Int32.max)
        XCTAssertEqual(EventPoster.scrollDelta(Double(Int32.min) - 1_000), Int32.min)
    }

    private func unicodeString(from event: CGEvent) -> String {
        var length = 0
        event.keyboardGetUnicodeString(
            maxStringLength: 0,
            actualStringLength: &length,
            unicodeString: nil
        )
        var units = [UniChar](repeating: 0, count: max(0, length))
        event.keyboardGetUnicodeString(
            maxStringLength: units.count,
            actualStringLength: &length,
            unicodeString: &units
        )
        return String(decoding: units.prefix(min(units.count, max(0, length))), as: UTF16.self)
    }
}

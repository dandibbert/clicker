import XCTest
@testable import Clicker
import ClickerCore

final class PressedInputTrackerTests: XCTestCase {
    func testNormalKeyUpRemovesHeldKey() {
        var tracker = PressedInputTracker()

        tracker.observe(.keyDown(keyCode: 4, flags: 11, chars: "h"))
        tracker.observe(.keyUp(keyCode: 4, flags: 12))

        XCTAssertTrue(tracker.releaseActions().isEmpty)
    }

    func testRepeatedKeyDownProducesOneReleaseWithLatestFlags() {
        var tracker = PressedInputTracker()

        tracker.observe(.keyDown(keyCode: 4, flags: 11, chars: "h"))
        tracker.observe(.keyDown(keyCode: 4, flags: 12, chars: "h"))

        XCTAssertEqual(tracker.releaseActions(), [
            .keyUp(keyCode: 4, flags: 12),
        ])
        XCTAssertTrue(tracker.releaseActions().isEmpty)
    }

    func testMouseUpRemovesHeldButton() {
        var tracker = PressedInputTracker()

        tracker.observe(.mouseDown(
            x: 10,
            y: 20,
            button: .left,
            clickCount: 1,
            flags: 21
        ))
        tracker.observe(.mouseUp(
            x: 11,
            y: 22,
            button: .left,
            clickCount: 1,
            flags: 22
        ))

        XCTAssertTrue(tracker.releaseActions().isEmpty)
    }

    func testReleaseActionsUseLatestDragLocationAndDeterministicOrder() {
        var tracker = PressedInputTracker()

        tracker.observe(.mouseDown(
            x: 30,
            y: 40,
            button: .right,
            clickCount: 2,
            flags: 31
        ))
        tracker.observe(.keyDown(keyCode: 9, flags: 41, chars: "v"))
        tracker.observe(.keyDown(keyCode: 4, flags: 42, chars: "h"))
        tracker.observe(.mouseDown(
            x: 10,
            y: 20,
            button: .left,
            clickCount: 1,
            flags: 32
        ))
        tracker.observe(.mouseDrag(
            x: 15,
            y: 25,
            button: .left,
            flags: 33
        ))

        XCTAssertEqual(tracker.releaseActions(), [
            .keyUp(keyCode: 4, flags: 42),
            .keyUp(keyCode: 9, flags: 41),
            .mouseUp(x: 15, y: 25, button: .left, clickCount: 1, flags: 33),
            .mouseUp(x: 30, y: 40, button: .right, clickCount: 2, flags: 31),
        ])
        XCTAssertTrue(tracker.releaseActions().isEmpty)
    }
}

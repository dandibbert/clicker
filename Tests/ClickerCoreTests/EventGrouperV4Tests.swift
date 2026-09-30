import XCTest
@testable import ClickerCore

final class EventGrouperV4Tests: XCTestCase {
    private func event(
        _ t: TimeInterval,
        _ kind: EventKind,
        x: Double = 0,
        y: Double = 0,
        keyCode: UInt16 = 0,
        flags: UInt64 = 0,
        chars: String = "",
        isRepeat: Bool = false,
        dx: Double = 0,
        dy: Double = 0
    ) -> RecordedEvent {
        RecordedEvent(
            t: t,
            kind: kind,
            x: x,
            y: y,
            keyCode: keyCode,
            flags: flags,
            chars: chars,
            clickCount: 1,
            scrollDX: dx,
            scrollDY: dy,
            isRepeat: isRepeat
        )
    }

    func testGroupingAssignsAbsoluteOffsetsToActionsAndWaits() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                event(0.2, .leftDown, x: 1, y: 2),
                event(0.3, .leftUp, x: 1, y: 2),
                event(1, .rightDown, x: 3, y: 4),
                event(1.1, .rightUp, x: 3, y: 4),
            ],
            duration: 1.1
        ))

        XCTAssertEqual(timeline.blocks.count, 3)
        for (actual, expected) in zip(timeline.blocks.map(\.startOffset), [0.2, 0.3, 1]) {
            XCTAssertEqual(actual, expected, accuracy: 0.000_001)
        }
        guard case .wait(let wait) = timeline.blocks[1] else { return XCTFail() }
        XCTAssertEqual(wait.duration, 0.7, accuracy: 0.000_001)
        XCTAssertEqual(timeline.blocks.map(\.delayBefore), [0, 0, 0])
        XCTAssertEqual(timeline.blocks.map(\.overlapBefore), [0, 0, 0])
    }

    func testEqualTimestampCaptureOrderSurvivesGroupingAndExpansion() {
        let command = KeyCodeMap.maskCommand
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                event(0, .keyDown, keyCode: 8, flags: command, chars: "c"),
                event(0, .leftDown, x: 1, y: 2),
                event(0, .leftUp, x: 3, y: 4),
                event(0, .keyUp, keyCode: 8, flags: command),
            ],
            duration: 0
        ))

        let plan = BlockExpander.plan(blocks: timeline.blocks)

        XCTAssertEqual(plan.steps.map(\.ordinal), [0, 1, 2, 3])
        XCTAssertEqual(plan.steps.map(\.action), [
            .keyDown(keyCode: 8, flags: command, chars: ""),
            .mouseDown(x: 1, y: 2, button: .left, clickCount: 1, flags: 0),
            .mouseUp(x: 3, y: 4, button: .left, clickCount: 1, flags: 0),
            .keyUp(keyCode: 8, flags: command),
        ])
    }

    func testAutorepeatGroupingKeepsOnePhysicalReleaseAtItsCapturedTime() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                event(0, .keyDown, keyCode: 0, chars: "a"),
                event(0.1, .keyDown, keyCode: 0, chars: "a", isRepeat: true),
                event(0.2, .keyDown, keyCode: 0, chars: "a", isRepeat: true),
                event(0.5, .keyUp, keyCode: 0, flags: 7),
            ],
            duration: 0.5
        ))

        guard case .typeText(let typeText) = timeline.blocks.first else { return XCTFail() }
        XCTAssertEqual(typeText.text, "aaa")
        XCTAssertEqual(typeText.keystrokes.map(\.isRepeat), [false, true, true])
        XCTAssertEqual(typeText.keystrokes.map(\.downOrdinal), [0, 1, 2])
        XCTAssertEqual(typeText.keystrokes.map(\.upOrdinal), [3, 3, 3])
        XCTAssertEqual(typeText.keystrokes.map(\.upT), [0.5, 0.5, 0.5])

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        XCTAssertEqual(plan.steps.map(\.t), [0, 0.1, 0.2, 0.5])
        XCTAssertEqual(plan.steps.map(\.ordinal), [0, 1, 2, 3])
        XCTAssertEqual(plan.steps.map(\.action), [
            .keyDown(keyCode: 0, flags: 0, chars: "a"),
            .keyDown(keyCode: 0, flags: 0, chars: "a", isRepeat: true),
            .keyDown(keyCode: 0, flags: 0, chars: "a", isRepeat: true),
            .keyUp(keyCode: 0, flags: 7),
        ])
        XCTAssertEqual(plan.steps.filter { step in
            if case .keyUp = step.action { return true }
            return false
        }.count, 1)
    }

    func testDanglingAutorepeatSynthesizesOneReleaseAfterTheLastRepeat() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                event(0, .keyDown, keyCode: 0, chars: "a"),
                event(0.1, .keyDown, keyCode: 0, chars: "a", isRepeat: true),
                event(0.2, .keyDown, keyCode: 0, chars: "a", isRepeat: true),
            ],
            duration: 0.2
        ))

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        XCTAssertEqual(plan.steps.map(\.t), [0, 0.1, 0.2, 0.22])
        XCTAssertEqual(plan.steps.filter { step in
            if case .keyUp = step.action { return true }
            return false
        }.count, 1)
        guard case .keyUp(keyCode: 0, flags: 0) = plan.steps.last?.action else {
            return XCTFail("expected one fallback release after the final repeat")
        }
    }

    func testAutorepeatShortcutAlsoEmitsOnlyOneRelease() {
        let command = KeyCodeMap.maskCommand
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                event(0, .keyDown, keyCode: 8, flags: command, chars: "c"),
                event(0.1, .keyDown, keyCode: 8, flags: command, chars: "c", isRepeat: true),
                event(0.3, .keyUp, keyCode: 8, flags: command),
            ],
            duration: 0.3
        ))

        XCTAssertEqual(timeline.blocks.count, 2)
        guard case .shortcut(let initial) = timeline.blocks[0],
              case .shortcut(let repeated) = timeline.blocks[1] else { return XCTFail() }
        XCTAssertFalse(initial.isRepeat)
        XCTAssertTrue(repeated.isRepeat)

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        XCTAssertEqual(plan.steps.map(\.t), [0, 0.1, 0.3])
        XCTAssertEqual(plan.steps.map(\.ordinal), [0, 1, 2])
        XCTAssertEqual(plan.steps.map(\.action), [
            .keyDown(keyCode: 8, flags: command, chars: ""),
            .keyDown(keyCode: 8, flags: command, chars: "", isRepeat: true),
            .keyUp(keyCode: 8, flags: command),
        ])
        XCTAssertEqual(plan.steps.filter { step in
            if case .keyUp = step.action { return true }
            return false
        }.count, 1)
    }

    func testRecordingBeginningWithAutorepeatPreservesItsFlagAndOneRelease() {
        for flags in [UInt64(0), KeyCodeMap.maskCommand] {
            let timeline = EventGrouper.group(RecordingCapture(
                events: [
                    event(0, .keyDown, keyCode: 0, flags: flags, chars: "a", isRepeat: true),
                    event(0.1, .keyDown, keyCode: 0, flags: flags, chars: "a", isRepeat: true),
                    event(0.3, .keyUp, keyCode: 0, flags: flags),
                ],
                duration: 0.3
            ))

            let plan = BlockExpander.plan(blocks: timeline.blocks)
            let chars = flags == 0 ? "a" : ""
            XCTAssertEqual(plan.steps.map(\.t), [0, 0.1, 0.3])
            XCTAssertEqual(plan.steps.map(\.action), [
                .keyDown(keyCode: 0, flags: flags, chars: chars, isRepeat: true),
                .keyDown(keyCode: 0, flags: flags, chars: chars, isRepeat: true),
                .keyUp(keyCode: 0, flags: flags),
            ])
        }
    }
}

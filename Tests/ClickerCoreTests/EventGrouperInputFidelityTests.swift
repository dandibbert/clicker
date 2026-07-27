import XCTest
@testable import ClickerCore

final class EventGrouperInputFidelityTests: XCTestCase {
    private func ev(
        _ t: TimeInterval,
        _ kind: EventKind,
        x: Double = 0,
        y: Double = 0,
        keyCode: UInt16 = 0,
        flags: UInt64 = 0,
        chars: String = "",
        clicks: Int = 1,
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
            clickCount: clicks,
            scrollDX: dx,
            scrollDY: dy
        )
    }

    func testOverlappingShortcutsMatchOutstandingKeyUpsDeterministically() throws {
        let command = KeyCodeMap.maskCommand
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0, .keyDown, keyCode: 8, flags: command | 1, chars: "c"),
                ev(0.1, .keyDown, keyCode: 9, flags: command | 2, chars: "v"),
                ev(0.3, .keyUp, keyCode: 8, flags: command | 3),
                ev(0.5, .keyUp, keyCode: 9, flags: 4),
            ],
            duration: 0.5
        ))

        XCTAssertEqual(timeline.blocks.count, 2)
        guard case .shortcut(let copy) = timeline.blocks[0],
              case .shortcut(let paste) = timeline.blocks[1] else {
            return XCTFail("expected two shortcuts, got \(timeline.blocks)")
        }
        XCTAssertEqual(copy.keyCode, 8)
        XCTAssertEqual(copy.flags, command | 1)
        XCTAssertEqual(copy.upFlags, command | 3)
        XCTAssertEqual(copy.duration, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(paste.keyCode, 9)
        XCTAssertEqual(paste.flags, command | 2)
        XCTAssertEqual(paste.upFlags, 4)
        XCTAssertEqual(paste.duration, 0.4, accuracy: 0.000_001)

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        XCTAssertEqual(plan.steps.map(\.action), [
            .keyDown(keyCode: 8, flags: command | 1, chars: ""),
            .keyDown(keyCode: 9, flags: command | 2, chars: ""),
            .keyUp(keyCode: 8, flags: command | 3),
            .keyUp(keyCode: 9, flags: 4),
        ])
        XCTAssertEqual(plan.steps.map(\.t), [0, 0.1, 0.3, 0.5])
        XCTAssertEqual(plan.duration, 0.5, accuracy: 0.000_001)

        let data = try JSONEncoder().encode(Script(name: "Shortcuts", blocks: timeline.blocks))
        let decoded = try JSONDecoder().decode(Script.self, from: data)
        let decodedPlan = BlockExpander.plan(for: decoded)
        XCTAssertEqual(decodedPlan.steps.map(\.action), plan.steps.map(\.action))
        XCTAssertEqual(decodedPlan.steps.map(\.t), [0, 0.1, 0.3, 0.5])
        XCTAssertEqual(decodedPlan.duration, 0.5, accuracy: 0.000_001)
    }

    func testContainedCrossInputBlocksReplayAtAbsoluteOverlapTimes() {
        let command = KeyCodeMap.maskCommand
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0, .keyDown, keyCode: 8, flags: command, chars: "c"),
                ev(0.1, .leftDown, x: 1, y: 2, flags: 11),
                ev(0.2, .scroll, x: 3, y: 4, flags: 21, dy: -2),
                ev(0.3, .leftUp, x: 5, y: 6, flags: 12),
                ev(0.4, .keyDown, keyCode: 9, flags: command, chars: "v"),
                ev(0.5, .keyUp, keyCode: 9, flags: 31),
                ev(0.8, .keyUp, keyCode: 8, flags: 32),
            ],
            duration: 0.8
        ))

        XCTAssertEqual(timeline.blocks.count, 4)
        XCTAssertEqual(timeline.blocks.map(\.startOffset), [0, 0.1, 0.2, 0.4])
        XCTAssertEqual(timeline.blocks.map(\.delayBefore), [0, 0, 0, 0])
        XCTAssertEqual(timeline.blocks.map(\.overlapBefore), [0, 0, 0, 0])

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        XCTAssertEqual(plan.steps.map(\.action), [
            .keyDown(keyCode: 8, flags: command, chars: ""),
            .mouseDown(x: 1, y: 2, button: .left, clickCount: 1, flags: 11),
            .scroll(x: 3, y: 4, dx: 0, dy: -2, flags: 21),
            .mouseUp(x: 5, y: 6, button: .left, clickCount: 1, flags: 12),
            .keyDown(keyCode: 9, flags: command, chars: ""),
            .keyUp(keyCode: 9, flags: 31),
            .keyUp(keyCode: 8, flags: 32),
        ])
        for (actual, expected) in zip(
            plan.steps.map(\.t),
            [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.8]
        ) {
            XCTAssertEqual(actual, expected, accuracy: 0.000_001)
        }
        XCTAssertEqual(plan.duration, 0.8, accuracy: 0.000_001)
    }

    func testPrintableKeyUpMatchesAcrossUnrelatedMouseAndScrollEvents() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0, .keyDown, keyCode: 0, flags: 11, chars: "a"),
                ev(0.1, .mouseMove, x: 10, y: 20),
                ev(0.2, .scroll, x: 30, y: 40, dy: -3),
                ev(0.4, .keyUp, keyCode: 0, flags: 12),
            ],
            duration: 0.4
        ))

        guard case .typeText(let typeText) = timeline.blocks.first else {
            return XCTFail("expected type block, got \(timeline.blocks)")
        }
        XCTAssertEqual(typeText.keystrokes.count, 1)
        XCTAssertEqual(typeText.keystrokes[0].upT, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(typeText.keystrokes[0].upFlags, 12)
        XCTAssertEqual(typeText.duration, 0.4, accuracy: 0.000_001)

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        XCTAssertEqual(plan.steps.map(\.action), [
            .keyDown(keyCode: 0, flags: 11, chars: "a"),
            .mouseMove(x: 10, y: 20, flags: 0),
            .scroll(x: 30, y: 40, dx: 0, dy: -3, flags: 0),
            .keyUp(keyCode: 0, flags: 12),
        ])
        XCTAssertEqual(plan.steps.count, 4)
        for (actual, expected) in zip(plan.steps.map(\.t), [0, 0.1, 0.2, 0.4]) {
            XCTAssertEqual(actual, expected, accuracy: 0.000_001)
        }
        XCTAssertEqual(plan.duration, 0.4, accuracy: 0.000_001)
    }

    func testMergedScrollKeepsEverySampleLocationThroughModelAndExpansion() throws {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0.25, .scroll, x: 100, y: 200, flags: 11, dx: 1.5, dy: -2.5),
                ev(0.4, .scroll, x: 300, y: 400, flags: 12, dx: -3.5, dy: 4.5),
            ],
            duration: 0.4
        ))

        guard case .scroll(let scroll) = timeline.blocks.first else { return XCTFail() }
        let encodedStep = try JSONEncoder().encode(scroll.steps[1])
        let stepObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedStep) as? [String: Any]
        )
        XCTAssertEqual(stepObject["x"] as? Double, 300)
        XCTAssertEqual(stepObject["y"] as? Double, 400)

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        XCTAssertEqual(plan.steps.map(\.action), [
            .scroll(x: 100, y: 200, dx: 1.5, dy: -2.5, flags: 11),
            .scroll(x: 300, y: 400, dx: -3.5, dy: 4.5, flags: 12),
        ])
    }

    func testInterruptedDragKeepsSamplesAcrossUnrelatedEventsBeforeSafeRelease() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0, .leftDown, x: 1, y: 2, flags: 11),
                ev(0.1, .leftDrag, x: 3, y: 4, flags: 12),
                ev(0.15, .scroll, x: 20, y: 30, flags: 21, dy: -2),
                ev(0.2, .leftDrag, x: 5, y: 6, flags: 13),
            ],
            duration: 0.2
        ))

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        XCTAssertEqual(plan.steps.map(\.action), [
            .mouseDown(x: 1, y: 2, button: .left, clickCount: 1, flags: 11),
            .mouseDrag(x: 3, y: 4, button: .left, flags: 12),
            .scroll(x: 20, y: 30, dx: 0, dy: -2, flags: 21),
            .mouseDrag(x: 5, y: 6, button: .left, flags: 13),
            .mouseUp(x: 5, y: 6, button: .left, clickCount: 1, flags: 13),
        ])
        XCTAssertEqual(plan.steps.count, 5)
        for (actual, expected) in zip(plan.steps.map(\.t), [0, 0.1, 0.15, 0.2, 0.2]) {
            XCTAssertEqual(actual, expected, accuracy: 0.000_001)
        }
        XCTAssertEqual(plan.duration, 0.2, accuracy: 0.000_001)
    }

    func testTwoPointInterruptedDragReplaysFinalDragBeforeSafeRelease() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(1, .leftDown, x: 1, y: 2, flags: 11),
                ev(1.25, .leftDrag, x: 3, y: 4, flags: 12),
            ],
            duration: 1.25
        ))

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        XCTAssertEqual(plan.steps.map(\.action), [
            .mouseDown(x: 1, y: 2, button: .left, clickCount: 1, flags: 11),
            .mouseDrag(x: 3, y: 4, button: .left, flags: 12),
            .mouseUp(x: 3, y: 4, button: .left, clickCount: 1, flags: 12),
        ])
        XCTAssertEqual(plan.steps.map(\.t), [1, 1.25, 1.25])
    }
}

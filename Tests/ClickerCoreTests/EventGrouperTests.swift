import XCTest
@testable import ClickerCore

final class EventGrouperTests: XCTestCase {
    func ev(_ t: TimeInterval, _ kind: EventKind, x: Double = 0, y: Double = 0,
            keyCode: UInt16 = 0, flags: UInt64 = 0, chars: String = "",
            clicks: Int = 1, dx: Double = 0, dy: Double = 0) -> RecordedEvent {
        RecordedEvent(t: t, kind: kind, x: x, y: y, keyCode: keyCode, flags: flags,
                      chars: chars, clickCount: clicks, scrollDX: dx, scrollDY: dy)
    }

    func testEmptyInput() {
        XCTAssertTrue(EventGrouper.group([]).isEmpty)
    }

    func testSimpleClick() {
        let blocks = EventGrouper.group([
            ev(0, .leftDown, x: 100, y: 200),
            ev(0.1, .leftUp, x: 100, y: 200),
        ])
        guard case .click(let click) = blocks.first else {
            return XCTFail("expected click, got \(blocks)")
        }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(click.x, 100)
        XCTAssertEqual(click.y, 200)
        XCTAssertEqual(click.button, .left)
        XCTAssertEqual(click.clickCount, 1)
        XCTAssertEqual(click.duration, 0.1, accuracy: 0.000_001)
    }

    func testDoubleClickKeepsClickCount() {
        let blocks = EventGrouper.group([
            ev(0, .leftDown, x: 10, y: 10, clicks: 1),
            ev(0.05, .leftUp, x: 10, y: 10, clicks: 1),
            ev(0.2, .leftDown, x: 10, y: 10, clicks: 2),
            ev(0.25, .leftUp, x: 10, y: 10, clicks: 2),
        ])
        XCTAssertEqual(blocks.count, 2)
        guard case .click(let secondClick) = blocks[1] else { return XCTFail() }
        XCTAssertEqual(secondClick.clickCount, 2)
    }

    func testMouseMoveMerged() {
        let blocks = EventGrouper.group([
            ev(0, .mouseMove, x: 0, y: 0),
            ev(0.1, .mouseMove, x: 50, y: 50),
            ev(0.2, .mouseMove, x: 100, y: 100),
        ])
        guard case .move(let move) = blocks.first else {
            return XCTFail("expected move, got \(blocks)")
        }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(move.points.count, 3)
        XCTAssertEqual(move.points.first?.x, 0)
        XCTAssertEqual(move.points.last?.x, 100)
        XCTAssertEqual(move.duration, 0.2, accuracy: 0.001)
        XCTAssertEqual(move.points.first?.t, 0)
        XCTAssertEqual(move.points.last?.t ?? -1, 0.2, accuracy: 0.001)
    }

    func testDrag() {
        let blocks = EventGrouper.group([
            ev(0, .leftDown, x: 100, y: 100),
            ev(0.1, .leftDrag, x: 150, y: 150),
            ev(0.2, .leftDrag, x: 200, y: 200),
            ev(0.3, .leftUp, x: 200, y: 200),
        ])
        guard case .drag(let drag) = blocks.first else {
            return XCTFail("expected drag, got \(blocks)")
        }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(drag.button, .left)
        XCTAssertEqual(drag.points.first?.x, 100)
        XCTAssertEqual(drag.points.last?.x, 200)
        XCTAssertEqual(drag.duration, 0.3, accuracy: 0.001)
    }

    func testScrollMerged() {
        let blocks = EventGrouper.group([
            ev(0, .scroll, x: 500, y: 400, dy: -3),
            ev(0.05, .scroll, x: 500, y: 400, dy: -5),
        ])
        guard case .scroll(let scroll) = blocks.first else {
            return XCTFail("expected scroll, got \(blocks)")
        }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(scroll.steps.count, 2)
        XCTAssertEqual(scroll.steps[1].dy, -5)
    }

    func testTypingMerged() {
        let blocks = EventGrouper.group([
            ev(0, .keyDown, keyCode: 4, chars: "h"),
            ev(0.05, .keyUp, keyCode: 4),
            ev(0.1, .keyDown, keyCode: 14, chars: "e"),
            ev(0.15, .keyUp, keyCode: 14),
        ])
        guard case .typeText(let typeText) = blocks.first else {
            return XCTFail("expected typeText, got \(blocks)")
        }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(typeText.text, "he")
        XCTAssertEqual(typeText.keystrokes.count, 2)
    }

    func testShortcutSeparate() {
        let blocks = EventGrouper.group([
            ev(0, .keyDown, keyCode: 8, flags: KeyCodeMap.maskCommand, chars: "c"),
            ev(0.05, .keyUp, keyCode: 8, flags: KeyCodeMap.maskCommand),
        ])
        guard case .shortcut(let shortcut) = blocks.first else {
            return XCTFail("expected shortcut, got \(blocks)")
        }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(shortcut.keyCode, 8)
        XCTAssertEqual(shortcut.flags & KeyCodeMap.maskCommand, KeyCodeMap.maskCommand)
    }

    func testShiftTypingIsText() {
        let blocks = EventGrouper.group([
            ev(0, .keyDown, keyCode: 4, flags: KeyCodeMap.maskShift, chars: "H"),
            ev(0.05, .keyUp, keyCode: 4, flags: KeyCodeMap.maskShift),
        ])
        guard case .typeText(let typeText) = blocks.first else {
            return XCTFail("expected typeText, got \(blocks)")
        }
        XCTAssertEqual(typeText.text, "H")
        XCTAssertEqual(typeText.keystrokes.first?.downFlags, KeyCodeMap.maskShift)
        XCTAssertEqual(typeText.keystrokes.first?.upFlags, KeyCodeMap.maskShift)
    }

    func testWaitInserted() {
        let blocks = EventGrouper.group([
            ev(0, .leftDown, x: 1, y: 1),
            ev(0.05, .leftUp, x: 1, y: 1),
            ev(2.05, .leftDown, x: 9, y: 9),
            ev(2.1, .leftUp, x: 9, y: 9),
        ])
        XCTAssertEqual(blocks.count, 3)
        guard case .wait(let wait) = blocks[1] else {
            return XCTFail("expected wait, got \(blocks)")
        }
        XCTAssertEqual(wait.duration, 2.0, accuracy: 0.001)
    }

    func testSmallGapHasNoVisibleWaitAndIsPreservedByAbsoluteStart() {
        let blocks = EventGrouper.group([
            ev(0, .leftDown, x: 1, y: 1),
            ev(0.05, .leftUp, x: 1, y: 1),
            ev(0.3, .leftDown, x: 9, y: 9),
            ev(0.35, .leftUp, x: 9, y: 9),
        ])

        XCTAssertEqual(blocks.count, 2)
        XCTAssertFalse(blocks.contains { block in
            if case .wait = block { return true }
            return false
        })
        guard case .click(let secondClick) = blocks[1] else { return XCTFail() }
        XCTAssertEqual(secondClick.startOffset, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(secondClick.delayBefore, 0, accuracy: 0.000_001)

        let plan = BlockExpander.plan(blocks: blocks)
        let mouseDownTimes = plan.steps.compactMap { step -> TimeInterval? in
            if case .mouseDown = step.action { return step.t }
            return nil
        }
        XCTAssertEqual(mouseDownTimes.count, 2)
        XCTAssertEqual(mouseDownTimes[0], 0, accuracy: 0.000_001)
        XCTAssertEqual(mouseDownTimes[1], 0.3, accuracy: 0.000_001)
    }

    func testTypingSplitByWait() {
        let blocks = EventGrouper.group([
            ev(0, .keyDown, keyCode: 4, chars: "h"),
            ev(0.05, .keyUp, keyCode: 4),
            ev(3.0, .keyDown, keyCode: 14, chars: "e"),
            ev(3.05, .keyUp, keyCode: 14),
        ])
        XCTAssertEqual(blocks.count, 3)
        guard case .typeText = blocks[0], case .wait = blocks[1], case .typeText = blocks[2]
        else { return XCTFail("got \(blocks)") }
    }

    func testMoveThenClick() {
        let blocks = EventGrouper.group([
            ev(0, .mouseMove, x: 0, y: 0),
            ev(0.1, .mouseMove, x: 100, y: 100),
            ev(0.2, .leftDown, x: 100, y: 100),
            ev(0.25, .leftUp, x: 100, y: 100),
        ])
        XCTAssertEqual(blocks.count, 2)
        guard case .move = blocks[0], case .click = blocks[1] else {
            return XCTFail("got \(blocks)")
        }
    }

    func testStandaloneFlagsChangedEmitsNoInputBlock() {
        let blocks = EventGrouper.group([
            ev(0, .flagsChanged, keyCode: 55, flags: KeyCodeMap.maskCommand),
            ev(0.1, .flagsChanged, keyCode: 55),
        ])
        XCTAssertTrue(blocks.isEmpty)
    }

    func testDanglingDownEmitsClick() {
        let blocks = EventGrouper.group([
            ev(0, .leftDown, x: 5, y: 6, flags: 7, clicks: 2),
        ])
        XCTAssertEqual(blocks.count, 1)
        guard case .click(let click) = blocks[0] else { return XCTFail("got \(blocks)") }
        XCTAssertEqual(click.duration, 0.03, accuracy: 0.000_001)
        XCTAssertEqual(click.downFlags, 7)
        XCTAssertEqual(click.upFlags, 7)
        XCTAssertEqual(click.clickCount, 2)
        XCTAssertEqual(click.upClickCount, 2)
    }

    func testInitialShortIdleBecomesFirstAbsoluteStartAndPlanTiming() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0.2, .leftDown, x: 1, y: 2),
                ev(0.3, .leftUp, x: 1, y: 2),
            ],
            duration: 0.3
        ))

        XCTAssertEqual(timeline.blocks.count, 1)
        XCTAssertEqual(timeline.trailingDelay, 0, accuracy: 0.000_001)
        guard case .click(let click) = timeline.blocks[0] else { return XCTFail() }
        XCTAssertEqual(click.startOffset, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(click.delayBefore, 0, accuracy: 0.000_001)

        let plan = BlockExpander.plan(
            blocks: timeline.blocks,
            trailingDelay: timeline.trailingDelay
        )
        XCTAssertEqual(plan.steps.first?.t ?? -1, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(plan.duration, 0.3, accuracy: 0.000_001)
    }

    func testInitialLongIdleBecomesLeadingWait() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(2, .leftDown, x: 1, y: 2),
                ev(2.1, .leftUp, x: 1, y: 2),
            ],
            duration: 2.1
        ))

        XCTAssertEqual(timeline.blocks.count, 2)
        guard case .wait(let wait) = timeline.blocks[0],
              case .click(let click) = timeline.blocks[1] else {
            return XCTFail("got \(timeline.blocks)")
        }
        XCTAssertEqual(wait.startOffset, 0, accuracy: 0.000_001)
        XCTAssertEqual(wait.duration, 2, accuracy: 0.000_001)
        XCTAssertEqual(click.startOffset, 2, accuracy: 0.000_001)
        XCTAssertEqual(click.delayBefore, 0, accuracy: 0.000_001)

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        XCTAssertEqual(plan.steps.first?.t ?? -1, 2, accuracy: 0.000_001)
    }

    func testTwoClicksPreserveExactTimesHoldsCoordinatesFlagsAndCounts() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0, .leftDown, x: 1, y: 2, flags: 11, clicks: 2),
                ev(0.1, .leftUp, x: 3, y: 4, flags: 12, clicks: 3),
                ev(0.4, .rightDown, x: 5, y: 6, flags: 21, clicks: 4),
                ev(0.7, .rightUp, x: 7, y: 8, flags: 22, clicks: 5),
            ],
            duration: 0.7
        ))

        XCTAssertEqual(timeline.blocks.count, 2)
        guard case .click(let first) = timeline.blocks[0],
              case .click(let second) = timeline.blocks[1] else {
            return XCTFail("got \(timeline.blocks)")
        }
        XCTAssertEqual(first.x, 1)
        XCTAssertEqual(first.y, 2)
        XCTAssertEqual(first.upX, 3)
        XCTAssertEqual(first.upY, 4)
        XCTAssertEqual(first.clickCount, 2)
        XCTAssertEqual(first.upClickCount, 3)
        XCTAssertEqual(first.downFlags, 11)
        XCTAssertEqual(first.upFlags, 12)
        XCTAssertEqual(first.duration, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(second.x, 5)
        XCTAssertEqual(second.y, 6)
        XCTAssertEqual(second.upX, 7)
        XCTAssertEqual(second.upY, 8)
        XCTAssertEqual(second.clickCount, 4)
        XCTAssertEqual(second.upClickCount, 5)
        XCTAssertEqual(second.downFlags, 21)
        XCTAssertEqual(second.upFlags, 22)
        XCTAssertEqual(second.startOffset, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(second.delayBefore, 0, accuracy: 0.000_001)
        XCTAssertEqual(second.duration, 0.3, accuracy: 0.000_001)

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        let downTimes = plan.steps.compactMap { step -> TimeInterval? in
            if case .mouseDown = step.action { return step.t }
            return nil
        }
        XCTAssertEqual(downTimes.count, 2)
        XCTAssertEqual(downTimes[0], 0, accuracy: 0.000_001)
        XCTAssertEqual(downTimes[1], 0.4, accuracy: 0.000_001)
    }

    func testTrailingShortIdleBecomesTrailingDelay() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0, .leftDown, x: 1, y: 1),
                ev(0.1, .leftUp, x: 1, y: 1),
            ],
            duration: 0.3
        ))

        XCTAssertEqual(timeline.blocks.count, 1)
        XCTAssertEqual(timeline.trailingDelay, 0.2, accuracy: 0.000_001)
        let plan = BlockExpander.plan(
            blocks: timeline.blocks,
            trailingDelay: timeline.trailingDelay
        )
        XCTAssertEqual(plan.duration, 0.3, accuracy: 0.000_001)
    }

    func testTrailingLongIdleBecomesWaitBlock() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0, .leftDown, x: 1, y: 1),
                ev(0.1, .leftUp, x: 1, y: 1),
            ],
            duration: 2.1
        ))

        XCTAssertEqual(timeline.blocks.count, 2)
        guard case .wait(let wait) = timeline.blocks[1] else {
            return XCTFail("got \(timeline.blocks)")
        }
        XCTAssertEqual(wait.duration, 2, accuracy: 0.000_001)
        XCTAssertEqual(timeline.trailingDelay, 0, accuracy: 0.000_001)
        XCTAssertEqual(BlockExpander.plan(blocks: timeline.blocks).duration, 2.1, accuracy: 0.000_001)
    }

    func testEmptyCaptureRetainsShortAndLongDurations() {
        let short = EventGrouper.group(RecordingCapture(events: [], duration: 0.2))
        XCTAssertTrue(short.blocks.isEmpty)
        XCTAssertEqual(short.trailingDelay, 0.2, accuracy: 0.000_001)

        let long = EventGrouper.group(RecordingCapture(events: [], duration: 2))
        XCTAssertEqual(long.blocks.count, 1)
        guard case .wait(let wait) = long.blocks[0] else { return XCTFail() }
        XCTAssertEqual(wait.duration, 2, accuracy: 0.000_001)
        XCTAssertEqual(long.trailingDelay, 0, accuracy: 0.000_001)
    }

    func testMouseMovePreservesEveryPointTimeAndFlags() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0.2, .mouseMove, x: 1, y: 2, flags: 11),
                ev(0.3, .mouseMove, x: 3, y: 4, flags: 12),
                ev(0.45, .mouseMove, x: 5, y: 6, flags: 13),
            ],
            duration: 0.45
        ))

        guard case .move(let move) = timeline.blocks.last else { return XCTFail() }
        XCTAssertEqual(move.startOffset, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(move.delayBefore, 0, accuracy: 0.000_001)
        XCTAssertEqual(move.duration, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(move.points.count, 3)
        XCTAssertEqual(move.points.map(\.x), [1, 3, 5])
        XCTAssertEqual(move.points.map(\.y), [2, 4, 6])
        XCTAssertEqual(move.points.map(\.flags), [11, 12, 13])
        XCTAssertEqual(move.points[0].t, 0, accuracy: 0.000_001)
        XCTAssertEqual(move.points[1].t, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(move.points[2].t, 0.25, accuracy: 0.000_001)

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        XCTAssertEqual(plan.steps.map(\.t), [0.2, 0.3, 0.45])
    }

    func testExactKeyHoldIsPreservedThroughPlaybackPlan() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0.2, .keyDown, keyCode: 0, flags: KeyCodeMap.maskShift, chars: "A"),
                ev(0.6, .keyUp, keyCode: 0, flags: KeyCodeMap.maskShift),
            ],
            duration: 0.6
        ))

        guard case .typeText(let typeText) = timeline.blocks.first else { return XCTFail() }
        XCTAssertEqual(typeText.duration, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(typeText.keystrokes.count, 1)
        XCTAssertEqual(typeText.keystrokes[0].t, 0, accuracy: 0.000_001)
        XCTAssertEqual(typeText.keystrokes[0].upT, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(typeText.keystrokes[0].downFlags, KeyCodeMap.maskShift)
        XCTAssertEqual(typeText.keystrokes[0].upFlags, KeyCodeMap.maskShift)

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        XCTAssertEqual(plan.steps.count, 2)
        XCTAssertEqual(plan.steps[0].t, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(plan.steps[1].t, 0.6, accuracy: 0.000_001)
    }

    func testOverlappingKeyHoldsExpandInChronologicalOrder() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0, .keyDown, keyCode: 0, flags: 11, chars: "a"),
                ev(0.1, .keyDown, keyCode: 11, flags: 21, chars: "b"),
                ev(0.3, .keyUp, keyCode: 0, flags: 12),
                ev(0.4, .keyUp, keyCode: 11, flags: 22),
            ],
            duration: 0.4
        ))

        guard case .typeText(let typeText) = timeline.blocks.first else { return XCTFail() }
        XCTAssertEqual(typeText.text, "ab")
        XCTAssertEqual(typeText.duration, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(typeText.keystrokes[0].upT, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(typeText.keystrokes[1].upT, 0.4, accuracy: 0.000_001)

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        XCTAssertEqual(plan.steps.map(\.action), [
            .keyDown(keyCode: 0, flags: 11, chars: "a"),
            .keyDown(keyCode: 11, flags: 21, chars: "b"),
            .keyUp(keyCode: 0, flags: 12),
            .keyUp(keyCode: 11, flags: 22),
        ])
        XCTAssertEqual(plan.steps.map(\.t), [0, 0.1, 0.3, 0.4])
    }

    func testRepeatedKeyCodesMatchKeyUpsInFirstInFirstOutOrder() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0, .keyDown, keyCode: 0, chars: "a"),
                ev(0.1, .keyDown, keyCode: 0, chars: "a"),
                ev(0.2, .keyUp, keyCode: 0, flags: 31),
                ev(0.3, .keyUp, keyCode: 0, flags: 32),
            ],
            duration: 0.3
        ))

        guard case .typeText(let typeText) = timeline.blocks.first else { return XCTFail() }
        XCTAssertEqual(typeText.keystrokes.count, 2)
        XCTAssertEqual(typeText.keystrokes[0].upT, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(typeText.keystrokes[0].upFlags, 31)
        XCTAssertEqual(typeText.keystrokes[1].upT, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(typeText.keystrokes[1].upFlags, 32)
    }

    func testDanglingPrintableDownUsesFallbackAndSplitsAfterIdle() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0, .keyDown, keyCode: 0, chars: "a"),
                ev(1, .keyDown, keyCode: 11, chars: "b"),
                ev(1.1, .keyUp, keyCode: 11, flags: 42),
            ],
            duration: 1.1
        ))

        guard timeline.blocks.count == 3 else {
            return XCTFail("expected type/wait/type, got \(timeline.blocks)")
        }
        guard case .typeText(let first) = timeline.blocks[0],
              case .wait(let wait) = timeline.blocks[1],
              case .typeText(let second) = timeline.blocks[2] else {
            return XCTFail("got \(timeline.blocks)")
        }
        XCTAssertEqual(first.text, "a")
        XCTAssertEqual(first.duration, 0.02, accuracy: 0.000_001)
        XCTAssertEqual(first.keystrokes[0].upT, 0.02, accuracy: 0.000_001)
        XCTAssertEqual(wait.duration, 0.98, accuracy: 0.000_001)
        XCTAssertEqual(second.text, "b")
        XCTAssertEqual(second.duration, 0.1, accuracy: 0.000_001)
    }

    func testLongHeldKeyStillMatchesUpAfterOverlappingDownBeyondThreshold() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0, .keyDown, keyCode: 0, flags: 11, chars: "a"),
                ev(1, .keyDown, keyCode: 11, flags: 21, chars: "b"),
                ev(1.1, .keyUp, keyCode: 0, flags: 12),
                ev(1.2, .keyUp, keyCode: 11, flags: 22),
            ],
            duration: 1.2
        ))

        guard timeline.blocks.count == 1 else {
            return XCTFail("expected one overlapping type block, got \(timeline.blocks)")
        }
        guard case .typeText(let typeText) = timeline.blocks.first else { return XCTFail() }
        XCTAssertEqual(typeText.text, "ab")
        XCTAssertEqual(typeText.keystrokes[0].upT, 1.1, accuracy: 0.000_001)
        XCTAssertEqual(typeText.keystrokes[0].upFlags, 12)
        XCTAssertEqual(typeText.keystrokes[1].upT, 1.2, accuracy: 0.000_001)
        XCTAssertEqual(typeText.keystrokes[1].upFlags, 22)
        XCTAssertEqual(typeText.duration, 1.2, accuracy: 0.000_001)
    }

    func testLongHeldKeyUpIsConsumedBeforeTypingSplitDecision() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0, .keyDown, keyCode: 0, chars: "a"),
                ev(0.6, .flagsChanged, keyCode: 56, flags: KeyCodeMap.maskShift),
                ev(1, .keyUp, keyCode: 0, flags: 41),
                ev(1.2, .keyDown, keyCode: 11, chars: "b"),
                ev(1.3, .keyUp, keyCode: 11, flags: 42),
            ],
            duration: 1.3
        ))

        XCTAssertEqual(timeline.blocks.count, 1)
        guard case .typeText(let typeText) = timeline.blocks[0] else { return XCTFail() }
        XCTAssertEqual(typeText.text, "ab")
        XCTAssertEqual(typeText.keystrokes[0].upT, 1, accuracy: 0.000_001)
        XCTAssertEqual(typeText.duration, 1.3, accuracy: 0.000_001)
    }

    func testShiftArrowAndPlainTabAreShortcuts() {
        let arrow = EventGrouper.group(RecordingCapture(
            events: [
                ev(0, .keyDown, keyCode: 123, flags: KeyCodeMap.maskShift),
                ev(0.2, .flagsChanged, keyCode: 56, flags: KeyCodeMap.maskShift),
                ev(0.4, .keyUp, keyCode: 123, flags: 91),
            ],
            duration: 0.4
        ))
        guard case .shortcut(let arrowBlock) = arrow.blocks.first else { return XCTFail() }
        XCTAssertEqual(arrowBlock.flags, KeyCodeMap.maskShift)
        XCTAssertEqual(arrowBlock.upFlags, 91)
        XCTAssertEqual(arrowBlock.duration, 0.4, accuracy: 0.000_001)

        let tab = EventGrouper.group(RecordingCapture(
            events: [
                ev(0, .keyDown, keyCode: 48),
                ev(0.1, .keyUp, keyCode: 48, flags: 92),
            ],
            duration: 0.1
        ))
        guard case .shortcut(let tabBlock) = tab.blocks.first else { return XCTFail() }
        XCTAssertEqual(tabBlock.keyCode, 48)
        XCTAssertEqual(tabBlock.flags, 0)
        XCTAssertEqual(tabBlock.upFlags, 92)
        XCTAssertEqual(tabBlock.duration, 0.1, accuracy: 0.000_001)
    }

    func testShiftAndOptionPrintableCharactersRemainText() {
        let shift = EventGrouper.group([
            ev(0, .keyDown, keyCode: 4, flags: KeyCodeMap.maskShift, chars: "H"),
            ev(0.1, .keyUp, keyCode: 4, flags: KeyCodeMap.maskShift),
        ])
        guard case .typeText(let shiftText) = shift.first else { return XCTFail() }
        XCTAssertEqual(shiftText.text, "H")

        let option = EventGrouper.group([
            ev(0, .keyDown, keyCode: 0, flags: KeyCodeMap.maskOption, chars: "å"),
            ev(0.1, .keyUp, keyCode: 0, flags: KeyCodeMap.maskOption),
        ])
        guard case .typeText(let optionText) = option.first else { return XCTFail() }
        XCTAssertEqual(optionText.text, "å")
        XCTAssertEqual(optionText.keystrokes.first?.downFlags, KeyCodeMap.maskOption)
        XCTAssertEqual(optionText.keystrokes.first?.upFlags, KeyCodeMap.maskOption)
    }

    func testCommandClickAndShiftDragFlagsSurviveExpansion() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0, .leftDown, x: 1, y: 2, flags: KeyCodeMap.maskCommand),
                ev(0.1, .leftUp, x: 3, y: 4, flags: KeyCodeMap.maskCommand),
                ev(0.3, .rightDown, x: 5, y: 6, flags: KeyCodeMap.maskShift),
                ev(0.4, .rightDrag, x: 7, y: 8, flags: KeyCodeMap.maskShift | 1),
                ev(0.6, .rightUp, x: 9, y: 10, flags: 2),
            ],
            duration: 0.6
        ))

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        XCTAssertEqual(plan.steps.map(\.action), [
            .mouseDown(x: 1, y: 2, button: .left, clickCount: 1,
                       flags: KeyCodeMap.maskCommand),
            .mouseUp(x: 3, y: 4, button: .left, clickCount: 1,
                     flags: KeyCodeMap.maskCommand),
            .mouseDown(x: 5, y: 6, button: .right, clickCount: 1,
                       flags: KeyCodeMap.maskShift),
            .mouseDrag(x: 7, y: 8, button: .right, flags: KeyCodeMap.maskShift | 1),
            .mouseUp(x: 9, y: 10, button: .right, clickCount: 1, flags: 2),
        ])
        XCTAssertEqual(plan.steps.map(\.t), [0, 0.1, 0.3, 0.4, 0.6])
    }

    func testScrollLocationDeltasTimingAndFlagsSurviveExpansion() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0.25, .scroll, x: 100, y: 200, flags: 11, dx: 1.5, dy: -2.5),
                ev(0.4, .scroll, x: 100, y: 200, flags: 12, dx: -3.5, dy: 4.5),
            ],
            duration: 0.4
        ))

        guard case .scroll(let scroll) = timeline.blocks.first else { return XCTFail() }
        XCTAssertEqual(scroll.x, 100)
        XCTAssertEqual(scroll.y, 200)
        XCTAssertEqual(scroll.startOffset, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(scroll.delayBefore, 0, accuracy: 0.000_001)
        XCTAssertEqual(scroll.duration, 0.15, accuracy: 0.000_001)
        XCTAssertEqual(scroll.steps.count, 2)
        XCTAssertEqual(scroll.steps.map(\.dx), [1.5, -3.5])
        XCTAssertEqual(scroll.steps.map(\.dy), [-2.5, 4.5])
        XCTAssertEqual(scroll.steps.map(\.flags), [11, 12])
        XCTAssertEqual(scroll.steps[0].t, 0, accuracy: 0.000_001)
        XCTAssertEqual(scroll.steps[1].t, 0.15, accuracy: 0.000_001)

        let plan = BlockExpander.plan(blocks: timeline.blocks)
        XCTAssertEqual(plan.steps.map(\.action), [
            .scroll(x: 100, y: 200, dx: 1.5, dy: -2.5, flags: 11),
            .scroll(x: 100, y: 200, dx: -3.5, dy: 4.5, flags: 12),
        ])
        XCTAssertEqual(plan.steps.map(\.t), [0.25, 0.4])
    }

    func testInterruptedDragDurationReachesLatestCollectedSample() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(1, .leftDown, x: 1, y: 2, flags: 11),
                ev(1.2, .leftDrag, x: 3, y: 4, flags: 12),
                ev(1.35, .leftDrag, x: 5, y: 6, flags: 13),
            ],
            duration: 1.35
        ))

        guard case .drag(let drag) = timeline.blocks.last else { return XCTFail() }
        XCTAssertEqual(drag.points.count, 3)
        XCTAssertEqual(drag.points.map(\.x), [1, 3, 5])
        XCTAssertEqual(drag.points.map(\.y), [2, 4, 6])
        XCTAssertEqual(drag.points.map(\.flags), [11, 12, 13])
        XCTAssertEqual(drag.points[0].t, 0, accuracy: 0.000_001)
        XCTAssertEqual(drag.points[1].t, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(drag.points[2].t, 0.35, accuracy: 0.000_001)
        XCTAssertEqual(drag.duration, 0.35, accuracy: 0.000_001)
    }

    func testFlagsChangedDoesNotEraseInitialIdleAndOrphansAreSkipped() {
        let timeline = EventGrouper.group(RecordingCapture(
            events: [
                ev(0.2, .flagsChanged, keyCode: 55, flags: KeyCodeMap.maskCommand),
                ev(0.4, .leftUp, x: 9, y: 9),
                ev(0.6, .leftDrag, x: 9, y: 9),
                ev(1, .leftDown, x: 1, y: 1),
                ev(1.1, .leftUp, x: 1, y: 1),
            ],
            duration: 1.1
        ))

        XCTAssertEqual(timeline.blocks.count, 2)
        guard case .wait(let wait) = timeline.blocks[0], case .click = timeline.blocks[1] else {
            return XCTFail("got \(timeline.blocks)")
        }
        XCTAssertEqual(wait.duration, 1, accuracy: 0.000_001)
    }

    func testNonFiniteAndNegativeCaptureDurationsAreSanitized() {
        let negative = EventGrouper.group(RecordingCapture(events: [], duration: -1))
        XCTAssertTrue(negative.blocks.isEmpty)
        XCTAssertEqual(negative.trailingDelay, 0)

        let nonFinite = EventGrouper.group(RecordingCapture(events: [], duration: .infinity))
        XCTAssertTrue(nonFinite.blocks.isEmpty)
        XCTAssertEqual(nonFinite.trailingDelay, 0)
    }
}

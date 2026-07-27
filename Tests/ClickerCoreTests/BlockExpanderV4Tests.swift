import XCTest
@testable import ClickerCore

final class BlockExpanderV4Tests: XCTestCase {
    func testAbsoluteOffsetsDrivePlaybackInsteadOfLegacyRelativeTiming() {
        let first = ActionBlock.click(ClickBlock(
            x: 1,
            y: 2,
            button: .left,
            clickCount: 1,
            delayBefore: 99,
            startOffset: 2,
            duration: 0.5
        )).withOverlapBefore(88)
        let second = ActionBlock.shortcut(ShortcutBlock(
            keyCode: 8,
            flags: 1,
            delayBefore: 77,
            startOffset: 0.25,
            upFlags: 2,
            duration: 0.25
        )).withOverlapBefore(66)

        let plan = BlockExpander.plan(blocks: [first, second], trailingDelay: 0.5)

        XCTAssertEqual(plan.steps.map(\.t), [0.25, 0.5, 2, 2.5])
        XCTAssertEqual(plan.duration, 3, accuracy: 0.000_001)
    }

    func testEqualTimeStepsSortByOrdinalThenStableIndexAcrossBlocks() {
        let laterCaptureBlock = ClickBlock(
            x: 10,
            y: 20,
            button: .left,
            clickCount: 1,
            startOffset: 1,
            duration: 0,
            downOrdinal: 2,
            upOrdinal: 4
        )
        let earlierCaptureBlock = ClickBlock(
            x: 30,
            y: 40,
            button: .right,
            clickCount: 1,
            startOffset: 1,
            duration: 0,
            downOrdinal: 1,
            upOrdinal: 3
        )

        let plan = BlockExpander.plan(blocks: [
            .click(laterCaptureBlock),
            .click(earlierCaptureBlock),
        ])

        XCTAssertEqual(plan.steps.map(\.ordinal), [1, 2, 3, 4])
        XCTAssertEqual(plan.steps.map(\.action), [
            .mouseDown(x: 30, y: 40, button: .right, clickCount: 1, flags: 0),
            .mouseDown(x: 10, y: 20, button: .left, clickCount: 1, flags: 0),
            .mouseUp(x: 30, y: 40, button: .right, clickCount: 1, flags: 0),
            .mouseUp(x: 10, y: 20, button: .left, clickCount: 1, flags: 0),
        ])
    }

    func testAutorepeatDownsEmitOnlyTheCapturedFinalKeyUp() {
        let block = TypeTextBlock(
            text: "aaa",
            keystrokes: [
                Keystroke(
                    t: 0,
                    keyCode: 0,
                    chars: "a",
                    upT: 0.5,
                    downOrdinal: 0,
                    upOrdinal: 3
                ),
                Keystroke(
                    t: 0.1,
                    keyCode: 0,
                    chars: "a",
                    upT: 0.5,
                    isRepeat: true,
                    downOrdinal: 1,
                    upOrdinal: 3
                ),
                Keystroke(
                    t: 0.2,
                    keyCode: 0,
                    chars: "a",
                    upT: 0.5,
                    isRepeat: true,
                    downOrdinal: 2,
                    upOrdinal: 3
                ),
            ],
            startOffset: 1,
            duration: 0.5
        )

        let plan = BlockExpander.plan(blocks: [.typeText(block)])

        XCTAssertEqual(plan.steps.map(\.t), [1, 1.1, 1.2, 1.5])
        XCTAssertEqual(plan.steps.map(\.ordinal), [0, 1, 2, 3])
        XCTAssertEqual(plan.steps.map(\.action), [
            .keyDown(keyCode: 0, flags: 0, chars: "a"),
            .keyDown(keyCode: 0, flags: 0, chars: "a"),
            .keyDown(keyCode: 0, flags: 0, chars: "a"),
            .keyUp(keyCode: 0, flags: 0),
        ])
    }

    func testStandaloneRepeatBlockStillEmitsItsKnownRelease() {
        let block = ShortcutBlock(
            keyCode: 8,
            flags: 1,
            startOffset: 2,
            upFlags: 2,
            duration: 0.3,
            isRepeat: true,
            downOrdinal: 4,
            upOrdinal: 5
        )

        let plan = BlockExpander.plan(blocks: [.shortcut(block)])

        XCTAssertEqual(plan.steps.map(\.t), [2, 2.3])
        XCTAssertEqual(plan.steps.map(\.action), [
            .keyDown(keyCode: 8, flags: 1, chars: ""),
            .keyUp(keyCode: 8, flags: 2),
        ])
    }

    func testEditedTextWithMaximumLegacyOrdinalDoesNotOverflow() {
        let block = TypeTextBlock(
            text: "b",
            keystrokes: [Keystroke(
                t: 0,
                keyCode: 0,
                chars: "a",
                upT: 0.1,
                downOrdinal: Int.max,
                upOrdinal: Int.max
            )]
        )

        let plan = BlockExpander.plan(blocks: [.typeText(block)])

        XCTAssertEqual(plan.steps.count, 2)
        XCTAssertEqual(plan.steps.map(\.ordinal), [Int.max, Int.max])
    }

    func testPartialScrollCoordinatesFallBackAsAnAtomicPair() {
        var step = ScrollStep(t: 0, x: 100, y: 200, dx: 1, dy: -1, flags: 5, ordinal: 9)
        step.y = nil
        let scroll = ScrollBlock(
            x: 10,
            y: 20,
            duration: 0,
            steps: [step],
            startOffset: 0.5
        )

        let plan = BlockExpander.plan(blocks: [.scroll(scroll)])

        XCTAssertEqual(plan.steps[0].action, .scroll(x: 10, y: 20, dx: 1, dy: -1, flags: 5))
        XCTAssertEqual(plan.steps[0].t, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(plan.steps[0].ordinal, 9)
    }
}

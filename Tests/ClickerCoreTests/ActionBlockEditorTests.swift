import XCTest
@testable import ClickerCore

final class ActionBlockEditorTests: XCTestCase {
    func testClickEditMovesDownAndUpCoordinatesTogether() {
        let original = ClickBlock(
            x: 10,
            y: 20,
            button: .left,
            clickCount: 1,
            startOffset: 1.5,
            duration: 0.25,
            upX: 11,
            upY: 21,
            upClickCount: 1,
            downFlags: 3,
            upFlags: 4,
            downOrdinal: 7,
            upOrdinal: 9
        )

        let edited = ActionBlockEditor.click(
            original,
            x: 30,
            y: 40,
            button: .right,
            clickCount: 2
        )

        XCTAssertEqual(edited.x, 30)
        XCTAssertEqual(edited.y, 40)
        XCTAssertEqual(edited.upX, 30)
        XCTAssertEqual(edited.upY, 40)
        XCTAssertEqual(edited.button, .right)
        XCTAssertEqual(edited.clickCount, 2)
        XCTAssertEqual(edited.upClickCount, 2)
        XCTAssertEqual(edited.startOffset, 1.5)
        XCTAssertEqual(edited.duration, 0.25)
        XCTAssertEqual(edited.downFlags, 3)
        XCTAssertEqual(edited.upFlags, 4)
        XCTAssertEqual(edited.downOrdinal, 7)
        XCTAssertEqual(edited.upOrdinal, 9)
    }

    func testShortcutEditUsesSameModifiersForSafeKeyRelease() {
        let original = ShortcutBlock(
            keyCode: 8,
            flags: 1,
            startOffset: 2,
            upFlags: 2,
            duration: 0.4,
            isRepeat: true,
            downOrdinal: 4,
            upOrdinal: 6
        )

        let edited = ActionBlockEditor.shortcut(
            original,
            keyCode: 9,
            flags: 12
        )

        XCTAssertEqual(edited.keyCode, 9)
        XCTAssertEqual(edited.flags, 12)
        XCTAssertEqual(edited.upFlags, 12)
        XCTAssertEqual(edited.startOffset, 2)
        XCTAssertEqual(edited.duration, 0.4)
        XCTAssertTrue(edited.isRepeat)
        XCTAssertEqual(edited.downOrdinal, 4)
        XCTAssertEqual(edited.upOrdinal, 6)
    }

    func testScrollEditPreservesEverySampleAndScalesVerticalDeltas() {
        let original = ScrollBlock(
            x: 50,
            y: 60,
            duration: 0.2,
            steps: [
                ScrollStep(t: 0, x: 50, y: 60, dx: 1, dy: -2, flags: 10, ordinal: 3),
                ScrollStep(t: 0.1, x: 51, y: 61, dx: 2, dy: -3, flags: 11, ordinal: 4),
                ScrollStep(t: 0.2, x: 52, y: 62, dx: 3, dy: -3, flags: 12, ordinal: 5),
            ],
            startOffset: 4
        )

        let edited = ActionBlockEditor.scroll(original, totalDeltaY: -16)

        XCTAssertEqual(edited.steps, [
            ScrollStep(t: 0, x: 50, y: 60, dx: 1, dy: -4, flags: 10, ordinal: 3),
            ScrollStep(t: 0.1, x: 51, y: 61, dx: 2, dy: -6, flags: 11, ordinal: 4),
            ScrollStep(t: 0.2, x: 52, y: 62, dx: 3, dy: -6, flags: 12, ordinal: 5),
        ])
        XCTAssertEqual(edited.duration, 0.2)
        XCTAssertEqual(edited.startOffset, 4)
    }

    func testScrollEditWithZeroOriginalTotalChangesOnlyLastSample() {
        let original = ScrollBlock(
            x: 5,
            y: 6,
            duration: 0.1,
            steps: [
                ScrollStep(t: 0, x: 5, y: 6, dx: 0, dy: -2, ordinal: 8),
                ScrollStep(t: 0.1, x: 5, y: 6, dx: 0, dy: 2, ordinal: 9),
            ]
        )

        let edited = ActionBlockEditor.scroll(original, totalDeltaY: 5)

        XCTAssertEqual(edited.steps.map(\.dy), [-2, 7])
        XCTAssertEqual(edited.steps.map(\.ordinal), [8, 9])
    }

    func testMoveEditNormalizesNegativeDurationAndKeepsTimesFinite() {
        let original = MoveBlock(
            duration: 2,
            points: [
                TrackPoint(t: 0, x: 0, y: 0, flags: 1, ordinal: 2),
                TrackPoint(t: 2, x: 20, y: 20, flags: 2, ordinal: 3),
            ],
            startOffset: 5
        )

        let edited = ActionBlockEditor.move(
            original,
            endX: 30,
            endY: 40,
            duration: -1
        )

        XCTAssertEqual(edited.duration, 0)
        XCTAssertEqual(edited.points.map(\.t), [0, 0])
        XCTAssertEqual(edited.points.map(\.x), [10, 30])
        XCTAssertEqual(edited.points.map(\.y), [20, 40])
        XCTAssertTrue(edited.points.allSatisfy { $0.t.isFinite })
        XCTAssertEqual(edited.points.map(\.ordinal), [2, 3])
        XCTAssertEqual(edited.startOffset, 5)
    }

    func testDragEditNormalizesInfiniteDuration() {
        let original = DragBlock(
            button: .left,
            duration: 1,
            points: [
                TrackPoint(t: 0, x: 0, y: 0, ordinal: 4),
                TrackPoint(t: 1, x: 10, y: 10, ordinal: 5),
            ],
            hasRecordedMouseUp: true,
            upOrdinal: 5
        )

        let edited = ActionBlockEditor.drag(
            original,
            startX: 20,
            startY: 30,
            endX: 40,
            endY: 50,
            duration: .infinity
        )

        XCTAssertEqual(edited.duration, 0)
        XCTAssertEqual(edited.points.map(\.t), [0, 0])
        XCTAssertTrue(edited.points.allSatisfy { $0.t.isFinite })
        XCTAssertEqual(edited.points.map(\.x), [20, 40])
        XCTAssertEqual(edited.points.map(\.y), [30, 50])
        XCTAssertEqual(edited.upOrdinal, 5)
    }

    func testOnePointDragEditCreatesDistinctEndpointsAndKeepsSafeRelease() {
        let original = DragBlock(
            button: .right,
            duration: 1,
            points: [TrackPoint(t: 0, x: 10, y: 20, flags: 7, ordinal: 8)],
            startOffset: 3,
            hasRecordedMouseUp: false,
            upOrdinal: 9
        )

        let edited = ActionBlockEditor.drag(
            original,
            startX: 30,
            startY: 40,
            endX: 50,
            endY: 60,
            duration: 2
        )

        XCTAssertEqual(edited.points.count, 2)
        XCTAssertEqual(edited.points.map(\.t), [0, 2])
        XCTAssertEqual(edited.points.map(\.x), [30, 50])
        XCTAssertEqual(edited.points.map(\.y), [40, 60])
        XCTAssertEqual(edited.points.map(\.flags), [7, 7])
        XCTAssertFalse(edited.hasRecordedMouseUp)
        XCTAssertEqual(edited.upOrdinal, 9)
        XCTAssertEqual(edited.startOffset, 3)
    }

    func testWaitEditNormalizesNaNDuration() {
        let original = WaitBlock(duration: 4, startOffset: 6)

        let edited = ActionBlockEditor.wait(original, duration: .nan)

        XCTAssertEqual(edited.duration, 0)
        XCTAssertTrue(edited.duration.isFinite)
        XCTAssertEqual(edited.startOffset, 6)
    }

    func testEditDispatchesFormValuesToTheMatchingBlockKind() {
        let click = ActionBlock.click(ClickBlock(
            x: 1,
            y: 2,
            button: .left,
            clickCount: 1,
            upX: 3,
            upY: 4
        ))
        let values = ActionBlockEditValues(
            x: 10,
            y: 20,
            endX: 30,
            endY: 40,
            duration: 2,
            text: "edited",
            button: .right,
            clickCount: 2,
            keyCode: 9,
            shortcutFlags: 12,
            scrollDeltaY: -6
        )

        guard case .click(let editedClick) = ActionBlockEditor.edit(click, values: values) else {
            return XCTFail("expected click")
        }
        XCTAssertEqual(editedClick.x, 10)
        XCTAssertEqual(editedClick.y, 20)
        XCTAssertEqual(editedClick.upX, 10)
        XCTAssertEqual(editedClick.upY, 20)
        XCTAssertEqual(editedClick.button, .right)
        XCTAssertEqual(editedClick.clickCount, 2)

        let scroll = ActionBlock.scroll(ScrollBlock(
            x: 5,
            y: 6,
            duration: 0.1,
            steps: [
                ScrollStep(t: 0, x: 5, y: 6, dx: 0, dy: -1, ordinal: 3),
                ScrollStep(t: 0.1, x: 5, y: 6, dx: 0, dy: -2, ordinal: 4),
            ]
        ))
        guard case .scroll(let editedScroll) = ActionBlockEditor.edit(scroll, values: values) else {
            return XCTFail("expected scroll")
        }
        XCTAssertEqual(editedScroll.steps.map(\.dy), [-2, -4])
        XCTAssertEqual(editedScroll.steps.map(\.ordinal), [3, 4])

        let drag = ActionBlock.drag(DragBlock(
            button: .left,
            duration: 1,
            points: [TrackPoint(t: 0, x: 0, y: 0, ordinal: 5)]
        ))
        guard case .drag(let editedDrag) = ActionBlockEditor.edit(drag, values: values) else {
            return XCTFail("expected drag")
        }
        XCTAssertEqual(editedDrag.points.map(\.x), [10, 30])
        XCTAssertEqual(editedDrag.points.map(\.y), [20, 40])
        XCTAssertEqual(editedDrag.duration, 2)

        let move = ActionBlock.move(MoveBlock(
            duration: 1,
            points: [
                TrackPoint(t: 0, x: 0, y: 0, ordinal: 6),
                TrackPoint(t: 1, x: 10, y: 10, ordinal: 7),
            ]
        ))
        guard case .move(let editedMove) = ActionBlockEditor.edit(move, values: values) else {
            return XCTFail("expected move")
        }
        XCTAssertEqual(editedMove.points.map(\.x), [20, 30])
        XCTAssertEqual(editedMove.points.map(\.y), [30, 40])
        XCTAssertEqual(editedMove.points.map(\.t), [0, 2])

        let typeText = ActionBlock.typeText(TypeTextBlock(
            text: "old",
            keystrokes: [],
            startOffset: 3,
            duration: 0.5
        ))
        guard case .typeText(let editedText) = ActionBlockEditor.edit(
            typeText,
            values: values
        ) else {
            return XCTFail("expected typeText")
        }
        XCTAssertEqual(editedText.text, "edited")
        XCTAssertEqual(editedText.startOffset, 3)
        XCTAssertEqual(editedText.duration, 0.32, accuracy: 0.000_001)

        let shortcut = ActionBlock.shortcut(ShortcutBlock(
            keyCode: 8,
            flags: 1,
            upFlags: 2,
            downOrdinal: 10,
            upOrdinal: 11
        ))
        guard case .shortcut(let editedShortcut) = ActionBlockEditor.edit(
            shortcut,
            values: values
        ) else {
            return XCTFail("expected shortcut")
        }
        XCTAssertEqual(editedShortcut.keyCode, 9)
        XCTAssertEqual(editedShortcut.flags, 12)
        XCTAssertEqual(editedShortcut.upFlags, 12)
        XCTAssertEqual(editedShortcut.downOrdinal, 10)
        XCTAssertEqual(editedShortcut.upOrdinal, 11)

        let wait = ActionBlock.wait(WaitBlock(duration: 1, startOffset: 4))
        guard case .wait(let editedWait) = ActionBlockEditor.edit(wait, values: values) else {
            return XCTFail("expected wait")
        }
        XCTAssertEqual(editedWait.duration, 2)
        XCTAssertEqual(editedWait.startOffset, 4)
    }
}

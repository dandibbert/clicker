import XCTest
@testable import ClickerCore

final class BlockExpanderTests: XCTestCase {
    func testClickAbsoluteStartHoldAndTrailingDelayProduceExactPlan() {
        let id = UUID()
        let script = Script(
            name: "Click",
            blocks: [.click(ClickBlock(
                id: id,
                x: 10,
                y: 20,
                button: .left,
                clickCount: 2,
                startOffset: 0.4,
                duration: 0.25,
                upX: 30,
                upY: 40,
                upClickCount: 3,
                downFlags: 11,
                upFlags: 12
            ))],
            trailingDelay: 0.5
        )

        let plan = BlockExpander.plan(for: script)

        XCTAssertEqual(plan.steps.count, 2)
        XCTAssertEqual(plan.steps[0].t, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(plan.steps[0].action, .mouseDown(
            x: 10,
            y: 20,
            button: .left,
            clickCount: 2,
            flags: 11
        ))
        XCTAssertEqual(plan.steps[0].blockID, id)
        XCTAssertEqual(plan.steps[1].t, 0.65, accuracy: 0.000_001)
        XCTAssertEqual(plan.steps[1].action, .mouseUp(
            x: 30,
            y: 40,
            button: .left,
            clickCount: 3,
            flags: 12
        ))
        XCTAssertEqual(plan.duration, 1.15, accuracy: 0.000_001)
    }

    func testWaitOnlyPlanHasNoStepsAndRetainsDuration() {
        let plan = BlockExpander.plan(blocks: [.wait(WaitBlock(duration: 2))], trailingDelay: 0)

        XCTAssertTrue(plan.steps.isEmpty)
        XCTAssertEqual(plan.duration, 2, accuracy: 0.000_001)
    }

    func testTrailingOnlyEmptyScriptRetainsPositiveDuration() {
        let plan = BlockExpander.plan(for: Script(name: "Empty", trailingDelay: 0.75))

        XCTAssertTrue(plan.steps.isEmpty)
        XCTAssertEqual(plan.duration, 0.75, accuracy: 0.000_001)
    }

    func testOverlappingKeystrokesAreChronologicalStableAndExact() {
        let id = UUID()
        let block = TypeTextBlock(
            id: id,
            text: "ab",
            keystrokes: [
                Keystroke(
                    t: 0,
                    keyCode: 4,
                    chars: "a",
                    upT: 0.2,
                    downFlags: 101,
                    upFlags: 102
                ),
                Keystroke(
                    t: 0.1,
                    keyCode: 5,
                    chars: "b",
                    upT: 0.2,
                    downFlags: 201,
                    upFlags: 202
                ),
            ],
            startOffset: 0.3
        )

        let plan = BlockExpander.plan(blocks: [.typeText(block)], trailingDelay: 0)

        XCTAssertEqual(plan.steps.count, 4)
        XCTAssertEqual(plan.steps[0].t, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(plan.steps[0].action, .keyDown(keyCode: 4, flags: 101, chars: "a"))
        XCTAssertEqual(plan.steps[1].t, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(plan.steps[1].action, .keyDown(keyCode: 5, flags: 201, chars: "b"))
        XCTAssertEqual(plan.steps[2].t, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(plan.steps[2].action, .keyUp(keyCode: 4, flags: 102))
        XCTAssertEqual(plan.steps[3].t, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(plan.steps[3].action, .keyUp(keyCode: 5, flags: 202))
        XCTAssertEqual(plan.steps.map(\.blockID), [id, id, id, id])
        XCTAssertEqual(plan.duration, 0.5, accuracy: 0.000_001)
    }

    func testMouseAndScrollSampleFlagsAndLocationsSurviveExpansion() {
        let moveID = UUID()
        let dragID = UUID()
        let scrollID = UUID()
        let blocks: [ActionBlock] = [
            .move(MoveBlock(
                id: moveID,
                duration: 0.2,
                points: [
                    TrackPoint(t: 0, x: 1, y: 2, flags: 11),
                    TrackPoint(t: 0.2, x: 3, y: 4, flags: 12),
                ]
            )),
            .drag(DragBlock(
                id: dragID,
                button: .right,
                duration: 0.3,
                points: [
                    TrackPoint(t: 0, x: 5, y: 6, flags: 21),
                    TrackPoint(t: 0.1, x: 7, y: 8, flags: 22),
                    TrackPoint(t: 0.3, x: 9, y: 10, flags: 23),
                ],
                startOffset: 0.2
            )),
            .scroll(ScrollBlock(
                id: scrollID,
                x: 11,
                y: 12,
                duration: 0.1,
                steps: [ScrollStep(t: 0, dx: 13, dy: -14, flags: 31)],
                startOffset: 0.5
            )),
        ]

        let plan = BlockExpander.plan(blocks: blocks, trailingDelay: 0)
        let moveActions = plan.steps.filter { $0.blockID == moveID }.map(\.action)
        let dragActions = plan.steps.filter { $0.blockID == dragID }.map(\.action)
        let scrollActions = plan.steps.filter { $0.blockID == scrollID }.map(\.action)

        XCTAssertEqual(moveActions, [
            .mouseMove(x: 1, y: 2, flags: 11),
            .mouseMove(x: 3, y: 4, flags: 12),
        ])
        XCTAssertEqual(dragActions, [
            .mouseDown(x: 5, y: 6, button: .right, clickCount: 1, flags: 21),
            .mouseDrag(x: 7, y: 8, button: .right, flags: 22),
            .mouseUp(x: 9, y: 10, button: .right, clickCount: 1, flags: 23),
        ])
        XCTAssertEqual(scrollActions, [
            .scroll(x: 11, y: 12, dx: 13, dy: -14, flags: 31),
        ])
        XCTAssertEqual(plan.duration, 0.6, accuracy: 0.000_001)
    }

    func testEditedTextUsesUnicodeGeneratedTiming() {
        let block = TypeTextBlock(text: "你好", keystrokes: [])

        let plan = BlockExpander.plan(blocks: [.typeText(block)], trailingDelay: 0)

        XCTAssertEqual(plan.steps.count, 4)
        XCTAssertEqual(plan.steps[0].t, 0, accuracy: 0.000_001)
        XCTAssertEqual(plan.steps[0].action, .keyDown(keyCode: 0, flags: 0, chars: "你"))
        XCTAssertEqual(plan.steps[1].t, 0.02, accuracy: 0.000_001)
        XCTAssertEqual(plan.steps[1].action, .keyUp(keyCode: 0, flags: 0))
        XCTAssertEqual(plan.steps[2].t, 0.06, accuracy: 0.000_001)
        XCTAssertEqual(plan.steps[2].action, .keyDown(keyCode: 0, flags: 0, chars: "好"))
        XCTAssertEqual(plan.steps[3].t, 0.08, accuracy: 0.000_001)
        XCTAssertEqual(plan.steps[3].action, .keyUp(keyCode: 0, flags: 0))
        XCTAssertEqual(plan.duration, 0.08, accuracy: 0.000_001)
    }

    func testShortcutUsesExactDurationAndUpFlags() {
        let block = ShortcutBlock(
            keyCode: 8,
            flags: 41,
            startOffset: 0.4,
            upFlags: 42,
            duration: 0.25
        )

        let plan = BlockExpander.plan(blocks: [.shortcut(block)], trailingDelay: 0)

        XCTAssertEqual(plan.steps.count, 2)
        XCTAssertEqual(plan.steps[0].t, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(plan.steps[0].action, .keyDown(keyCode: 8, flags: 41, chars: ""))
        XCTAssertEqual(plan.steps[1].t, 0.65, accuracy: 0.000_001)
        XCTAssertEqual(plan.steps[1].action, .keyUp(keyCode: 8, flags: 42))
        XCTAssertEqual(plan.duration, 0.65, accuracy: 0.000_001)
    }

    func testExplicitWaitAndAbsoluteActionStartBothContributeToTimeline() {
        let blocks: [ActionBlock] = [
            .wait(WaitBlock(duration: 2)),
            .click(ClickBlock(
                x: 1,
                y: 1,
                button: .left,
                clickCount: 1,
                startOffset: 2.3
            )),
        ]

        let plan = BlockExpander.plan(blocks: blocks, trailingDelay: 0)

        XCTAssertEqual(plan.steps.first?.t ?? -1, 2.3, accuracy: 0.000_001)
        XCTAssertEqual(plan.duration, 2.33, accuracy: 0.000_001)
    }

    func testNegativeAndNonFiniteDurationsDoNotMoveClockBackward() {
        let blocks: [ActionBlock] = [
            .wait(WaitBlock(duration: -1)),
            .click(ClickBlock(
                x: 1,
                y: 2,
                button: .left,
                clickCount: 1,
                delayBefore: -0.5,
                duration: -0.25
            )),
            .shortcut(ShortcutBlock(
                keyCode: 8,
                flags: 0,
                delayBefore: .nan,
                duration: .infinity
            )),
        ]

        let plan = BlockExpander.plan(blocks: blocks, trailingDelay: -Double.infinity)

        XCTAssertEqual(plan.steps.count, 4)
        XCTAssertEqual(plan.steps.map(\.t), [0, 0, 0, 0])
        XCTAssertEqual(plan.duration, 0, accuracy: 0.000_001)
        XCTAssertTrue(plan.steps.allSatisfy { $0.t.isFinite && $0.t >= 0 })
    }

    func testMalformedDragTimesKeepMouseUpAtOrAfterMouseDown() throws {
        let dragID = UUID()
        let plan = BlockExpander.plan(blocks: [
            .drag(DragBlock(
                id: dragID,
                button: .left,
                duration: 0.1,
                points: [
                    TrackPoint(t: 2, x: 1, y: 1),
                    TrackPoint(t: 1, x: 2, y: 2),
                    TrackPoint(t: 0.5, x: 3, y: 3),
                ]
            )),
        ])

        let down = try XCTUnwrap(plan.steps.first { step in
            guard step.blockID == dragID else { return false }
            if case .mouseDown = step.action { return true }
            return false
        })
        let up = try XCTUnwrap(plan.steps.first { step in
            guard step.blockID == dragID else { return false }
            if case .mouseUp = step.action { return true }
            return false
        })

        XCTAssertGreaterThanOrEqual(up.t, down.t)
        XCTAssertEqual(plan.steps.map(\.t), plan.steps.map(\.t).sorted())
        XCTAssertTrue(plan.steps.allSatisfy { $0.t.isFinite && $0.t >= 0 })
        XCTAssertGreaterThanOrEqual(plan.duration, plan.steps.last?.t ?? 0)
    }

    func testKeyUpBeforeDownIsClampedWithoutShiftingFollowingAbsoluteBlock() throws {
        let textID = UUID()
        let clickID = UUID()
        let plan = BlockExpander.plan(blocks: [
            .typeText(TypeTextBlock(
                id: textID,
                text: "a",
                keystrokes: [Keystroke(t: 2, keyCode: 4, chars: "a", upT: 1)],
                duration: 0.1
            )),
            .click(ClickBlock(
                id: clickID,
                x: 3,
                y: 4,
                button: .left,
                clickCount: 1,
                startOffset: 0.5
            )),
        ])

        let keyDown = try XCTUnwrap(plan.steps.first { step in
            if case .keyDown = step.action { return step.blockID == textID }
            return false
        })
        let keyUp = try XCTUnwrap(plan.steps.first { step in
            if case .keyUp = step.action { return step.blockID == textID }
            return false
        })
        let followingClick = try XCTUnwrap(plan.steps.first { step in
            if case .mouseDown = step.action { return step.blockID == clickID }
            return false
        })

        XCTAssertGreaterThanOrEqual(keyUp.t, keyDown.t)
        XCTAssertEqual(followingClick.t, 0.5, accuracy: 0.000_001)
        XCTAssertLessThan(followingClick.t, keyDown.t)
        XCTAssertGreaterThanOrEqual(plan.duration, plan.steps.last?.t ?? 0)
    }

    func testNonFiniteAndNegativeSampleTimesBecomeZero() {
        let plan = BlockExpander.plan(blocks: [
            .move(MoveBlock(
                duration: 0,
                points: [
                    TrackPoint(t: .nan, x: 1, y: 2),
                    TrackPoint(t: -1, x: 3, y: 4),
                ]
            )),
            .scroll(ScrollBlock(
                x: 5,
                y: 6,
                duration: 0,
                steps: [ScrollStep(t: .infinity, dx: 1, dy: -1)]
            )),
        ])

        XCTAssertEqual(plan.steps.map(\.t), [0, 0, 0])
        XCTAssertTrue(plan.steps.allSatisfy { $0.t.isFinite && $0.t >= 0 })
        XCTAssertEqual(plan.duration, 0)
    }

    func testSampleBeyondDeclaredDurationExtendsPlanWithoutShiftingAnotherBlock() throws {
        let clickID = UUID()
        let plan = BlockExpander.plan(blocks: [
            .move(MoveBlock(
                duration: 0.1,
                points: [TrackPoint(t: 3, x: 1, y: 2)]
            )),
            .click(ClickBlock(
                id: clickID,
                x: 3,
                y: 4,
                button: .left,
                clickCount: 1
            )),
        ])

        let clickDown = try XCTUnwrap(plan.steps.first { step in
            if case .mouseDown = step.action { return step.blockID == clickID }
            return false
        })

        XCTAssertEqual(clickDown.t, 0, accuracy: 0.000_001)
        XCTAssertEqual(plan.duration, 3, accuracy: 0.000_001)
        XCTAssertGreaterThanOrEqual(plan.duration, plan.steps.last?.t ?? 0)
    }

    func testHugeFiniteTimelineValuesClampWithoutOverflow() {
        let safeMaximum = Double(Int64.max) / 1_000_000_000 - 1
        let huge = Double.greatestFiniteMagnitude
        let plan = BlockExpander.plan(
            blocks: [
                .move(MoveBlock(
                    duration: huge,
                    points: [TrackPoint(t: huge, x: 1, y: 2)],
                    startOffset: huge
                )),
                .click(ClickBlock(
                    x: 3,
                    y: 4,
                    button: .left,
                    clickCount: 1,
                    startOffset: huge,
                    duration: huge
                )),
            ],
            trailingDelay: huge
        )

        XCTAssertEqual(plan.duration, safeMaximum, accuracy: 0.000_001)
        XCTAssertTrue(plan.steps.allSatisfy {
            $0.t.isFinite && $0.t >= 0 && $0.t <= safeMaximum
        })
        XCTAssertGreaterThanOrEqual(plan.duration, plan.steps.last?.t ?? 0)
    }

    func testCompatibilityExpandReturnsPlanSteps() {
        let blocks: [ActionBlock] = [
            .move(MoveBlock(duration: 0.2, points: [
                TrackPoint(t: 0, x: 0, y: 0),
                TrackPoint(t: 0.2, x: 100, y: 100),
            ])),
            .scroll(ScrollBlock(
                x: 5,
                y: 6,
                duration: 0.1,
                steps: [ScrollStep(t: 0, dx: 0, dy: -3)]
            )),
        ]

        XCTAssertEqual(
            BlockExpander.expand(blocks),
            BlockExpander.plan(blocks: blocks, trailingDelay: 0).steps
        )
    }
}

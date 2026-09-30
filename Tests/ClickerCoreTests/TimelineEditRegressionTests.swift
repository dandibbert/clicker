import Foundation
import XCTest
@testable import ClickerCore

final class TimelineEditRegressionTests: XCTestCase {
    private func click(
        start: TimeInterval = 0,
        duration: TimeInterval = 0.03,
        ordinal: Int = 0
    ) -> ActionBlock {
        .click(ClickBlock(
            x: 1, y: 2, button: .left, clickCount: 1,
            startOffset: start, duration: duration,
            downOrdinal: ordinal, upOrdinal: ordinal + 1
        ))
    }

    func testWaitDurationEditsRippleTheFullPlanAndKeepGapAndTrailingDelay() {
        let wait = WaitBlock(duration: 1, startOffset: 2)
        let original: [ActionBlock] = [.wait(wait), click(start: 3.25)]
        for duration in [5.0, 0.5, 0.0] {
            let blocks = TimelineMutation.replacing(
                at: 0, with: .wait(ActionBlockEditor.wait(wait, duration: duration)),
                in: original
            )
            let plan = BlockExpander.plan(blocks: blocks, trailingDelay: 0.75)
            XCTAssertEqual(blocks[0].startOffset, 2)
            XCTAssertEqual(blocks[1].startOffset, 2.25 + duration, accuracy: 0.000_001)
            XCTAssertEqual(plan.steps.map(\.blockID), [blocks[1].id, blocks[1].id])
            XCTAssertEqual(plan.steps.first?.t ?? -1, 2.25 + duration, accuracy: 0.000_001)
            XCTAssertEqual(plan.duration, 3.03 + duration, accuracy: 0.000_001)
        }
    }

    func testZeroDurationWaitCanGrowAtAnEqualStartBoundary() {
        let wait = WaitBlock(duration: 0, startOffset: 1)
        let blocks = TimelineMutation.replacing(
            at: 0, with: .wait(ActionBlockEditor.wait(wait, duration: 2)),
            in: [.wait(wait), click(start: 1)]
        )
        XCTAssertEqual(blocks.map(\.startOffset), [1, 3])
        XCTAssertEqual(BlockExpander.plan(blocks: blocks).steps.first?.t, 3)
    }

    func testMoveAndDragEditsRescaleSamplesAndRippleTheNextAction() {
        let points = [
            TrackPoint(t: 0, x: 0, y: 0, ordinal: 0),
            TrackPoint(t: 0.5, x: 4, y: 6, ordinal: 1),
            TrackPoint(t: 1, x: 10, y: 10, ordinal: 2),
        ]
        let move = MoveBlock(duration: 1, points: points, startOffset: 2)
        let drag = DragBlock(button: .left, duration: 1, points: points, startOffset: 2)
        for duration in [3.0, 0.25, 0.0] {
            let pairs: [(ActionBlock, ActionBlock)] = [
                (.move(move), .move(ActionBlockEditor.move(
                    move, endX: 10, endY: 10, duration: duration
                ))),
                (.drag(drag), .drag(ActionBlockEditor.drag(
                    drag, startX: 0, startY: 0, endX: 10, endY: 10, duration: duration
                ))),
            ]
            for (original, edited) in pairs {
                let blocks = TimelineMutation.replacing(
                    at: 0, with: edited, in: [original, click(start: 3, ordinal: 3)]
                )
                let plan = BlockExpander.plan(blocks: blocks, trailingDelay: 0.2)
                let firstSteps = plan.steps.filter { $0.blockID == original.id }
                let nextSteps = plan.steps.filter { $0.blockID == blocks[1].id }
                XCTAssertEqual(firstSteps.map(\.t), [2, 2 + duration / 2, 2 + duration])
                XCTAssertEqual(nextSteps.first?.t ?? -1, 2 + duration, accuracy: 0.000_001)
                XCTAssertEqual(plan.duration, 2.23 + duration, accuracy: 0.000_001)
                let boundary = plan.steps.filter { $0.t == 2 + duration }
                XCTAssertEqual(boundary.last?.blockID, blocks[1].id)
            }
        }
    }

    func testOverlapCohortStaysPutWhileFollowingSuffixKeepsItsOwnOverlaps() {
        let wait = WaitBlock(duration: 1, startOffset: 1)
        let original: [ActionBlock] = [
            click(start: 0, duration: 4, ordinal: 0),
            .wait(wait),
            click(start: 1.5, duration: 5.5, ordinal: 2),
            click(start: 8, duration: 1, ordinal: 4),
            click(start: 8.5, duration: 0.25, ordinal: 6),
        ]
        let longer = TimelineMutation.replacing(
            at: 1, with: .wait(ActionBlockEditor.wait(wait, duration: 8)), in: original
        )
        XCTAssertEqual(longer.map(\.startOffset), [0, 1, 1.5, 10, 10.5])
        XCTAssertEqual(longer[0], original[0])
        XCTAssertEqual(longer[2], original[2])
        XCTAssertEqual(longer.map(\.atomOrdinals), original.map(\.atomOrdinals))
        XCTAssertEqual(BlockExpander.plan(blocks: longer).duration, 11)

        let shorter = TimelineMutation.replacing(
            at: 1, with: .wait(ActionBlockEditor.wait(wait, duration: 0)), in: original
        )
        XCTAssertEqual(shorter.map(\.startOffset), original.map(\.startOffset))
        XCTAssertEqual(BlockExpander.plan(blocks: shorter).duration, 9)
    }

    func testShorteningTheLongestActionStopsAtTheOtherOverlappingActionEnd() {
        let wait = WaitBlock(duration: 10)
        let original: [ActionBlock] = [
            .wait(wait), click(start: 1, duration: 4, ordinal: 0),
            click(start: 10, ordinal: 2),
        ]
        let blocks = TimelineMutation.replacing(
            at: 0, with: .wait(ActionBlockEditor.wait(wait, duration: 2)), in: original
        )
        XCTAssertEqual(blocks.map(\.startOffset), [0, 1, 5])
        let boundary = BlockExpander.plan(blocks: blocks).steps.filter { $0.t == 5 }
        XCTAssertEqual(boundary.map(\.blockID), [blocks[1].id, blocks[2].id])
    }

    func testOverlapChainDeterminesTheSuffixBoundary() {
        let wait = WaitBlock(duration: 3)
        let original: [ActionBlock] = [
            .wait(wait), click(start: 2, duration: 2, ordinal: 0),
            click(start: 3.5, duration: 2, ordinal: 2), click(start: 6, ordinal: 4),
        ]
        let blocks = TimelineMutation.replacing(
            at: 0, with: .wait(ActionBlockEditor.wait(wait, duration: 8)), in: original
        )
        XCTAssertEqual(blocks.map(\.startOffset), [0, 2, 3.5, 8.5])
    }

    func testReplacementIgnoresAStaleStartAndNoOpLeavesTheWholeTimelineIdentical() {
        let original = [click(start: 2, duration: 1, ordinal: 8), click(start: 3, ordinal: 10)]
        XCTAssertEqual(TimelineMutation.replacing(at: 0, with: original[0], in: original), original)
        XCTAssertEqual(TimelineMutation.replacing(at: -1, with: original[0], in: original), original)
        XCTAssertEqual(TimelineMutation.replacing(at: 2, with: original[0], in: original), original)
        let result = TimelineMutation.replacing(
            at: 0, with: original[0].withStartOffset(99), in: original
        )
        XCTAssertEqual(result, original)
    }

    func testLongerEditedTextAppendsOnlyAfterItsCanonicalPlaybackEnd() {
        let initial = TypeTextBlock(text: "文本", keystrokes: [])
        let edited = ActionBlock.typeText(ActionBlockEditor.typeText(
            initial, text: "abcdefghijklmnopqrst"
        ))
        let blocks = TimelineMutation.inserting(click(), at: 1, in: [edited])
        let textPlan = BlockExpander.plan(blocks: [edited])
        XCTAssertEqual(edited.duration, 1.16, accuracy: 0.000_001)
        XCTAssertEqual(edited.effectiveDuration, textPlan.duration)
        XCTAssertEqual(blocks[1].startOffset, textPlan.duration)
        XCTAssertEqual(textPlan.steps.count, 40)
        XCTAssertEqual(Set(edited.atomOrdinals).count, 40)
    }

    func testTextEditsKeepClickTextClickBoundariesOrderedIncludingEmptyAndEmoji() throws {
        var blocks = TimelineMutation.inserting(
            .typeText(TypeTextBlock(text: "文本", keystrokes: [])), at: 1, in: [click()]
        )
        blocks = TimelineMutation.inserting(click(), at: 2, in: blocks)
        let firstID = blocks[0].id
        let textID = blocks[1].id
        let lastID = blocks[2].id
        for text in ["abcdefghijklmnopqrst", "x", "", "👨‍👩‍👧‍👦e\u{301}"] {
            guard case .typeText(let original) = blocks[1] else { return XCTFail("expected text") }
            blocks = TimelineMutation.replacing(
                at: 1, with: .typeText(ActionBlockEditor.typeText(original, text: text)), in: blocks
            )
            let plan = BlockExpander.plan(blocks: blocks)
            XCTAssertEqual(blocks[1].id, textID)
            XCTAssertEqual(blocks[2].startOffset, blocks[1].timelineEndOffset)
            XCTAssertEqual(plan.steps.filter { $0.blockID == textID }.count, text.count * 2)
            XCTAssertEqual(plan.steps.first?.blockID, firstID)
            XCTAssertEqual(plan.steps.last?.blockID, lastID)
            let openingBoundary = plan.steps.filter { $0.t == blocks[1].startOffset }
            XCTAssertEqual(openingBoundary.first?.action, .mouseUp(
                x: 1, y: 2, button: .left, clickCount: 1, flags: 0
            ))
            if !text.isEmpty {
                let closingBoundary = plan.steps.filter { $0.t == blocks[2].startOffset }
                XCTAssertEqual(closingBoundary.map(\.blockID), [textID, lastID])
                XCTAssertEqual(closingBoundary.first?.action, .keyUp(keyCode: 0, flags: 0))
            } else {
                XCTAssertEqual(openingBoundary.map(\.blockID), [firstID, lastID])
                XCTAssertEqual(openingBoundary.map(\.action), [
                    .mouseUp(x: 1, y: 2, button: .left, clickCount: 1, flags: 0),
                    .mouseDown(x: 1, y: 2, button: .left, clickCount: 1, flags: 0),
                ])
            }
            let encoded = try JSONEncoder().encode(Script(name: "Boundary", blocks: blocks))
            let decoded = try JSONDecoder().decode(Script.self, from: encoded)
            XCTAssertEqual(BlockExpander.plan(for: decoded), plan)
        }
    }

    func testGeneratedTextParticipatesInAppendDuplicateAndMoveOrdinals() {
        var blocks = [click()]
        for text in ["a", "👩🏽‍💻", "bc"] {
            blocks = TimelineMutation.inserting(
                .typeText(TypeTextBlock(text: text, keystrokes: [])), at: blocks.count, in: blocks
            )
        }
        blocks = TimelineMutation.inserting(click(), at: blocks.count, in: blocks)
        blocks = TimelineMutation.duplicating(at: 1, in: blocks)
        blocks = TimelineMutation.moving(from: 3, to: 1, in: blocks)
        blocks = TimelineMutation.moving(fromOffsets: IndexSet(integer: 2), toOffset: 4, in: blocks)
        let plan = BlockExpander.plan(blocks: blocks)
        XCTAssertEqual(Set(blocks.map(\.id)).count, blocks.count)
        XCTAssertEqual(Set(plan.steps.map(\.ordinal)).count, plan.steps.count)
        for index in 1..<blocks.count {
            XCTAssertEqual(blocks[index].startOffset, blocks[index - 1].timelineEndOffset)
            let boundary = plan.steps.filter { $0.t == blocks[index].startOffset }
            XCTAssertEqual(boundary.map(\.blockID), [blocks[index - 1].id, blocks[index].id])
        }
    }

    func testGeneratedEmojiUsesGraphemesAndEmptyTextHasNoAtomsOrDuration() {
        let emoji = TypeTextBlock(text: "👨‍👩‍👧‍👦e\u{301}", keystrokes: [])
        XCTAssertEqual(emoji.keystrokes.map(\.chars), ["👨‍👩‍👧‍👦", "e\u{301}"])
        XCTAssertEqual(emoji.keystrokes.map(\.t), [0, 0.06])
        XCTAssertEqual(emoji.duration, 0.08, accuracy: 0.000_001)
        let empty = ActionBlockEditor.typeText(emoji, text: "")
        XCTAssertTrue(empty.keystrokes.isEmpty)
        XCTAssertEqual(empty.duration, 0)
        XCTAssertEqual(BlockExpander.plan(blocks: [.typeText(empty)]), PlaybackPlan(steps: [], duration: 0))
    }

    func testStaleTextDurationStillUsesTheSameAtomsForMetadataAndExpansion() {
        var text = TypeTextBlock(text: "a", keystrokes: [])
        text.text = "abcdefghijklmnopqrst"
        let block = ActionBlock.typeText(text)
        XCTAssertEqual(block.effectiveDuration, BlockExpander.plan(blocks: [block]).duration)
        XCTAssertEqual(block.atomOrdinals.count, 40)
        let inserted = TimelineMutation.inserting(block, at: 1, in: [click()])
        guard case .typeText(let canonical) = inserted[1] else { return XCTFail("expected text") }
        XCTAssertEqual(canonical.keystrokes.map(\.chars).joined(), text.text)
        XCTAssertEqual(Set(canonical.keystrokes.flatMap { [$0.downOrdinal, $0.upOrdinal] }).count, 40)
    }

    func testRecordedTextNoOpKeepsPhysicalTimingFlagsAndRepeats() {
        let original = TypeTextBlock(text: "aa", keystrokes: [
            Keystroke(t: 0.1, keyCode: 12, chars: "a", upT: 0.8,
                      downFlags: 5, upFlags: 6, downOrdinal: 10, upOrdinal: 12),
            Keystroke(t: 0.3, keyCode: 12, chars: "a", upT: 0.8,
                      downFlags: 7, upFlags: 8, isRepeat: true, downOrdinal: 11, upOrdinal: 12),
        ], startOffset: 4, duration: 1)
        XCTAssertEqual(ActionBlockEditor.typeText(original, text: original.text), original)
    }

    func testReplacingRecordedTextRemovesEverySupersededCharacterFromSavedData() throws {
        let original = TypeTextBlock(text: "ΩЖ漢", keystrokes: [
            Keystroke(t: 0, keyCode: 1, chars: "Ω", upT: 0.1),
            Keystroke(t: 0.2, keyCode: 2, chars: "Ж", upT: 0.3),
            Keystroke(t: 0.4, keyCode: 3, chars: "漢", upT: 0.5),
        ])
        for replacement in ["safe", ""] {
            let edited = ActionBlockEditor.typeText(original, text: replacement)
            let data = try JSONEncoder().encode(edited)
            let json = try XCTUnwrap(String(data: data, encoding: .utf8))
            for oldCharacter in ["Ω", "Ж", "漢"] { XCTAssertFalse(json.contains(oldCharacter)) }
            let decoded = try JSONDecoder().decode(TypeTextBlock.self, from: data)
            XCTAssertEqual(decoded.keystrokes.map(\.chars).joined(), replacement)
            XCTAssertEqual(decoded, edited)
        }
    }

    func testOldMismatchedArchiveDropsHiddenKeystrokesOnDecodeAndResave() throws {
        let object: [String: Any] = [
            "id": UUID().uuidString, "text": "safe", "duration": 0.02,
            "keystrokes": [["t": 0, "keyCode": 2, "chars": "ΩЖ漢"]],
        ]
        let decoded = try JSONDecoder().decode(
            TypeTextBlock.self, from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.keystrokes.map(\.chars).joined(), "safe")
        let block = ActionBlock.typeText(decoded)
        XCTAssertEqual(block.effectiveDuration, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(block.effectiveDuration, BlockExpander.plan(blocks: [block]).duration)
        let saved = try JSONEncoder().encode(decoded)
        XCTAssertFalse(try XCTUnwrap(String(data: saved, encoding: .utf8)).contains("ΩЖ漢"))
    }

    func testTextReplacementPreservesSharedReleaseAcrossPrefixAndSuffix() throws {
        let held = ActionBlock.shortcut(ShortcutBlock(
            keyCode: 123, flags: 0, startOffset: 0, duration: 3,
            downOrdinal: 0, upOrdinal: 5
        ))
        let text = TypeTextBlock(text: "x", keystrokes: [
            Keystroke(t: 0, keyCode: 7, chars: "x", upT: 0.02,
                      downOrdinal: 1, upOrdinal: 2),
        ], startOffset: 1, duration: 0.02)
        let repeated = ActionBlock.shortcut(ShortcutBlock(
            keyCode: 123, flags: 0, startOffset: 2, duration: 1,
            isRepeat: true, downOrdinal: 3, upOrdinal: 5
        ))
        let sameTimeClick = ActionBlock.click(ClickBlock(
            x: 1, y: 2, button: .left, clickCount: 1,
            startOffset: 3, downOrdinal: 4, upOrdinal: 6
        ))
        let original: [ActionBlock] = [held, .typeText(text), repeated, sameTimeClick]
        let release = StepAction.keyUp(keyCode: 123, flags: 0)
        XCTAssertEqual(BlockExpander.plan(blocks: original).steps.filter {
            $0.action == release
        }.count, 1)

        for replacement in ["y", "longer", ""] {
            let blocks = TimelineMutation.replacing(
                at: 1, with: .typeText(ActionBlockEditor.typeText(text, text: replacement)),
                in: original
            )
            let plan = BlockExpander.plan(blocks: blocks)
            let releases = plan.steps.filter { $0.action == release }
            XCTAssertEqual(releases.count, 1)
            XCTAssertEqual(releases.first?.t, 3)
            // Retained equal-time events keep their captured cross-block order,
            // even though the key's shared release also occurs in the prefix.
            XCTAssertEqual(plan.steps.filter { $0.t == 3 }.map(\.action), [
                .mouseDown(x: 1, y: 2, button: .left, clickCount: 1, flags: 0),
                release,
            ])
            guard case .shortcut(let first) = blocks[0],
                  case .shortcut(let last) = blocks[2] else {
                return XCTFail("expected retained shortcuts")
            }
            XCTAssertEqual(first.upOrdinal, last.upOrdinal)
            XCTAssertLessThan(first.downOrdinal, last.downOrdinal)
            XCTAssertLessThan(last.downOrdinal, last.upOrdinal)
            XCTAssertTrue(plan.steps.contains { step in
                step.action == .keyDown(keyCode: 123, flags: 0, chars: "", isRepeat: true)
            })
            let decoded = try JSONDecoder().decode(Script.self, from: JSONEncoder().encode(
                Script(name: "Shared release", blocks: blocks)
            ))
            XCTAssertEqual(BlockExpander.plan(for: decoded), plan)
        }
    }

    func testTranslatingSharedEndWaitsForEveryRoundedRelease() throws {
        let oldAnchor = 3.76
        let oldEnd = 4.12
        let wait = WaitBlock(duration: oldAnchor)
        let first = click(start: oldAnchor, duration: oldEnd - oldAnchor, ordinal: 0)
        let secondStart = oldAnchor + 0.19
        let second = click(start: secondStart, duration: oldEnd - secondStart, ordinal: 2)
        let following = click(start: oldEnd, ordinal: 4)
        XCTAssertEqual(first.timelineEndOffset, oldEnd)
        XCTAssertEqual(second.timelineEndOffset, oldEnd)

        let blocks = TimelineMutation.replacing(
            at: 0, with: .wait(ActionBlockEditor.wait(wait, duration: 10.4)),
            in: [.wait(wait), first, second, following]
        )
        // These two mathematically equal ends differ by one representable value.
        // Do not let the later-visited block overwrite the latest release time.
        XCTAssertGreaterThan(blocks[1].timelineEndOffset, blocks[2].timelineEndOffset)
        XCTAssertEqual(blocks[3].startOffset, max(
            blocks[1].timelineEndOffset, blocks[2].timelineEndOffset
        ))
        let plan = BlockExpander.plan(blocks: blocks)
        let followingDownIndex = try XCTUnwrap(plan.steps.firstIndex { step in
            step.blockID == following.id && step.action == .mouseDown(
                x: 1, y: 2, button: .left, clickCount: 1, flags: 0
            )
        })
        for block in [first, second] {
            let releaseIndex = try XCTUnwrap(plan.steps.firstIndex { step in
                step.blockID == block.id && step.action == .mouseUp(
                    x: 1, y: 2, button: .left, clickCount: 1, flags: 0
                )
            })
            XCTAssertLessThan(releaseIndex, followingDownIndex)
        }
    }

    func testEditedTimelineSurvivesActualStoreSaveAndReloadWithIdenticalPlan() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClickerTimelineEdit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScriptStore(directory: directory)
        let wait = WaitBlock(duration: 1)
        var blocks: [ActionBlock] = [.wait(wait)]
        blocks = TimelineMutation.inserting(click(), at: 1, in: blocks)
        blocks = TimelineMutation.inserting(
            .typeText(TypeTextBlock(text: "old", keystrokes: [])), at: 2, in: blocks
        )
        blocks = TimelineMutation.inserting(click(), at: 3, in: blocks)
        blocks = TimelineMutation.replacing(
            at: 0, with: .wait(ActionBlockEditor.wait(wait, duration: 5)), in: blocks
        )
        guard case .typeText(let text) = blocks[2] else { return XCTFail("expected text") }
        blocks = TimelineMutation.replacing(
            at: 2, with: .typeText(ActionBlockEditor.typeText(text, text: "👩🏽‍💻abcdef")), in: blocks
        )
        let script = Script(name: "Edited", blocks: blocks, trailingDelay: 0.75)
        try store.save(script)
        let result = store.loadAll()
        XCTAssertTrue(result.issues.isEmpty)
        let loaded = try XCTUnwrap(result.scripts.first)
        XCTAssertEqual(loaded.id, script.id)
        XCTAssertEqual(loaded.blocks, script.blocks)
        XCTAssertEqual(BlockExpander.plan(for: loaded), BlockExpander.plan(for: script))
        XCTAssertEqual(loaded.trailingDelay, 0.75)
    }
}

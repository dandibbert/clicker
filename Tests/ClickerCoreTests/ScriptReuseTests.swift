import Foundation
import XCTest
@testable import ClickerCore

final class ScriptReuseTests: XCTestCase {
    private func click(start: TimeInterval, duration: TimeInterval = 1, ordinal: Int = 0) -> ActionBlock {
        .click(ClickBlock(x: 5, y: 10, button: .left, clickCount: 1,
                          startOffset: start, duration: duration,
                          downOrdinal: ordinal, upOrdinal: ordinal + 1))
    }

    func testDuplicatePreservesContentAndTimelineButGetsFreshInertIdentity() {
        let source = Script(
            name: "Original", blocks: [click(start: 2), click(start: 2.5, ordinal: 2)],
            repeatCount: 3, repeatForever: true, repeatInterval: 2, trailingDelay: 4,
            targetBundleIdentifier: "com.example.app", startApplicationBeforePlayback: true,
            playbackShortcut: ScriptShortcut(keyCode: 0, modifierFlags: KeyCodeMap.maskCommand),
            recordingInterruption: "Partial capture"
        )
        let now = Date(timeIntervalSince1970: 500)

        let copy = ScriptReuse.duplicate(source, name: "Copy", now: now)

        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertEqual(copy.name, "Copy")
        XCTAssertEqual(copy.createdAt, now)
        XCTAssertEqual(copy.modifiedAt, now)
        XCTAssertTrue(Set(copy.blocks.map(\.id)).isDisjoint(with: source.blocks.map(\.id)))
        XCTAssertEqual(copy.blocks.map(\.startOffset), source.blocks.map(\.startOffset))
        XCTAssertEqual(copy.blocks.map(\.duration), source.blocks.map(\.duration))
        XCTAssertEqual(copy.blocks.map(\.atomOrdinals), source.blocks.map(\.atomOrdinals))
        XCTAssertEqual(copy.targetBundleIdentifier, source.targetBundleIdentifier)
        XCTAssertEqual(copy.repeatCount, 3)
        XCTAssertTrue(copy.repeatForever)
        XCTAssertEqual(copy.repeatInterval, 2)
        XCTAssertEqual(copy.trailingDelay, 4)
        XCTAssertEqual(copy.recordingInterruption, "Partial capture")
        XCTAssertNil(copy.playbackShortcut)
        XCTAssertFalse(copy.startApplicationBeforePlayback)
        XCTAssertTrue(source.startApplicationBeforePlayback)
        XCTAssertNotNil(source.playbackShortcut)
    }

    func testCopyUsesExactSelectionInSourceOrderAndPreservesGapsAndOverlap() throws {
        let blocks = [click(start: 2, duration: 3), click(start: 2.5, ordinal: 2),
                      click(start: 3, ordinal: 4), click(start: 8, ordinal: 6)]
        let selected = Set([blocks[0].id, blocks[2].id, blocks[3].id, UUID()])

        let clipboard = try XCTUnwrap(ScriptReuse.copyActions(
            from: Script(name: "Source", blocks: blocks), selectedBlockIDs: selected
        ))

        XCTAssertEqual(clipboard.blocks.map(\.id), [blocks[0].id, blocks[2].id, blocks[3].id])
        XCTAssertEqual(clipboard.blocks.map(\.startOffset), [0, 1, 6])
        XCTAssertEqual(clipboard.blocks.map(\.duration), [3, 1, 1])
        XCTAssertEqual(clipboard.count, 3)
        XCTAssertFalse(clipboard.isEmpty)
    }

    func testEmptyOrStaleSelectionDoesNotBecomeWholeScript() {
        let script = Script(name: "Source", blocks: [click(start: 0)])
        XCTAssertNil(ScriptReuse.copyActions(from: script, selectedBlockIDs: []))
        XCTAssertNil(ScriptReuse.trial(script, selectedBlockIDs: [UUID()]))
        XCTAssertEqual(ScriptReuse.pasteActions(ActionClipboard(blocks: []), at: 0,
                                               in: script.blocks), script.blocks)
    }

    func testPastePreservesGroupAndSuffixRelativeTimelinesAndCreatesFreshIDsEachTime() {
        let copied = [click(start: 2, duration: 3, ordinal: 10),
                      click(start: 3, ordinal: 20), click(start: 7, ordinal: 30)]
        let clipboard = ActionClipboard(blocks: copied)
        let destination = [click(start: 0), click(start: 4, duration: 3, ordinal: 40),
                           click(start: 5, ordinal: 50)]

        let result = ScriptReuse.pasteActions(clipboard, at: 1, in: destination)
        let second = ScriptReuse.pasteActions(clipboard, at: 1, in: result)

        XCTAssertEqual(result.map(\.startOffset), [0, 1, 2, 6, 7, 8])
        XCTAssertEqual(result.map(\.duration), [1, 3, 1, 1, 3, 1])
        XCTAssertEqual([result[0].id, result[4].id, result[5].id], destination.map(\.id))
        let insertedIDs = Set(result[1...3].map(\.id))
        XCTAssertTrue(insertedIDs.isDisjoint(with: copied.map(\.id)))
        XCTAssertTrue(insertedIDs.isDisjoint(with: second[1...3].map(\.id)))
        XCTAssertEqual(Set(second.map(\.id)).count, second.count)
        XCTAssertEqual(clipboard.blocks.map(\.startOffset), [0, 1, 5])
    }

    func testPasteClampsRequestedIndexAndWorksInEmptyTimeline() {
        let source = ActionClipboard(blocks: [click(start: 2), click(start: 2.5, ordinal: 2)])
        let result = ScriptReuse.pasteActions(source, at: 100, in: [])
        XCTAssertEqual(result.map(\.startOffset), [0, 0.5])
        let before = ScriptReuse.pasteActions(source, at: -10, in: [click(start: 5)])
        XCTAssertEqual(before.map(\.startOffset), [0, 0.5, 1.5])
    }

    func testPasteOrdersInsertedReleaseBeforeSuffixPressAtExactBoundary() {
        let source = ActionClipboard(blocks: [click(start: 0, duration: 0.1, ordinal: 500)])
        let destination = [click(start: 0, duration: 0.2, ordinal: 10),
                           click(start: 2, duration: 0.1, ordinal: 20)]
        let result = ScriptReuse.pasteActions(source, at: 1, in: destination)
        let boundary = result[2].startOffset
        let steps = BlockExpander.plan(blocks: result).steps.filter { $0.t == boundary }
        XCTAssertEqual(steps.map(\.blockID), [result[1].id, result[2].id])
        XCTAssertLessThan(steps[0].ordinal, steps[1].ordinal)
    }

    func testPasteKeepsSharedAutorepeatReleaseAndDistinctCopyOrdinals() {
        let initial = ActionBlock.shortcut(ShortcutBlock(
            keyCode: 0, flags: 0, startOffset: 1, duration: 1,
            downOrdinal: 10, upOrdinal: 30
        ))
        let repeated = ActionBlock.shortcut(ShortcutBlock(
            keyCode: 0, flags: 0, startOffset: 1.5, duration: 0.5,
            isRepeat: true, downOrdinal: 20, upOrdinal: 30
        ))
        let clipboard = ActionClipboard(blocks: [initial, repeated])
        let result = ScriptReuse.pasteActions(clipboard, at: 2, in: [initial, repeated])
        let plan = BlockExpander.plan(blocks: result)
        let releases = plan.steps.filter {
            if case .keyUp = $0.action { return true }
            return false
        }
        XCTAssertEqual(releases.count, 2)
        XCTAssertEqual(releases.map(\.t), [2, 3])
        XCTAssertTrue(Set(result[0...1].flatMap(\.atomOrdinals)).isDisjoint(
            with: result[2...3].flatMap(\.atomOrdinals)
        ))
    }

    func testPasteAfterLongHeldPrefixOrdersReleaseBeforeInsertedPress() {
        let prefix = click(start: 0, duration: 10, ordinal: 100)
        let suffix = click(start: 1, duration: 1, ordinal: 20)
        let copied = ActionClipboard(blocks: [click(start: 0, duration: 0.5)])
        let result = ScriptReuse.pasteActions(copied, at: 1, in: [prefix, suffix])
        let boundary = BlockExpander.plan(blocks: result).steps.filter { $0.t == 10 }
        XCTAssertEqual(boundary.map(\.blockID), [prefix.id, result[1].id])
        XCTAssertEqual(result.map(\.startOffset), [0, 10, 10.5])
    }

    func testPasteCompactsMaximumOrdinalsWithoutWrappingBoundaryOrder() {
        let prefix = ActionBlock.shortcut(ShortcutBlock(
            keyCode: 0, flags: 0, duration: 1,
            downOrdinal: Int.max - 1, upOrdinal: Int.max
        ))
        let clipboard = ActionClipboard(blocks: [click(start: 0)])
        let result = ScriptReuse.pasteActions(clipboard, at: 1, in: [prefix])
        let boundary = BlockExpander.plan(blocks: result).steps.filter { $0.t == 1 }
        XCTAssertEqual(boundary.map(\.blockID), [prefix.id, result[1].id])
        XCTAssertTrue(result.flatMap(\.atomOrdinals).allSatisfy { $0 < Int.max })
    }

    func testTrialRunsOnlySelectedBlocksOnceWithRelevantReleaseAndNoTrailingDelay() throws {
        let initial = ActionBlock.shortcut(ShortcutBlock(
            keyCode: 0, flags: 0, startOffset: 4, duration: 2,
            downOrdinal: 10, upOrdinal: 50
        ))
        let unrelated = click(start: 4.5, duration: 20, ordinal: 20)
        let repeated = ActionBlock.shortcut(ShortcutBlock(
            keyCode: 0, flags: 0, startOffset: 5, duration: 1,
            isRepeat: true, downOrdinal: 30, upOrdinal: 50
        ))
        let script = Script(name: "Trial", blocks: [initial, unrelated, repeated],
                            repeatCount: 20, repeatForever: true, repeatInterval: 5,
                            trailingDelay: 100,
                            playbackShortcut: ScriptShortcut(keyCode: 5, modifierFlags: 0))

        let trial = try XCTUnwrap(ScriptReuse.trial(script, selectedBlockIDs: [repeated.id]))
        let plan = BlockExpander.plan(for: trial)

        XCTAssertEqual(trial.id, script.id)
        XCTAssertEqual(trial.blocks.map(\.id), [repeated.id])
        XCTAssertEqual(trial.blocks.map(\.startOffset), [0])
        XCTAssertEqual(trial.repeatCount, 1)
        XCTAssertFalse(trial.repeatForever)
        XCTAssertEqual(trial.repeatInterval, 0)
        XCTAssertEqual(trial.trailingDelay, 0)
        XCTAssertNil(trial.playbackShortcut)
        XCTAssertEqual(plan.duration, 1)
        XCTAssertEqual(plan.steps.map(\.blockID), [repeated.id, repeated.id])
        XCTAssertEqual(plan.steps.map(\.action), [
            .keyDown(keyCode: 0, flags: 0, chars: "", isRepeat: true),
            .keyUp(keyCode: 0, flags: 0)
        ])
        XCTAssertEqual(script.blocks.count, 3)
        XCTAssertTrue(script.repeatForever)
    }

    func testTrialOfWaitOnlyPreservesWaitDuration() throws {
        let wait = ActionBlock.wait(WaitBlock(duration: 3, startOffset: 9))
        let trial = try XCTUnwrap(ScriptReuse.trial(
            Script(name: "Wait", blocks: [wait], trailingDelay: 10), selectedBlockIDs: [wait.id]
        ))
        XCTAssertEqual(BlockExpander.plan(for: trial), PlaybackPlan(steps: [], duration: 3))
    }
}

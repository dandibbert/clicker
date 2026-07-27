import Foundation
import XCTest
@testable import ClickerCore

final class TimelineMutationTests: XCTestCase {
    private func click(
        id: UUID = UUID(),
        start: TimeInterval,
        duration: TimeInterval
    ) -> ActionBlock {
        .click(ClickBlock(
            id: id,
            x: 0,
            y: 0,
            button: .left,
            clickCount: 1,
            startOffset: start,
            duration: duration
        ))
    }

    func testInsertTranslatesSuffixAndPreservesItsRelativeTiming() {
        let original = [
            click(start: 0, duration: 1),
            click(start: 2, duration: 1),
            click(start: 4, duration: 1),
        ]
        let inserted = ActionBlock.wait(WaitBlock(duration: 0.5))

        let result = TimelineMutation.inserting(inserted, at: 1, in: original)

        XCTAssertEqual(result.map(\.startOffset), [0, 1, 1.5, 3.5])
        XCTAssertEqual(
            result[3].startOffset - result[2].startOffset,
            original[2].startOffset - original[1].startOffset,
            accuracy: 0.000_001
        )
    }

    func testDeleteJoinsPrefixAndSuffixWhilePreservingSuffixTiming() {
        let original = [
            click(start: 0, duration: 1),
            click(start: 2, duration: 1),
            click(start: 4, duration: 1),
            click(start: 5, duration: 1),
        ]

        let result = TimelineMutation.deleting(at: 1, in: original)

        XCTAssertEqual(result.map(\.startOffset), [0, 1, 2])
        XCTAssertEqual(
            result[2].startOffset - result[1].startOffset,
            original[3].startOffset - original[2].startOffset,
            accuracy: 0.000_001
        )
    }

    func testDuplicateGetsFreshIdentityAndMovesTheSuffix() {
        let firstID = UUID()
        let copiedID = UUID()
        let original = [
            click(id: firstID, start: 0, duration: 1),
            click(id: copiedID, start: 2, duration: 1),
            click(start: 4, duration: 1),
        ]

        let result = TimelineMutation.duplicating(at: 1, in: original)

        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result.map(\.startOffset), [0, 2, 3, 4])
        XCTAssertEqual(result[1].id, copiedID)
        XCTAssertNotEqual(result[2].id, copiedID)
        XCTAssertEqual(result[1].duration, result[2].duration)
    }

    func testDuplicateGetsFreshOrdinalsWithoutChangingTheOriginal() throws {
        let copiedID = UUID()
        let original: [ActionBlock] = [
            .click(ClickBlock(
                x: 0,
                y: 0,
                button: .left,
                clickCount: 1,
                startOffset: 0,
                duration: 0.1,
                downOrdinal: 10,
                upOrdinal: 11
            )),
            .click(ClickBlock(
                id: copiedID,
                x: 1,
                y: 1,
                button: .right,
                clickCount: 1,
                startOffset: 1,
                duration: 0.1,
                downOrdinal: 20,
                upOrdinal: 21
            )),
            .click(ClickBlock(
                x: 2,
                y: 2,
                button: .left,
                clickCount: 1,
                startOffset: 2,
                duration: 0.1,
                downOrdinal: 30,
                upOrdinal: 31
            )),
        ]

        let result = TimelineMutation.duplicating(at: 1, in: original)
        let duplicateID = result[2].id
        let plan = BlockExpander.plan(blocks: result)
        let originalOrdinals = plan.steps
            .filter { $0.blockID == copiedID }
            .map(\.ordinal)
        let duplicateOrdinals = plan.steps
            .filter { $0.blockID == duplicateID }
            .map(\.ordinal)

        XCTAssertEqual(originalOrdinals, [20, 21])
        XCTAssertEqual(duplicateOrdinals.count, 2)
        XCTAssertTrue(duplicateOrdinals.allSatisfy { $0 > 21 })
        XCTAssertTrue(Set(originalOrdinals).isDisjoint(with: duplicateOrdinals))
    }

    func testMoveRebasesTheMovedBlockAndTranslatesTheRemainingSuffix() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let original = [
            click(id: firstID, start: 0, duration: 1),
            click(id: secondID, start: 2, duration: 1),
            click(id: thirdID, start: 4, duration: 1),
        ]

        let result = TimelineMutation.moving(from: 2, to: 0, in: original)

        XCTAssertEqual(result.map(\.id), [thirdID, firstID, secondID])
        XCTAssertEqual(result.map(\.startOffset), [0, 1, 3])
        XCTAssertGreaterThanOrEqual(result[1].startOffset, result[0].timelineEndOffset)
    }

    func testInsertionOrdersInsertedReleaseBeforeTranslatedSuffixDownAtBoundary() {
        let insertedID = UUID()
        let suffixID = UUID()
        let original: [ActionBlock] = [
            .click(ClickBlock(
                x: 0,
                y: 0,
                button: .left,
                clickCount: 1,
                startOffset: 0,
                duration: 1,
                downOrdinal: 10,
                upOrdinal: 11
            )),
            .click(ClickBlock(
                id: suffixID,
                x: 2,
                y: 2,
                button: .right,
                clickCount: 1,
                startOffset: 2,
                duration: 1,
                downOrdinal: 20,
                upOrdinal: 21
            )),
        ]
        let inserted = ActionBlock.click(ClickBlock(
            id: insertedID,
            x: 1,
            y: 1,
            button: .left,
            clickCount: 1,
            duration: 1
        ))

        let result = TimelineMutation.inserting(inserted, at: 1, in: original)
        let boundarySteps = BlockExpander.plan(blocks: result).steps.filter {
            abs($0.t - 2) < 0.000_001
        }

        XCTAssertEqual(boundarySteps.map(\.blockID), [insertedID, suffixID])
        XCTAssertEqual(boundarySteps.map(\.action), [
            .mouseUp(x: 1, y: 1, button: .left, clickCount: 1, flags: 0),
            .mouseDown(x: 2, y: 2, button: .right, clickCount: 1, flags: 0),
        ])
    }

    func testInsertAfterLongOverlapCannotRetainAStaleOverlapAtTheSplice() {
        let original = [
            click(start: 0, duration: 10),
            click(start: 1, duration: 1),
        ]

        let result = TimelineMutation.inserting(
            .wait(WaitBlock(duration: 1)),
            at: 1,
            in: original
        )

        XCTAssertEqual(result.map(\.startOffset), [0, 10, 11])
        XCTAssertGreaterThanOrEqual(result[2].startOffset, result[1].timelineEndOffset)
    }
}

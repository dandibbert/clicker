import Foundation
import XCTest
@testable import ClickerCore

final class DragGeometryRegressionTests: XCTestCase {
    private func drag(_ coordinates: [(Double, Double)]) -> DragBlock {
        DragBlock(
            button: .right,
            duration: 1,
            points: coordinates.enumerated().map { index, coordinate in
                TrackPoint(
                    t: Double(index) / Double(coordinates.count - 1),
                    x: coordinate.0, y: coordinate.1,
                    flags: UInt64(index + 1), ordinal: index + 10
                )
            },
            startOffset: 3,
            hasRecordedMouseUp: true,
            upOrdinal: coordinates.count + 9
        )
    }

    func testClosedCurveNoOpPreservesEveryPointAndTheFullPlaybackPlan() throws {
        let original = drag([(10, 20), (110, 220), (-30, 70), (10, 20)])
        let edited = ActionBlockEditor.drag(
            original, startX: 10, startY: 20, endX: 10, endY: 20, duration: 1
        )
        XCTAssertEqual(edited, original)
        XCTAssertEqual(
            BlockExpander.plan(blocks: [.drag(edited)]),
            BlockExpander.plan(blocks: [.drag(original)])
        )
        let data = try JSONEncoder().encode(edited)
        XCTAssertEqual(try JSONDecoder().decode(DragBlock.self, from: data), original)
    }

    func testDurationOnlyEditPreservesAllCoordinatesFlagsAndOrdinalsForBothAxes() {
        let originals = [
            drag([(10, 20), (110, 220), (10, 20)]),
            drag([(10, 20), (110, 220), (10, 50)]),
            drag([(10, 20), (110, 220), (50, 20)]),
            drag([(10, 20), (110, 220), (50, 60)]),
        ]
        for original in originals {
            guard let first = original.points.first, let last = original.points.last else {
                return XCTFail("expected points")
            }
            for duration in [2.0, 0.5, 0.0] {
                let edited = ActionBlockEditor.drag(
                    original, startX: first.x, startY: first.y,
                    endX: last.x, endY: last.y, duration: duration
                )
                XCTAssertEqual(edited.points.map(\.x), original.points.map(\.x))
                XCTAssertEqual(edited.points.map(\.y), original.points.map(\.y))
                XCTAssertEqual(edited.points.map(\.flags), original.points.map(\.flags))
                XCTAssertEqual(edited.points.map(\.ordinal), original.points.map(\.ordinal))
                XCTAssertEqual(edited.points.map(\.t), [0, duration / 2, duration])
                XCTAssertEqual(edited.upOrdinal, original.upOrdinal)
                XCTAssertEqual(edited.startOffset, original.startOffset)
                XCTAssertEqual(edited.hasRecordedMouseUp, original.hasRecordedMouseUp)
            }
        }
    }

    func testTranslatingClosedCurveKeepsItsExcursion() {
        let original = drag([(0, 0), (100, -100), (0, 0)])
        let edited = ActionBlockEditor.drag(
            original, startX: 20, startY: 30, endX: 20, endY: 30, duration: 1
        )
        XCTAssertEqual(edited.points.map(\.x), [20, 120, 20])
        XCTAssertEqual(edited.points.map(\.y), [30, -70, 30])
        XCTAssertEqual(edited.points.map(\.t), original.points.map(\.t))
    }

    func testOpeningClosedAxisAddsEndpointDisplacementWithoutFlatteningResidual() {
        let original = drag([(0, 10), (100, 30), (0, 50)])
        let edited = ActionBlockEditor.drag(
            original, startX: 10, startY: 10, endX: 30, endY: 50, duration: 1
        )
        XCTAssertEqual(edited.points.map(\.x), [10, 120, 30])
        XCTAssertEqual(edited.points.map(\.y), [10, 30, 50])
    }

    func testOpeningClosedYAxisKeepsResidualAndOtherAxisScalesNormally() {
        let original = drag([(10, 0), (30, 100), (50, 0)])
        let edited = ActionBlockEditor.drag(
            original, startX: 20, startY: 10, endX: 100, endY: 30, duration: 1
        )
        XCTAssertEqual(edited.points.map(\.x), [20, 60, 100])
        XCTAssertEqual(edited.points.map(\.y), [10, 120, 30])
    }

    func testClosedAxisWithEqualSampleTimesUsesSampleIndexProgress() {
        var original = drag([(0, 0), (100, 100), (0, 0)])
        for index in original.points.indices { original.points[index].t = 0 }
        original.duration = 0
        let edited = ActionBlockEditor.drag(
            original, startX: 10, startY: 20, endX: 30, endY: 40, duration: 2
        )
        XCTAssertEqual(edited.points.map(\.x), [10, 120, 30])
        XCTAssertEqual(edited.points.map(\.y), [20, 130, 40])
        XCTAssertEqual(edited.points.map(\.t), [0, 1, 2])
    }

    func testUnchangedNonClosedAxisDoesNotAcquireFloatingPointCoordinateDrift() {
        let original = drag([(0.1, 0.2), (0.123456789, 0.234567891), (0.3, 0.4)])
        let edited = ActionBlockEditor.drag(
            original, startX: 0.1, startY: 0.2, endX: 0.3, endY: 0.4, duration: 3
        )
        XCTAssertEqual(edited.points.map(\.x), original.points.map(\.x))
        XCTAssertEqual(edited.points.map(\.y), original.points.map(\.y))
    }

    func testOnePointNoOpDoesNotInventASecondPoint() {
        let original = DragBlock(
            button: .left, duration: 1,
            points: [TrackPoint(t: 0, x: 10, y: 20, flags: 4, ordinal: 8)],
            hasRecordedMouseUp: false, upOrdinal: 9
        )
        let edited = ActionBlockEditor.drag(
            original, startX: 10, startY: 20, endX: 10, endY: 20, duration: 1
        )
        XCTAssertEqual(edited, original)
        let retimed = ActionBlockEditor.drag(
            original, startX: 10, startY: 20, endX: 10, endY: 20, duration: 2
        )
        XCTAssertEqual(retimed.points, original.points)
        XCTAssertEqual(retimed.duration, 2)
        XCTAssertEqual(retimed.upOrdinal, 9)
    }
}

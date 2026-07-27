import CoreGraphics
import XCTest
@testable import Clicker
import ClickerCore

final class MenuBarRecordingCutoffControllerTests: XCTestCase {
    func testOpeningMenuEstablishesCutoffAndStopSelectionUsesItLater() {
        let expected = RecordingCutoff(eventCount: 3, duration: 1.25)
        var establishedAt: [CGEventTimestamp] = []
        var stoppedAt: [RecordingCutoff] = []
        let controller = MenuBarRecordingCutoffController(
            establishCutoff: { timestamp in
                establishedAt.append(timestamp)
                return expected
            },
            stopRecording: { cutoff in
                stoppedAt.append(cutoff)
            }
        )

        controller.menuWillOpen(at: 5_000)

        XCTAssertEqual(establishedAt, [5_000])
        XCTAssertTrue(stoppedAt.isEmpty)

        controller.stopSelected()

        XCTAssertEqual(stoppedAt, [expected])
    }

    func testMenuOpenKeepsCutoffEstablishedWhenPointerEnteredStatusItem() {
        let expected = RecordingCutoff(eventCount: 2, duration: 1)
        var establishedAt: [CGEventTimestamp] = []
        let controller = MenuBarRecordingCutoffController(
            establishCutoff: { timestamp in
                establishedAt.append(timestamp)
                return expected
            },
            stopRecording: { _ in }
        )

        controller.interactionBegan(at: 4_000)
        controller.menuWillOpen(at: 5_000)

        XCTAssertEqual(establishedAt, [4_000])
    }
}

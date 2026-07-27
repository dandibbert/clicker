import XCTest
@testable import ClickerCore

final class RecordingCaptureTests: XCTestCase {
    func testDurationIsAlwaysFiniteAndNonnegative() {
        XCTAssertEqual(RecordingCapture(events: [], duration: -1).duration, 0)
        XCTAssertEqual(RecordingCapture(events: [], duration: .nan).duration, 0)
        XCTAssertEqual(RecordingCapture(events: [], duration: .infinity).duration, 0)
        XCTAssertEqual(RecordingCapture(events: [], duration: 1.25).duration, 1.25)
    }

    func testCutoffIsAlwaysFiniteAndNonnegative() {
        let invalid = RecordingCutoff(eventCount: -2, duration: -.infinity)
        XCTAssertEqual(invalid.eventCount, 0)
        XCTAssertEqual(invalid.duration, 0)

        let valid = RecordingCutoff(eventCount: 3, duration: 1.25)
        XCTAssertEqual(valid.eventCount, 3)
        XCTAssertEqual(valid.duration, 1.25)
    }
}

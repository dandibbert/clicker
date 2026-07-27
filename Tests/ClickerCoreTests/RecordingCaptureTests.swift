import XCTest
@testable import ClickerCore

final class RecordingCaptureTests: XCTestCase {
    func testDurationIsAlwaysFiniteAndNonnegative() {
        XCTAssertEqual(RecordingCapture(events: [], duration: -1).duration, 0)
        XCTAssertEqual(RecordingCapture(events: [], duration: .nan).duration, 0)
        XCTAssertEqual(RecordingCapture(events: [], duration: .infinity).duration, 0)
        XCTAssertEqual(RecordingCapture(events: [], duration: 1.25).duration, 1.25)
    }
}

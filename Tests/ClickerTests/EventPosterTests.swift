import XCTest
@testable import Clicker

final class EventPosterTests: XCTestCase {
    func testScrollDeltaMapsNonFiniteValuesToZero() {
        XCTAssertEqual(EventPoster.scrollDelta(.nan), 0)
        XCTAssertEqual(EventPoster.scrollDelta(.infinity), 0)
        XCTAssertEqual(EventPoster.scrollDelta(-.infinity), 0)
    }

    func testScrollDeltaTruncatesAndClampsToInt32Range() {
        XCTAssertEqual(EventPoster.scrollDelta(12.9), 12)
        XCTAssertEqual(EventPoster.scrollDelta(-12.9), -12)
        XCTAssertEqual(EventPoster.scrollDelta(Double(Int32.max) + 1_000), Int32.max)
        XCTAssertEqual(EventPoster.scrollDelta(Double(Int32.min) - 1_000), Int32.min)
    }
}

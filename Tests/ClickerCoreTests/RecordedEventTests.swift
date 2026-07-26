import XCTest
@testable import ClickerCore

final class RecordedEventTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let e = RecordedEvent(t: 1.25, kind: .leftDown, x: 100, y: 200,
                              keyCode: 0, flags: 0, chars: "", clickCount: 2,
                              scrollDX: 0, scrollDY: 0)
        let data = try JSONEncoder().encode(e)
        let back = try JSONDecoder().decode(RecordedEvent.self, from: data)
        XCTAssertEqual(e, back)
    }

    func testDefaults() {
        let e = RecordedEvent(t: 0, kind: .mouseMove, x: 1, y: 2)
        XCTAssertEqual(e.keyCode, 0)
        XCTAssertEqual(e.chars, "")
        XCTAssertEqual(e.clickCount, 0)
    }
}

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

    func testLegacyJSONDefaultsAutorepeatToFalse() throws {
        let data = Data(#"{"t":1.25,"kind":"keyDown","x":0,"y":0,"keyCode":0,"flags":0,"chars":"a","clickCount":0,"scrollDX":0,"scrollDY":0}"#.utf8)

        let event = try JSONDecoder().decode(RecordedEvent.self, from: data)

        XCTAssertFalse(event.isRepeat)
    }

    func testDefaults() {
        let e = RecordedEvent(t: 0, kind: .mouseMove, x: 1, y: 2)
        XCTAssertEqual(e.keyCode, 0)
        XCTAssertEqual(e.chars, "")
        XCTAssertEqual(e.clickCount, 0)
    }
}

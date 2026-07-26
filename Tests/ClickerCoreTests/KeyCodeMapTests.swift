import XCTest
@testable import ClickerCore

final class KeyCodeMapTests: XCTestCase {
    func testLetterKey() {
        XCTAssertEqual(KeyCodeMap.name(for: 0), "A")
        XCTAssertEqual(KeyCodeMap.name(for: 8), "C")
    }

    func testSpecialKeys() {
        XCTAssertEqual(KeyCodeMap.name(for: 36), "Return")
        XCTAssertEqual(KeyCodeMap.name(for: 49), "Space")
        XCTAssertEqual(KeyCodeMap.name(for: 53), "Esc")
        XCTAssertEqual(KeyCodeMap.name(for: 51), "Delete")
    }

    func testUnknownKey() {
        XCTAssertEqual(KeyCodeMap.name(for: 999), "Key999")
    }

    func testShortcutDisplay() {
        // ⌘ = maskCommand (1 << 20), ⇧ = maskShift (1 << 17)
        XCTAssertEqual(KeyCodeMap.shortcutDisplay(keyCode: 8, flags: 1 << 20), "⌘C")
        XCTAssertEqual(KeyCodeMap.shortcutDisplay(keyCode: 8, flags: (1 << 20) | (1 << 17)), "⇧⌘C")
    }

    func testModifierFlagConstants() {
        XCTAssertEqual(KeyCodeMap.maskShift, 1 << 17)
        XCTAssertEqual(KeyCodeMap.maskControl, 1 << 18)
        XCTAssertEqual(KeyCodeMap.maskOption, 1 << 19)
        XCTAssertEqual(KeyCodeMap.maskCommand, 1 << 20)
    }
}

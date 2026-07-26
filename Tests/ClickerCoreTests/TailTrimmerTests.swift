import XCTest
@testable import ClickerCore

final class TailTrimmerTests: XCTestCase {
    func ev(_ t: TimeInterval, _ kind: EventKind, x: Double = 0, y: Double = 0,
            keyCode: UInt16 = 0, flags: UInt64 = 0) -> RecordedEvent {
        RecordedEvent(t: t, kind: kind, x: x, y: y, keyCode: keyCode, flags: flags)
    }

    func testTrimHotKeyStop() {
        // ⌥⌘R = keyCode 15 + option+command
        let stopFlags = KeyCodeMap.maskOption | KeyCodeMap.maskCommand
        let events = [
            ev(0, .leftDown, x: 1, y: 1), ev(0.1, .leftUp, x: 1, y: 1),
            ev(1.0, .flagsChanged, keyCode: 58, flags: KeyCodeMap.maskOption),
            ev(1.1, .flagsChanged, keyCode: 55, flags: stopFlags),
            ev(1.2, .keyDown, keyCode: 15, flags: stopFlags),
            ev(1.3, .keyUp, keyCode: 15, flags: stopFlags),
        ]
        let trimmed = TailTrimmer.trimHotKeyStop(events, stopKeyCode: 15, stopFlags: stopFlags)
        XCTAssertEqual(trimmed.count, 2)
        XCTAssertEqual(trimmed.last?.kind, .leftUp)
    }

    func testTrimHotKeyStopKeepsUnrelatedKeys() {
        let stopFlags = KeyCodeMap.maskOption | KeyCodeMap.maskCommand
        let events = [
            ev(0, .keyDown, keyCode: 4), ev(0.1, .keyUp, keyCode: 4),
            ev(1.2, .keyDown, keyCode: 15, flags: stopFlags),
        ]
        let trimmed = TailTrimmer.trimHotKeyStop(events, stopKeyCode: 15, stopFlags: stopFlags)
        XCTAssertEqual(trimmed.count, 2)
        XCTAssertEqual(trimmed.first?.keyCode, 4)
    }

    func testTrimMenuBarStop() {
        let events = [
            ev(0, .leftDown, x: 100, y: 500), ev(0.1, .leftUp, x: 100, y: 500),
            // 移动去菜单栏
            ev(0.5, .mouseMove, x: 200, y: 300),
            ev(0.6, .mouseMove, x: 500, y: 50),
            ev(0.7, .mouseMove, x: 800, y: 10),
            // 点菜单栏图标
            ev(0.8, .leftDown, x: 800, y: 10), ev(0.9, .leftUp, x: 800, y: 10),
        ]
        let trimmed = TailTrimmer.trimMenuBarStop(events)
        XCTAssertEqual(trimmed.count, 2)
        XCTAssertEqual(trimmed.last?.kind, .leftUp)
        XCTAssertEqual(trimmed.last?.x, 100)
    }

    func testTrimMenuBarStopNoTrailingClick() {
        // 尾部没有点击（如通过快捷键停但走了菜单栏路径）：原样返回
        let events = [ev(0, .mouseMove, x: 1, y: 1)]
        XCTAssertEqual(TailTrimmer.trimMenuBarStop(events).count, 1)
    }

    func testEmpty() {
        XCTAssertTrue(TailTrimmer.trimHotKeyStop([], stopKeyCode: 15, stopFlags: 0).isEmpty)
        XCTAssertTrue(TailTrimmer.trimMenuBarStop([]).isEmpty)
    }
}

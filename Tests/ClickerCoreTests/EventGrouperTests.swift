import XCTest
@testable import ClickerCore

final class EventGrouperTests: XCTestCase {

    // 辅助：构造事件
    func ev(_ t: TimeInterval, _ kind: EventKind, x: Double = 0, y: Double = 0,
            keyCode: UInt16 = 0, flags: UInt64 = 0, chars: String = "",
            clicks: Int = 1, dx: Double = 0, dy: Double = 0) -> RecordedEvent {
        RecordedEvent(t: t, kind: kind, x: x, y: y, keyCode: keyCode, flags: flags,
                      chars: chars, clickCount: clicks, scrollDX: dx, scrollDY: dy)
    }

    func testEmptyInput() {
        XCTAssertTrue(EventGrouper.group([]).isEmpty)
    }

    func testSimpleClick() {
        let blocks = EventGrouper.group([
            ev(0, .leftDown, x: 100, y: 200),
            ev(0.1, .leftUp, x: 100, y: 200),
        ])
        guard case .click(let c) = blocks.first else { return XCTFail("expected click, got \(blocks)") }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(c.x, 100); XCTAssertEqual(c.y, 200)
        XCTAssertEqual(c.button, .left); XCTAssertEqual(c.clickCount, 1)
    }

    func testDoubleClickKeepsClickCount() {
        let blocks = EventGrouper.group([
            ev(0, .leftDown, x: 10, y: 10, clicks: 1), ev(0.05, .leftUp, x: 10, y: 10, clicks: 1),
            ev(0.2, .leftDown, x: 10, y: 10, clicks: 2), ev(0.25, .leftUp, x: 10, y: 10, clicks: 2),
        ])
        // 两次 down/up 产生两个 click 块，第二个 clickCount = 2
        XCTAssertEqual(blocks.count, 2)
        guard case .click(let c2) = blocks[1] else { return XCTFail() }
        XCTAssertEqual(c2.clickCount, 2)
    }

    func testMouseMoveMerged() {
        let blocks = EventGrouper.group([
            ev(0, .mouseMove, x: 0, y: 0),
            ev(0.1, .mouseMove, x: 50, y: 50),
            ev(0.2, .mouseMove, x: 100, y: 100),
        ])
        guard case .move(let m) = blocks.first else { return XCTFail("expected move, got \(blocks)") }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(m.points.count, 3)
        XCTAssertEqual(m.points.first?.x, 0)
        XCTAssertEqual(m.points.last?.x, 100)
        XCTAssertEqual(m.duration, 0.2, accuracy: 0.001)
        // 轨迹点 t 相对块起点
        XCTAssertEqual(m.points.first?.t, 0)
        XCTAssertEqual(m.points.last?.t ?? -1, 0.2, accuracy: 0.001)
    }

    func testDrag() {
        let blocks = EventGrouper.group([
            ev(0, .leftDown, x: 100, y: 100),
            ev(0.1, .leftDrag, x: 150, y: 150),
            ev(0.2, .leftDrag, x: 200, y: 200),
            ev(0.3, .leftUp, x: 200, y: 200),
        ])
        guard case .drag(let d) = blocks.first else { return XCTFail("expected drag, got \(blocks)") }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(d.button, .left)
        XCTAssertEqual(d.points.first?.x, 100)
        XCTAssertEqual(d.points.last?.x, 200)
        XCTAssertEqual(d.duration, 0.3, accuracy: 0.001)
    }

    func testScrollMerged() {
        let blocks = EventGrouper.group([
            ev(0, .scroll, x: 500, y: 400, dy: -3),
            ev(0.05, .scroll, x: 500, y: 400, dy: -5),
        ])
        guard case .scroll(let s) = blocks.first else { return XCTFail("expected scroll, got \(blocks)") }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(s.steps.count, 2)
        XCTAssertEqual(s.steps[1].dy, -5)
    }

    func testTypingMerged() {
        let blocks = EventGrouper.group([
            ev(0, .keyDown, keyCode: 4, chars: "h"),
            ev(0.05, .keyUp, keyCode: 4),
            ev(0.1, .keyDown, keyCode: 14, chars: "e"),
            ev(0.15, .keyUp, keyCode: 14),
        ])
        guard case .typeText(let t) = blocks.first else { return XCTFail("expected typeText, got \(blocks)") }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(t.text, "he")
        XCTAssertEqual(t.keystrokes.count, 2)
    }

    func testShortcutSeparate() {
        let blocks = EventGrouper.group([
            ev(0, .keyDown, keyCode: 8, flags: KeyCodeMap.maskCommand, chars: "c"),
            ev(0.05, .keyUp, keyCode: 8, flags: KeyCodeMap.maskCommand),
        ])
        guard case .shortcut(let s) = blocks.first else { return XCTFail("expected shortcut, got \(blocks)") }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(s.keyCode, 8)
        XCTAssertEqual(s.flags & KeyCodeMap.maskCommand, KeyCodeMap.maskCommand)
    }

    func testShiftTypingIsText() {
        // Shift+h = 大写 H，应归入打字而非快捷键
        let blocks = EventGrouper.group([
            ev(0, .keyDown, keyCode: 4, flags: KeyCodeMap.maskShift, chars: "H"),
            ev(0.05, .keyUp, keyCode: 4),
        ])
        guard case .typeText(let t) = blocks.first else { return XCTFail("expected typeText, got \(blocks)") }
        XCTAssertEqual(t.text, "H")
    }

    func testWaitInserted() {
        let blocks = EventGrouper.group([
            ev(0, .leftDown, x: 1, y: 1), ev(0.05, .leftUp, x: 1, y: 1),
            ev(2.05, .leftDown, x: 9, y: 9), ev(2.1, .leftUp, x: 9, y: 9),
        ])
        XCTAssertEqual(blocks.count, 3)
        guard case .wait(let w) = blocks[1] else { return XCTFail("expected wait, got \(blocks)") }
        XCTAssertEqual(w.duration, 2.0, accuracy: 0.001)
    }

    func testSmallGapNoWait() {
        let blocks = EventGrouper.group([
            ev(0, .leftDown, x: 1, y: 1), ev(0.05, .leftUp, x: 1, y: 1),
            ev(0.3, .leftDown, x: 9, y: 9), ev(0.35, .leftUp, x: 9, y: 9),
        ])
        XCTAssertEqual(blocks.count, 2)  // 无 wait 块
    }

    func testTypingSplitByWait() {
        let blocks = EventGrouper.group([
            ev(0, .keyDown, keyCode: 4, chars: "h"), ev(0.05, .keyUp, keyCode: 4),
            ev(3.0, .keyDown, keyCode: 14, chars: "e"), ev(3.05, .keyUp, keyCode: 14),
        ])
        // 打字 / 等待 / 打字
        XCTAssertEqual(blocks.count, 3)
        guard case .typeText = blocks[0], case .wait = blocks[1], case .typeText = blocks[2]
        else { return XCTFail("got \(blocks)") }
    }

    func testMoveThenClick() {
        let blocks = EventGrouper.group([
            ev(0, .mouseMove, x: 0, y: 0),
            ev(0.1, .mouseMove, x: 100, y: 100),
            ev(0.2, .leftDown, x: 100, y: 100),
            ev(0.25, .leftUp, x: 100, y: 100),
        ])
        XCTAssertEqual(blocks.count, 2)
        guard case .move = blocks[0], case .click = blocks[1] else { return XCTFail("got \(blocks)") }
    }

    func testFlagsChangedIgnored() {
        let blocks = EventGrouper.group([
            ev(0, .flagsChanged, keyCode: 55, flags: KeyCodeMap.maskCommand),
            ev(0.5, .flagsChanged, keyCode: 55),
        ])
        XCTAssertTrue(blocks.isEmpty)
    }

    func testDanglingDownEmitsClick() {
        // down 后没有 up（录制被截断）：兜底生成 click，不崩溃
        let blocks = EventGrouper.group([ev(0, .leftDown, x: 5, y: 5)])
        XCTAssertEqual(blocks.count, 1)
        guard case .click = blocks[0] else { return XCTFail("got \(blocks)") }
    }
}

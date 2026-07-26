import XCTest
@testable import ClickerCore

final class BlockExpanderTests: XCTestCase {
    func testClickExpansion() {
        let blocks: [ActionBlock] = [.click(ClickBlock(x: 100, y: 200, button: .left, clickCount: 1))]
        let steps = BlockExpander.expand(blocks)
        XCTAssertEqual(steps.count, 2)
        guard case .mouseDown(let x, let y, let btn, let clicks) = steps[0].action else { return XCTFail() }
        XCTAssertEqual(x, 100); XCTAssertEqual(y, 200)
        XCTAssertEqual(btn, .left); XCTAssertEqual(clicks, 1)
        guard case .mouseUp = steps[1].action else { return XCTFail() }
        // down/up 有一个固定小间隔
        XCTAssertGreaterThan(steps[1].t, steps[0].t)
    }

    func testWaitShiftsTime() {
        let blocks: [ActionBlock] = [
            .wait(WaitBlock(duration: 2.0)),
            .click(ClickBlock(x: 1, y: 1, button: .left, clickCount: 1)),
        ]
        let steps = BlockExpander.expand(blocks)
        XCTAssertEqual(steps.first?.t ?? 0, 2.0, accuracy: 0.001)
    }

    func testMoveExpansion() {
        let blocks: [ActionBlock] = [.move(MoveBlock(duration: 0.2, points: [
            TrackPoint(t: 0, x: 0, y: 0), TrackPoint(t: 0.2, x: 100, y: 100),
        ]))]
        let steps = BlockExpander.expand(blocks)
        XCTAssertEqual(steps.count, 2)
        guard case .mouseMove(let x, _) = steps[1].action else { return XCTFail() }
        XCTAssertEqual(x, 100)
        XCTAssertEqual(steps[1].t, 0.2, accuracy: 0.001)
    }

    func testDragExpansion() {
        let blocks: [ActionBlock] = [.drag(DragBlock(button: .left, duration: 0.3, points: [
            TrackPoint(t: 0, x: 10, y: 10),
            TrackPoint(t: 0.15, x: 50, y: 50),
            TrackPoint(t: 0.3, x: 90, y: 90),
        ]))]
        let steps = BlockExpander.expand(blocks)
        // down + 中间 drag 移动 + up
        XCTAssertEqual(steps.count, 3)
        guard case .mouseDown(let x0, _, _, _) = steps[0].action, x0 == 10 else { return XCTFail() }
        guard case .mouseDrag(let x1, _, _) = steps[1].action, x1 == 50 else { return XCTFail() }
        guard case .mouseUp(let x2, _, _) = steps[2].action, x2 == 90 else { return XCTFail() }
    }

    func testTypeTextExpansion() {
        let blocks: [ActionBlock] = [.typeText(TypeTextBlock(text: "he", keystrokes: [
            Keystroke(t: 0, keyCode: 4, chars: "h"),
            Keystroke(t: 0.1, keyCode: 14, chars: "e"),
        ]))]
        let steps = BlockExpander.expand(blocks)
        // 每个 keystroke → keyDown + keyUp
        XCTAssertEqual(steps.count, 4)
        guard case .keyDown(let kc, _, let chars) = steps[0].action else { return XCTFail() }
        XCTAssertEqual(kc, 4); XCTAssertEqual(chars, "h")
        guard case .keyUp = steps[1].action else { return XCTFail() }
    }

    func testEditedTextRegeneratesKeystrokes() {
        // 用户编辑了 text 但 keystrokes 是旧的：以 text 为准，用 unicode 注入
        let blocks: [ActionBlock] = [.typeText(TypeTextBlock(text: "你好", keystrokes: [
            Keystroke(t: 0, keyCode: 4, chars: "h"),
        ]))]
        let steps = BlockExpander.expand(blocks)
        // text 与 keystrokes.chars 拼接不一致 → 逐字符 unicode 注入（down+up 各一）
        XCTAssertEqual(steps.count, 4)
        guard case .keyDown(_, _, let c0) = steps[0].action else { return XCTFail() }
        XCTAssertEqual(c0, "你")
    }

    func testShortcutExpansion() {
        let blocks: [ActionBlock] = [.shortcut(ShortcutBlock(keyCode: 8, flags: KeyCodeMap.maskCommand))]
        let steps = BlockExpander.expand(blocks)
        XCTAssertEqual(steps.count, 2)
        guard case .keyDown(let kc, let flags, _) = steps[0].action else { return XCTFail() }
        XCTAssertEqual(kc, 8)
        XCTAssertEqual(flags & KeyCodeMap.maskCommand, KeyCodeMap.maskCommand)
    }

    func testScrollExpansion() {
        let blocks: [ActionBlock] = [.scroll(ScrollBlock(x: 5, y: 5, duration: 0.1, steps: [
            ScrollStep(t: 0, dx: 0, dy: -3), ScrollStep(t: 0.1, dx: 0, dy: -5),
        ]))]
        let steps = BlockExpander.expand(blocks)
        XCTAssertEqual(steps.count, 2)
        guard case .scroll(let dx, let dy) = steps[0].action else { return XCTFail() }
        XCTAssertEqual(dx, 0); XCTAssertEqual(dy, -3)
    }

    func testTotalDurationAccumulates() {
        let blocks: [ActionBlock] = [
            .wait(WaitBlock(duration: 1.0)),
            .move(MoveBlock(duration: 0.5, points: [
                TrackPoint(t: 0, x: 0, y: 0), TrackPoint(t: 0.5, x: 10, y: 10),
            ])),
            .wait(WaitBlock(duration: 1.0)),
            .click(ClickBlock(x: 10, y: 10, button: .left, clickCount: 1)),
        ]
        let steps = BlockExpander.expand(blocks)
        // click 的 down 在 1.0 + 0.5 + 1.0 = 2.5
        guard case .mouseDown = steps.last(where: { if case .mouseDown = $0.action { return true }; return false })!.action
        else { return XCTFail() }
        let downStep = steps.first { if case .mouseDown = $0.action { return true }; return false }!
        XCTAssertEqual(downStep.t, 2.5, accuracy: 0.001)
    }
}

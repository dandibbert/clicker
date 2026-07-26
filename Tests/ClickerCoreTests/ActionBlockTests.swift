import XCTest
@testable import ClickerCore

final class ActionBlockTests: XCTestCase {
    func testBlockCodableRoundTrip() throws {
        let blocks: [ActionBlock] = [
            .move(MoveBlock(id: UUID(), duration: 0.5,
                            points: [TrackPoint(t: 0, x: 0, y: 0), TrackPoint(t: 0.5, x: 100, y: 100)])),
            .click(ClickBlock(id: UUID(), x: 100, y: 100, button: .left, clickCount: 1)),
            .drag(DragBlock(id: UUID(), button: .left, duration: 1.0,
                            points: [TrackPoint(t: 0, x: 100, y: 100), TrackPoint(t: 1.0, x: 300, y: 300)])),
            .scroll(ScrollBlock(id: UUID(), x: 50, y: 60, duration: 0.3,
                                steps: [ScrollStep(t: 0, dx: 0, dy: -3)])),
            .typeText(TypeTextBlock(id: UUID(), text: "hello",
                                    keystrokes: [Keystroke(t: 0, keyCode: 4, chars: "h")])),
            .shortcut(ShortcutBlock(id: UUID(), keyCode: 8, flags: 1 << 20)),
            .wait(WaitBlock(id: UUID(), duration: 2.0)),
        ]
        let data = try JSONEncoder().encode(blocks)
        let back = try JSONDecoder().decode([ActionBlock].self, from: data)
        XCTAssertEqual(blocks, back)
    }

    func testScriptDefaults() {
        let s = Script(name: "测试")
        XCTAssertEqual(s.repeatCount, 1)
        XCTAssertFalse(s.repeatForever)
        XCTAssertEqual(s.repeatInterval, 0)
        XCTAssertTrue(s.blocks.isEmpty)
    }

    func testBlockIDAccessor() {
        let id = UUID()
        let b = ActionBlock.wait(WaitBlock(id: id, duration: 1))
        XCTAssertEqual(b.id, id)
    }
}

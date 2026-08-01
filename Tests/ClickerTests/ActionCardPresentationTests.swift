import ClickerCore
import XCTest
@testable import Clicker

final class ActionCardPresentationTests: XCTestCase {
    func testClickCardPresentsButtonAndCoordinates() {
        let model = ActionCardPresentation(block: .click(ClickBlock(
            x: 120.4,
            y: 240.6,
            button: .right,
            clickCount: 1
        )))

        XCTAssertEqual(model.systemImage, "cursorarrow.click")
        XCTAssertEqual(model.title, "右键")
        XCTAssertEqual(model.summary, "(120, 241)")
        XCTAssertEqual(model.trailingText, "")
        XCTAssertEqual(model.accessibilityLabel, "右键，(120, 241)")
    }

    func testDragCardSeparatesPathAndDuration() {
        let model = ActionCardPresentation(block: .drag(DragBlock(
            button: .left,
            duration: 0.75,
            points: [
                TrackPoint(t: 0, x: 10, y: 20),
                TrackPoint(t: 0.75, x: 110, y: 220),
            ]
        )))

        XCTAssertEqual(model.systemImage, "hand.draw")
        XCTAssertEqual(model.title, "拖拽")
        XCTAssertEqual(model.summary, "(10, 20) → (110, 220)")
        XCTAssertEqual(model.trailingText, "0.8 秒")
        XCTAssertEqual(model.accessibilityLabel, "拖拽，(10, 20) → (110, 220)，0.8 秒")
    }

    func testMoveCardSeparatesPathAndDuration() {
        let model = ActionCardPresentation(block: .move(MoveBlock(
            duration: 1.04,
            points: [
                TrackPoint(t: 0, x: 50.2, y: 75.8),
                TrackPoint(t: 1.04, x: 250.9, y: 300.1),
            ]
        )))

        XCTAssertEqual(model.systemImage, "arrow.up.and.down.and.arrow.left.and.right")
        XCTAssertEqual(model.title, "移动鼠标")
        XCTAssertEqual(model.summary, "(50, 76) → (251, 300)")
        XCTAssertEqual(model.trailingText, "1.0 秒")
        XCTAssertEqual(model.accessibilityLabel, "移动鼠标，(50, 76) → (251, 300)，1.0 秒")
    }

    func testScrollCardPresentsDirectionAndDistance() {
        let model = ActionCardPresentation(block: .scroll(ScrollBlock(
            x: 400,
            y: 300,
            duration: 0.4,
            steps: [
                ScrollStep(t: 0, dx: 0, dy: -12.4),
                ScrollStep(t: 0.2, dx: 0, dy: -7.6),
            ]
        )))

        XCTAssertEqual(model.systemImage, "computermouse")
        XCTAssertEqual(model.title, "滚动")
        XCTAssertEqual(model.summary, "向下 20 px")
        XCTAssertEqual(model.trailingText, "")
        XCTAssertEqual(model.accessibilityLabel, "滚动，向下 20 px")
    }

    func testTypeTextCardTruncatesOnlyItsVisualSummary() {
        let text = "123456789012345678901234567890"
        let model = ActionCardPresentation(block: .typeText(TypeTextBlock(
            text: text,
            keystrokes: []
        )))

        XCTAssertEqual(model.systemImage, "keyboard")
        XCTAssertEqual(model.title, "输入文本")
        XCTAssertEqual(model.summary, "\"1234567890123456789012345678…\"")
        XCTAssertEqual(model.trailingText, "")
        XCTAssertEqual(model.accessibilityLabel, "输入文本，\(text)")
    }

    func testShortcutCardSeparatesTypeAndKeyCombination() {
        let model = ActionCardPresentation(block: .shortcut(ShortcutBlock(
            keyCode: 8,
            flags: KeyCodeMap.maskOption | KeyCodeMap.maskCommand
        )))

        XCTAssertEqual(model.systemImage, "command")
        XCTAssertEqual(model.title, "快捷键")
        XCTAssertEqual(model.summary, "⌥⌘C")
        XCTAssertEqual(model.trailingText, "")
        XCTAssertEqual(model.accessibilityLabel, "快捷键，⌥⌘C")
    }

    func testWaitCardSeparatesTitleSummaryAndDuration() {
        let model = ActionCardPresentation(block: .wait(WaitBlock(duration: 1.25)))

        XCTAssertEqual(model.systemImage, "clock")
        XCTAssertEqual(model.title, "等待")
        XCTAssertEqual(model.summary, "暂停回放")
        XCTAssertEqual(model.trailingText, "1.3 秒")
        XCTAssertTrue(model.accessibilityLabel.contains("等待"))
    }

    func testInactiveCardHasNoActiveFeedback() {
        XCTAssertNil(ActiveFeedbackStyle.resolve(isActive: false, reduceMotion: false))
        XCTAssertNil(ActiveFeedbackStyle.resolve(isActive: false, reduceMotion: true))
    }

    func testActiveCardUsesPulsingTrailWhenMotionIsAllowed() {
        XCTAssertEqual(
            ActiveFeedbackStyle.resolve(isActive: true, reduceMotion: false),
            .pulsingTrail
        )
    }

    func testReduceMotionUsesStaticActiveFeedback() {
        XCTAssertEqual(
            ActiveFeedbackStyle.resolve(isActive: true, reduceMotion: true),
            .staticHighlight
        )
    }
}

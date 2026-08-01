import AppKit
import ClickerCore
import SwiftUI
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

    func testDurationPresentationUsesEffectiveDurationAndNeverEmitsUnsafeValues() {
        let fixtures: [(ActionBlock, String)] = [
            (
                .move(MoveBlock(
                    duration: -4,
                    points: [TrackPoint(t: 1.25, x: 0, y: 0)]
                )),
                "1.3 秒"
            ),
            (
                .drag(DragBlock(
                    button: .left,
                    duration: .nan,
                    points: [TrackPoint(t: 2.25, x: 0, y: 0)]
                )),
                "2.3 秒"
            ),
            (.wait(WaitBlock(duration: -1)), "0.0 秒"),
            (.wait(WaitBlock(duration: .nan)), "0.0 秒"),
            (.wait(WaitBlock(duration: .infinity)), "0.0 秒"),
            (.wait(WaitBlock(duration: .greatestFiniteMagnitude)), "9223372035.9 秒"),
        ]

        for (block, expected) in fixtures {
            let trailingText = ActionCardPresentation(block: block).trailingText

            XCTAssertEqual(trailingText, expected)
            XCTAssertFalse(trailingText.lowercased().contains("nan"))
            XCTAssertFalse(trailingText.lowercased().contains("inf"))
            XCTAssertFalse(trailingText.hasPrefix("-"))
        }
    }

    func testCoordinatesReplaceNonfiniteValuesButPreserveLegalNegativeValues() {
        let invalid = ActionCardPresentation(block: .click(ClickBlock(
            x: .nan,
            y: .infinity,
            button: .left,
            clickCount: 1
        )))
        let negative = ActionCardPresentation(block: .click(ClickBlock(
            x: -42.6,
            y: -8.2,
            button: .left,
            clickCount: 1
        )))

        XCTAssertEqual(invalid.summary, "(0, 0)")
        XCTAssertEqual(negative.summary, "(-43, -8)")
    }

    func testScrollIgnoresNonfiniteDeltasAndPreservesNegativeDirection() {
        let model = ActionCardPresentation(block: .scroll(ScrollBlock(
            x: 0,
            y: 0,
            duration: 0,
            steps: [
                ScrollStep(t: 0, dx: 0, dy: .nan),
                ScrollStep(t: 0.1, dx: 0, dy: .infinity),
                ScrollStep(t: 0.2, dx: 0, dy: -12.6),
            ]
        )))

        XCTAssertEqual(model.summary, "向下 13 px")
        XCTAssertFalse(model.accessibilityLabel.lowercased().contains("nan"))
        XCTAssertFalse(model.accessibilityLabel.lowercased().contains("inf"))
    }

    func testActiveAccessibilityLabelAnnouncesPlayback() {
        let model = ActionCardPresentation(block: .wait(WaitBlock(duration: 1.25)))

        XCTAssertEqual(model.accessibilityLabel, "等待，暂停回放，1.3 秒")
        XCTAssertEqual(model.activeAccessibilityLabel, "正在回放，等待，暂停回放，1.3 秒")
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

    func testActionCardEditPolicySupportsKeyboardAndAccessibilityOnlyWhenEnabled() {
        let enabled = ActionCardEditPolicy(isEnabled: true)
        let disabled = ActionCardEditPolicy(isEnabled: false)

        XCTAssertTrue(enabled.isFocusable)
        XCTAssertTrue(enabled.allows(.doubleClick))
        XCTAssertTrue(enabled.allows(.returnKey))
        XCTAssertTrue(enabled.allows(.spaceKey))
        XCTAssertTrue(enabled.allows(.accessibilityAction))
        XCTAssertEqual(enabled.accessibilityActionName, "编辑动作")

        XCTAssertFalse(disabled.isFocusable)
        XCTAssertFalse(disabled.allows(.doubleClick))
        XCTAssertFalse(disabled.allows(.returnKey))
        XCTAssertFalse(disabled.allows(.spaceKey))
        XCTAssertFalse(disabled.allows(.accessibilityAction))
        XCTAssertNil(disabled.accessibilityActionName)
    }

    @MainActor
    func testLightActionCardRendersVisibleBoundaryAgainstCanvas() throws {
        _ = NSApplication.shared
        let view = ActionCardView(
            block: .wait(WaitBlock(duration: 1.25)),
            isActive: false
        )
        .environment(\.colorScheme, .light)
        .frame(width: 320)
        .background(ClickerVisualTheme.canvas)
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let centerX = bitmap.pixelsWide / 2
        let boundary = try XCTUnwrap(bitmap.colorAt(x: centerX, y: 1)?.usingColorSpace(.sRGB))
        let interior = try XCTUnwrap(
            bitmap.colorAt(x: centerX, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB)
        )

        XCTAssertGreaterThan(
            contrastRatio(boundary, interior),
            3,
            "浅色动作卡片边界必须达到非文本 UI 的 3:1 对比度"
        )
    }

    private func contrastRatio(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        let first = relativeLuminance(lhs)
        let second = relativeLuminance(rhs)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func relativeLuminance(_ color: NSColor) -> CGFloat {
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent)
            + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
    }
}

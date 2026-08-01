import XCTest
@testable import Clicker

final class VisualPresentationTests: XCTestCase {
    func testIdlePrimaryActionsHaveEqualRecordAndPlaybackEntries() {
        let pair = PrimaryActionPresentation.pair(phase: .idle, hasPlayableScript: true)

        XCTAssertEqual(pair.map(\.kind), [.record, .play])
        XCTAssertEqual(pair.map(\.title), ["录制", "回放"])
        XCTAssertEqual(pair.map(\.isEnabled), [true, true])
        XCTAssertTrue(pair.allSatisfy { !$0.isStop })
    }

    func testIdlePlaybackIsDisabledWithoutAPlayableScript() {
        let pair = PrimaryActionPresentation.pair(phase: .idle, hasPlayableScript: false)

        XCTAssertEqual(pair.map(\.isEnabled), [true, false])
        XCTAssertEqual(pair[1].accessibilityLabel, "开始回放")
    }

    func testCountdownPresentsAnEnabledStopRecordingActionAndDisablesPlayback() {
        let pair = PrimaryActionPresentation.pair(phase: .countdown(2), hasPlayableScript: true)

        XCTAssertEqual(pair[0].title, "停止录制")
        XCTAssertTrue(pair[0].isStop)
        XCTAssertTrue(pair[0].isEnabled)
        XCTAssertFalse(pair[1].isEnabled)
    }

    func testRecordingAndPlaybackExposeExplicitStopCopyAndDisableTheOppositeAction() {
        let recording = PrimaryActionPresentation.pair(phase: .recording, hasPlayableScript: true)
        let playing = PrimaryActionPresentation.pair(
            phase: .playing(iteration: 1, currentBlockID: nil),
            hasPlayableScript: true
        )

        XCTAssertEqual(recording[0].title, "停止录制")
        XCTAssertTrue(recording[0].isStop)
        XCTAssertFalse(recording[1].isEnabled)
        XCTAssertEqual(playing[1].title, "停止回放")
        XCTAssertTrue(playing[1].isStop)
        XCTAssertFalse(playing[0].isEnabled)
    }

    func testPrimaryActionsHaveDistinctAccessibleLabelsInEachPhase() {
        for phase in [
            AppPhase.idle,
            .countdown(1),
            .recording,
            .playing(iteration: 2, currentBlockID: UUID()),
        ] {
            let labels = PrimaryActionPresentation.pair(phase: phase, hasPlayableScript: true)
                .map(\.accessibilityLabel)

            XCTAssertEqual(Set(labels).count, 2)
        }
    }

    func testActiveFeedbackAnimationHonorsReduceMotion() {
        XCTAssertTrue(PrimaryActionPresentation.usesAnimatedActiveFeedback(isReduceMotionEnabled: false))
        XCTAssertFalse(PrimaryActionPresentation.usesAnimatedActiveFeedback(isReduceMotionEnabled: true))
    }

    func testVisualThemeUsesApprovedLayoutTokens() {
        XCTAssertEqual(ClickerVisualTheme.spacing4, 4)
        XCTAssertEqual(ClickerVisualTheme.spacing8, 8)
        XCTAssertEqual(ClickerVisualTheme.spacing12, 12)
        XCTAssertEqual(ClickerVisualTheme.spacing16, 16)
        XCTAssertEqual(ClickerVisualTheme.spacing24, 24)
        XCTAssertEqual(ClickerVisualTheme.cardCornerRadius, 10)
        XCTAssertEqual(ClickerVisualTheme.panelCornerRadius, 14)
        XCTAssertEqual(ClickerVisualTheme.primaryControlHeight, 34)
    }
}

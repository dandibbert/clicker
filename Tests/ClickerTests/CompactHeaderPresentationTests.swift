import ClickerCore
import XCTest
@testable import Clicker

final class CompactHeaderPresentationTests: XCTestCase {
    func testHeaderReportsActionCountAndPlanDuration() {
        let script = Script(
            name: "日报流程",
            blocks: [.wait(WaitBlock(duration: 1.5))],
            trailingDelay: 0.5
        )

        let model = ScriptHeaderPresentation(script: script)

        XCTAssertEqual(model.title, "日报流程")
        XCTAssertEqual(model.actionCountText, "1 个动作")
        XCTAssertEqual(model.durationText, "约 2.0 秒")
    }

    func testHeaderReportsEmptyScriptMetadata() {
        let model = ScriptHeaderPresentation(script: Script(name: "空脚本"))

        XCTAssertEqual(model.actionCountText, "0 个动作")
        XCTAssertEqual(model.durationText, "约 0.0 秒")
    }

    func testHeaderFormatsNonfinitePlanDurationSafely() {
        let script = Script(
            name: "安全时长",
            blocks: [.wait(WaitBlock(duration: .infinity))],
            trailingDelay: .nan
        )

        let model = ScriptHeaderPresentation(script: script)

        XCTAssertEqual(model.durationText, "约 0.0 秒")
    }

    func testCompactHeaderCombinesActionCountAndDurationMetadata() {
        let script = Script(
            name: "录制 1",
            blocks: [.wait(WaitBlock(duration: 1.5))],
            trailingDelay: 0.5
        )
        let model = CompactScriptHeaderPresentation(script: script, phase: .idle)

        XCTAssertEqual(model.title, "录制 1")
        XCTAssertEqual(model.metadata, "1 个动作 · 约 2.0 秒")
        XCTAssertFalse(model.showsPlaybackProgress)
    }

    func testCompactHeaderPreservesFiniteAndInfinitePlaybackProgressCopy() {
        var finiteScript = Script(name: "有限回放", repeatCount: 3)
        finiteScript.repeatForever = false
        var infiniteScript = Script(name: "无限回放", repeatCount: 3)
        infiniteScript.repeatForever = true
        let phase = AppPhase.playing(iteration: 2, currentBlockID: nil)

        let finite = CompactScriptHeaderPresentation(script: finiteScript, phase: phase)
        let infinite = CompactScriptHeaderPresentation(script: infiniteScript, phase: phase)

        XCTAssertTrue(finite.showsPlaybackProgress)
        XCTAssertEqual(finite.playbackProgressText, "第 2/3 轮")
        XCTAssertTrue(infinite.showsPlaybackProgress)
        XCTAssertEqual(infinite.playbackProgressText, "第 2 轮")
    }

    func testCompactHeaderHeightStaysInsideApprovedRange() {
        XCTAssertGreaterThanOrEqual(ClickerVisualTheme.compactHeaderHeight, 88)
        XCTAssertLessThanOrEqual(ClickerVisualTheme.compactHeaderHeight, 104)
    }
}

import AppKit
import ClickerCore
import XCTest
@testable import Clicker

final class VisualPresentationTests: XCTestCase {
    func testScriptRowIncludesActionCountAndModifiedMetadata() {
        let modifiedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let script = Script(
            name: "网页发布",
            modifiedAt: modifiedAt,
            blocks: [.wait(WaitBlock(duration: 1))]
        )

        let model = ScriptRowPresentation(script: script, now: modifiedAt)

        XCTAssertEqual(model.name, "网页发布")
        XCTAssertEqual(model.actionCountText, "1 个动作")
        XCTAssertEqual(model.modifiedText, "刚刚修改")
        XCTAssertEqual(model.metadataText, "1 个动作 · 刚刚修改")
        XCTAssertTrue(model.accessibilityLabel.contains("网页发布"))
        XCTAssertTrue(model.accessibilityLabel.contains("1 个动作"))
        XCTAssertTrue(model.accessibilityLabel.contains("刚刚修改"))
    }

    func testScriptRowPluralActionCountUsesFixedRelativeModificationTime() {
        let modifiedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let now = modifiedAt.addingTimeInterval(2 * 60 * 60)
        let script = Script(
            name: "整理文件",
            modifiedAt: modifiedAt,
            blocks: [
                .wait(WaitBlock(duration: 1)),
                .wait(WaitBlock(duration: 2)),
            ]
        )

        let model = ScriptRowPresentation(script: script, now: now)

        XCTAssertEqual(model.actionCountText, "2 个动作")
        XCTAssertEqual(model.modifiedText, "2 小时前修改")
    }

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

    func testEmptyLibraryOffersRecordingAction() {
        let model = ClickerEmptyStatePresentation(kind: .emptyLibrary)

        XCTAssertEqual(model.title, "还没有脚本")
        XCTAssertEqual(model.actionTitle, "开始录制")
    }

    func testNoSelectionExplainsHowToOpenAScriptWithoutAnAction() {
        let model = ClickerEmptyStatePresentation(kind: .noSelection)

        XCTAssertEqual(model.title, "选择一个脚本")
        XCTAssertTrue(model.description.contains("左侧脚本库"))
        XCTAssertNil(model.actionTitle)
    }

    func testEmptyScriptInvitesTheFirstRecordedAction() {
        let model = ClickerEmptyStatePresentation(kind: .emptyScript)

        XCTAssertEqual(model.title, "这个脚本还没有动作")
        XCTAssertTrue(model.description.contains("添加第一个动作"))
        XCTAssertEqual(model.actionTitle, "开始录制")
    }

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

    func testVisualThemeExportsRedOnlyForRecordingAndActiveFeedback() {
        let redRoles = ClickerVisualTheme.ColorRole.allCases.filter { role in
            let color = ClickerVisualTheme.resolvedColor(
                for: role,
                appearance: NSAppearance(named: .aqua)!
            )
            return isTrailRed(color)
        }

        XCTAssertEqual(redRoles, [.recordFill, .activeTrail])
    }

    func testVisualThemeResolvesOnlyApprovedPaletteAcrossAppearances() throws {
        let lightAppearanceNames: [NSAppearance.Name] = [
            .aqua,
            .accessibilityHighContrastAqua,
        ]
        let darkAppearanceNames: [NSAppearance.Name] = [
            .darkAqua,
            .accessibilityHighContrastDarkAqua,
        ]

        for appearanceName in lightAppearanceNames {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            for expectation in paletteExpectations {
                assertSRGB(expectation.role, equals: expectation.light, in: appearance)
            }
        }

        for appearanceName in darkAppearanceNames {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            for expectation in paletteExpectations {
                assertSRGB(expectation.role, equals: expectation.dark, in: appearance)
            }
        }
    }

    func testExportedDynamicThemeProvidersResolveThePaletteAcrossAppearances() throws {
        let lightAppearanceNames: [NSAppearance.Name] = [
            .aqua,
            .accessibilityHighContrastAqua,
        ]
        let darkAppearanceNames: [NSAppearance.Name] = [
            .darkAqua,
            .accessibilityHighContrastDarkAqua,
        ]

        for appearanceName in lightAppearanceNames {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            for expectation in paletteExpectations {
                assertDynamicProviderSRGB(expectation.role, equals: expectation.light, in: appearance)
            }
        }

        for appearanceName in darkAppearanceNames {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            for expectation in paletteExpectations {
                assertDynamicProviderSRGB(expectation.role, equals: expectation.dark, in: appearance)
            }
        }
    }

    private var paletteExpectations: [
        (role: ClickerVisualTheme.ColorRole, light: (UInt8, UInt8, UInt8), dark: (UInt8, UInt8, UInt8))
    ] {
        [
            (.canvas, (0xF1, 0xEA, 0xDC), (0x15, 0x14, 0x18)),
            (.cardSurface, (0xF1, 0xEA, 0xDC), (0x23, 0x21, 0x26)),
            (.elevatedSurface, (0xF1, 0xEA, 0xDC), (0x23, 0x21, 0x26)),
            (.primaryText, (0x17, 0x16, 0x19), (0xF1, 0xEA, 0xDC)),
            (.secondaryText, (0x8B, 0x84, 0x7A), (0x8B, 0x84, 0x7A)),
            (.separator, (0x8B, 0x84, 0x7A), (0x8B, 0x84, 0x7A)),
            (.selection, (0xF1, 0xEA, 0xDC), (0x23, 0x21, 0x26)),
            (.recordFill, (0xE7, 0x38, 0x36), (0xE7, 0x38, 0x36)),
            (.playbackFill, (0x17, 0x16, 0x19), (0xF1, 0xEA, 0xDC)),
            (.activeTrail, (0xE7, 0x38, 0x36), (0xE7, 0x38, 0x36)),
        ]
    }

    private func assertSRGB(
        _ role: ClickerVisualTheme.ColorRole,
        equals expected: (UInt8, UInt8, UInt8),
        in appearance: NSAppearance,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let sRGB = ClickerVisualTheme.resolvedColor(for: role, appearance: appearance)
            .usingColorSpace(NSColorSpace.sRGB) else {
            XCTFail("Expected an sRGB color", file: file, line: line)
            return
        }

        XCTAssertEqual(sRGB.redComponent, CGFloat(expected.0) / 255, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(sRGB.greenComponent, CGFloat(expected.1) / 255, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(sRGB.blueComponent, CGFloat(expected.2) / 255, accuracy: 0.0001, file: file, line: line)
    }

    private func assertDynamicProviderSRGB(
        _ role: ClickerVisualTheme.ColorRole,
        equals expected: (UInt8, UInt8, UInt8),
        in appearance: NSAppearance,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = ClickerVisualTheme.dynamicNSColor(for: role)
                .usingColorSpace(NSColorSpace.sRGB)
        }
        guard let sRGB = resolved else {
            XCTFail("Expected the dynamic provider to resolve to sRGB", file: file, line: line)
            return
        }

        XCTAssertEqual(sRGB.redComponent, CGFloat(expected.0) / 255, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(sRGB.greenComponent, CGFloat(expected.1) / 255, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(sRGB.blueComponent, CGFloat(expected.2) / 255, accuracy: 0.0001, file: file, line: line)
    }

    private func isTrailRed(_ color: NSColor) -> Bool {
        guard let sRGB = color.usingColorSpace(.sRGB) else { return false }
        return sRGB.redComponent == CGFloat(0xE7) / 255
            && sRGB.greenComponent == CGFloat(0x38) / 255
            && sRGB.blueComponent == CGFloat(0x36) / 255
    }
}

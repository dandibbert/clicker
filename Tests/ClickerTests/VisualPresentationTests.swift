import AppKit
import ClickerCore
import SwiftUI
import XCTest
@testable import Clicker

final class VisualPresentationTests: XCTestCase {
    private enum ColorConversionError: Error {
        case cannotConvertToSRGB
    }

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

    func testTrailingOnlyScriptPresentsPlaybackAsEnabled() {
        let script = Script(name: "收尾等待", trailingDelay: 0.5)

        let actions = PrimaryActionPresentation.pair(
            phase: .idle,
            hasPlayableScript: ScriptPlaybackEligibility.isPlayable(script)
        )

        XCTAssertTrue(actions[1].isEnabled)
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

    func testPermissionPresentationKeepsPrimaryAndSecondaryActions() {
        let model = ClickerEmptyStatePresentation(kind: .permissionRequired)

        XCTAssertEqual(model.title, "需要辅助功能权限")
        XCTAssertEqual(model.actionTitle, "打开系统设置")
        XCTAssertEqual(model.secondaryActionTitle, "重新检测")
    }

    func testEmptyScriptInvitesRecordingOrAddingAnAction() {
        let model = ClickerEmptyStatePresentation(kind: .emptyScript)

        XCTAssertEqual(model.title, "这个脚本还没有动作")
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

    func testRecordingIndicatorUsesStaticFeedbackWhenReduceMotionIsEnabled() {
        XCTAssertEqual(
            RecordingIndicatorFeedbackStyle.resolve(reduceMotion: false),
            .pulsing
        )
        XCTAssertEqual(
            RecordingIndicatorFeedbackStyle.resolve(reduceMotion: true),
            .staticHighlight
        )
    }

    @MainActor
    func testRecordingIndicatorBorderUsesRecordFillAndConcreteMotionPolicy() throws {
        let staticBorder = RecordingIndicatorBorder(
            feedbackStyle: .staticHighlight,
            isPulsing: false
        )
        XCTAssertEqual(staticBorder.borderOpacity, 1)
        XCTAssertNil(staticBorder.borderAnimation)

        let pulsingLow = RecordingIndicatorBorder(feedbackStyle: .pulsing, isPulsing: false)
        let pulsingHigh = RecordingIndicatorBorder(feedbackStyle: .pulsing, isPulsing: true)
        XCTAssertEqual(pulsingLow.borderOpacity, 0.35)
        XCTAssertEqual(pulsingHigh.borderOpacity, 1)
        XCTAssertNotNil(pulsingLow.borderAnimation)

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let bitmap = try renderBitmap(
                staticBorder.frame(width: 100, height: 100),
                appearance: appearance,
                size: CGSize(width: 100, height: 100)
            )
            XCTAssertTrue(
                bitmapContainsVisibleRecordFill(bitmap),
                "The real indicator border must render recordFill in \(appearanceName.rawValue)"
            )
        }

        XCTAssertTrue(
            String(reflecting: RecordingIndicatorView.Body.self)
                .contains("RecordingIndicatorBorder"),
            "Deleting the real indicator-border consumer must fail this test"
        )
        XCTAssertTrue(
            String(reflecting: RecordingIndicatorBorder.Body.self)
                .contains("_AnimationModifier"),
            "Deleting the real border animation wiring must fail this test"
        )
    }

    @MainActor
    func testRecordingSettingsPanelRendersVisibleStrokeInLightAndDark() throws {
        XCTAssertTrue(
            String(reflecting: RecordingSettingsView.Body.self)
                .contains("RecordingSettingsPanel"),
            "RecordingSettingsView must retain the real stroked panel consumer"
        )

        for fixture in [
            (NSAppearance.Name.aqua, ColorScheme.light),
            (.darkAqua, .dark),
        ] {
            let appearance = try XCTUnwrap(NSAppearance(named: fixture.0))
            let view = RecordingSettingsPanel {
                Color.clear
            }
            .environment(\.colorScheme, fixture.1)
            .frame(width: 320, height: 140)
            .background(ClickerVisualTheme.canvas)
            let bitmap = try renderBitmap(
                view,
                appearance: appearance,
                size: CGSize(width: 320, height: 140)
            )
            let centerX = bitmap.pixelsWide / 2
            let boundary = try XCTUnwrap(
                bitmap.colorAt(x: centerX, y: 1)?.usingColorSpace(.sRGB)
            )
            let interior = try XCTUnwrap(
                bitmap.colorAt(x: centerX, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB)
            )
            XCTAssertGreaterThanOrEqual(try contrastRatio(boundary, interior), 3)
        }
    }

    func testRecordingSettingsUsesScrollableContentAndFixedSafeFooter() {
        let body = String(reflecting: RecordingSettingsView.Body.self)

        XCTAssertTrue(body.contains("ScrollView"), body)
        XCTAssertTrue(body.contains("_InsetViewModifier"), body)
        XCTAssertTrue(body.contains("RecordingSettingsMessage"), body)
        XCTAssertTrue(body.contains("RecordingSettingsFooter"), body)
    }

    @MainActor
    func testRecordingSettingsKeepsBothFooterControlsVisibleAtMaximumDynamicType() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(store: ScriptStore(directory: directory))
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let bitmap = try renderBitmap(
            RecordingSettingsView()
                .environmentObject(state)
                .environment(\.dynamicTypeSize, .accessibility5)
                .environment(\.colorScheme, .light),
            appearance: appearance,
            size: CGSize(width: 440, height: 360)
        )
        let ink = ClickerVisualTheme.resolvedColor(for: .primaryText, appearance: appearance)
        let restoreRegion = CGRect(
            x: CGFloat(bitmap.pixelsWide) * 0.04,
            y: CGFloat(bitmap.pixelsHigh) * 0.82,
            width: CGFloat(bitmap.pixelsWide) * 0.28,
            height: CGFloat(bitmap.pixelsHigh) * 0.16
        )
        let doneRegion = CGRect(
            x: CGFloat(bitmap.pixelsWide) * 0.72,
            y: CGFloat(bitmap.pixelsHigh) * 0.82,
            width: CGFloat(bitmap.pixelsWide) * 0.24,
            height: CGFloat(bitmap.pixelsHigh) * 0.16
        )

        XCTAssertGreaterThan(
            pixelFraction(in: bitmap, region: restoreRegion, near: ink, tolerance: 0.16),
            0.001,
            "Restore Defaults must remain visibly rendered in the fixed footer"
        )
        XCTAssertGreaterThan(
            pixelFraction(in: bitmap, region: doneRegion, near: ink, tolerance: 0.12),
            0.01,
            "Done must remain visibly rendered in the fixed footer"
        )
    }

    @MainActor
    func testRecordingSettingsWarningUsesApprovedReadableForegroundInLightAndDark() throws {
        XCTAssertEqual(
            RecordingSettingsMessage(message: "裸文本键可能在输入文字时误触发").foregroundRole,
            .primaryText
        )
        XCTAssertEqual(RecordingSettingsMessage(message: nil).foregroundRole, .secondaryText)

        for fixture in [
            (NSAppearance.Name.aqua, ColorScheme.light),
            (.darkAqua, .dark),
        ] {
            let appearance = try XCTUnwrap(NSAppearance(named: fixture.0))
            let foreground = ClickerVisualTheme.resolvedColor(
                for: .primaryText,
                appearance: appearance
            )
            let canvas = ClickerVisualTheme.resolvedColor(for: .canvas, appearance: appearance)
            XCTAssertGreaterThanOrEqual(try contrastRatio(foreground, canvas), 4.5)

            let bitmap = try renderBitmap(
                RecordingSettingsMessage(message: "裸文本键可能在输入文字时误触发")
                    .environment(\.colorScheme, fixture.1)
                    .frame(width: 360, height: 64)
                    .background(ClickerVisualTheme.canvas),
                appearance: appearance,
                size: CGSize(width: 360, height: 64)
            )
            XCTAssertGreaterThan(
                pixelFraction(in: bitmap, near: foreground, tolerance: 0.12),
                0.001,
                "The real warning consumer must visibly render its approved foreground"
            )
        }
    }

    func testVisualThemeUsesApprovedLayoutTokens() {
        XCTAssertEqual(ClickerVisualTheme.spacing4, 4)
        XCTAssertEqual(ClickerVisualTheme.spacing8, 8)
        XCTAssertEqual(ClickerVisualTheme.spacing12, 12)
        XCTAssertEqual(ClickerVisualTheme.spacing16, 16)
        XCTAssertEqual(ClickerVisualTheme.spacing24, 24)
        XCTAssertEqual(ClickerVisualTheme.cardCornerRadius, 10)
        XCTAssertEqual(ClickerVisualTheme.panelCornerRadius, 14)
        XCTAssertEqual(ClickerVisualTheme.primaryControlHeight, 44)
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
        let approvedPalette: Set<UInt32> = [
            0xF1_EA_DC,
            0x17_16_19,
            0xE7_38_36,
            0x8B_84_7A,
            0x15_14_18,
            0x23_21_26,
        ]
        let lightAppearanceNames: [NSAppearance.Name] = [
            .aqua,
            .vibrantLight,
            .accessibilityHighContrastAqua,
            .accessibilityHighContrastVibrantLight,
        ]
        let darkAppearanceNames: [NSAppearance.Name] = [
            .darkAqua,
            .vibrantDark,
            .accessibilityHighContrastDarkAqua,
            .accessibilityHighContrastVibrantDark,
        ]

        for appearanceName in lightAppearanceNames {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            for role in ClickerVisualTheme.ColorRole.allCases {
                XCTAssertTrue(
                    approvedPalette.contains(try rgb24(
                        ClickerVisualTheme.resolvedColor(for: role, appearance: appearance)
                    )),
                    "\(role.rawValue) must resolve to one of the independently approved six colors"
                )
            }
        }

        for appearanceName in darkAppearanceNames {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            for role in ClickerVisualTheme.ColorRole.allCases {
                XCTAssertTrue(
                    approvedPalette.contains(try rgb24(
                        ClickerVisualTheme.resolvedColor(for: role, appearance: appearance)
                    )),
                    "\(role.rawValue) must resolve to one of the independently approved six colors"
                )
            }
        }
    }

    func testExportedDynamicThemeProvidersResolveThePaletteAcrossAppearances() throws {
        let lightAppearanceNames: [NSAppearance.Name] = [
            .aqua,
            .vibrantLight,
            .accessibilityHighContrastAqua,
            .accessibilityHighContrastVibrantLight,
        ]
        let darkAppearanceNames: [NSAppearance.Name] = [
            .darkAqua,
            .vibrantDark,
            .accessibilityHighContrastDarkAqua,
            .accessibilityHighContrastVibrantDark,
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

    func testAppearanceClassificationUsesAquaDarkAquaBestMatchForAllEightAppearances() throws {
        let fixtures: [(NSAppearance.Name, Bool)] = [
            (.aqua, false),
            (.vibrantLight, false),
            (.accessibilityHighContrastAqua, false),
            (.accessibilityHighContrastVibrantLight, false),
            (.darkAqua, true),
            (.vibrantDark, true),
            (.accessibilityHighContrastDarkAqua, true),
            (.accessibilityHighContrastVibrantDark, true),
        ]

        for (name, expectedIsDark) in fixtures {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            XCTAssertEqual(
                ClickerVisualTheme.appearanceIsDark(appearance),
                expectedIsDark,
                name.rawValue
            )
        }
    }

    func testSecondaryTextMeetsNormalTextContrastAcrossAppearances() throws {
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let text = ClickerVisualTheme.resolvedColor(for: .secondaryText, appearance: appearance)
            let canvas = ClickerVisualTheme.resolvedColor(for: .canvas, appearance: appearance)
            let card = ClickerVisualTheme.resolvedColor(for: .cardSurface, appearance: appearance)

            XCTAssertGreaterThanOrEqual(try contrastRatio(text, canvas), 4.5)
            XCTAssertGreaterThanOrEqual(try contrastRatio(text, card), 4.5)
        }
    }

    func testProminentButtonRolesUseReadableTextInLightAndDark() throws {
        for role in [ClickerProminentButtonRole.recording, .neutral] {
            for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
                let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
                let fill = ClickerVisualTheme.resolvedColor(
                    for: role.fillRole,
                    appearance: appearance
                )
                let foreground = ClickerVisualTheme.resolvedColor(
                    for: role.foregroundRole,
                    appearance: appearance
                )

                XCTAssertGreaterThanOrEqual(
                    try contrastRatio(foreground, fill),
                    4.5,
                    "\(role) text must remain readable in \(appearanceName.rawValue)"
                )
            }
        }
    }

    func testEveryProminentActionConsumerUsesTheExplicitSharedButton() {
        let consumers: [(String, Any.Type)] = [
            ("record and playback", PrimaryActionBar.Body.self),
            ("recording empty state and permission", ClickerEmptyStateView.Body.self),
            ("settings done", RecordingSettingsFooter.Body.self),
        ]

        for (name, bodyType) in consumers {
            XCTAssertTrue(
                String(reflecting: bodyType).contains("ClickerProminentButton"),
                "\(name) must use ClickerProminentButton so deleting its explicit foreground is observable"
            )
        }
    }

    func testSharedProminentButtonAppliesAnExplicitForegroundForBothSemanticRoles() throws {
        XCTAssertEqual(ClickerProminentButtonRole.recording.fillRole, .playbackFill)
        XCTAssertEqual(ClickerProminentButtonRole.recording.foregroundRole, .prominentForeground)
        XCTAssertEqual(ClickerProminentButtonRole.recording.cueRole, .recordFill)
        XCTAssertEqual(ClickerProminentButtonRole.neutral.fillRole, .playbackFill)
        XCTAssertEqual(ClickerProminentButtonRole.neutral.foregroundRole, .prominentForeground)
        XCTAssertNil(ClickerProminentButtonRole.neutral.cueRole)
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = NSAppearance(named: appearanceName)!
            let cue = ClickerVisualTheme.resolvedColor(for: .recordFill, appearance: appearance)
            let fill = ClickerVisualTheme.resolvedColor(for: .playbackFill, appearance: appearance)
            XCTAssertGreaterThanOrEqual(try contrastRatio(cue, fill), 3)
        }
        XCTAssertTrue(
            String(reflecting: ClickerProminentButton<Text>.Body.self)
                .contains("_ForegroundStyleModifier"),
            "Removing foregroundStyle from the real shared button must fail this test"
        )
        XCTAssertTrue(
            String(reflecting: ClickerProminentButton<Text>.Body.self)
                .contains("_OverlayModifier"),
            "Removing the recording cue overlay from the real shared button must fail this test"
        )
    }

    @MainActor
    func testProminentButtonRasterKeepsRedAsARecordingCueOnly() throws {
        for fixture in [
            (NSAppearance.Name.aqua, ColorScheme.light),
            (.darkAqua, .dark),
        ] {
            let appearance = try XCTUnwrap(NSAppearance(named: fixture.0))
            let record = try renderBitmap(
                ClickerProminentButton(role: .recording, action: {}) { Text("录制") }
                    .environment(\.colorScheme, fixture.1)
                    .frame(width: 160, height: 44),
                appearance: appearance,
                size: CGSize(width: 160, height: 44)
            )
            let neutral = try renderBitmap(
                ClickerProminentButton(role: .neutral, action: {}) { Text("回放") }
                    .environment(\.colorScheme, fixture.1)
                    .frame(width: 160, height: 44),
                appearance: appearance,
                size: CGSize(width: 160, height: 44)
            )
            let cue = ClickerVisualTheme.resolvedColor(for: .recordFill, appearance: appearance)
            let recordFraction = pixelFraction(in: record, near: cue, tolerance: 0.08)
            let neutralFraction = pixelFraction(in: neutral, near: cue, tolerance: 0.08)

            XCTAssertGreaterThan(recordFraction, 0.005)
            XCTAssertLessThan(recordFraction, 0.2, "Red must remain a cue, not the recording fill")
            XCTAssertLessThan(neutralFraction, 0.001)
        }
    }

    func testContrastCalculationRejectsAColorThatCannotConvertToSRGB() {
        let pattern = NSColor(patternImage: NSImage(size: NSSize(width: 1, height: 1)))

        XCTAssertThrowsError(try relativeLuminance(pattern))
    }

    private var paletteExpectations: [
        (role: ClickerVisualTheme.ColorRole, light: (UInt8, UInt8, UInt8), dark: (UInt8, UInt8, UInt8))
    ] {
        [
            (.canvas, (0xF1, 0xEA, 0xDC), (0x15, 0x14, 0x18)),
            (.cardSurface, (0xF1, 0xEA, 0xDC), (0x23, 0x21, 0x26)),
            (.elevatedSurface, (0xF1, 0xEA, 0xDC), (0x23, 0x21, 0x26)),
            (.primaryText, (0x17, 0x16, 0x19), (0xF1, 0xEA, 0xDC)),
            (.secondaryText, (0x17, 0x16, 0x19), (0xF1, 0xEA, 0xDC)),
            (.separator, (0x8B, 0x84, 0x7A), (0x8B, 0x84, 0x7A)),
            (.selection, (0xF1, 0xEA, 0xDC), (0x23, 0x21, 0x26)),
            (.recordFill, (0xE7, 0x38, 0x36), (0xE7, 0x38, 0x36)),
            (.playbackFill, (0x17, 0x16, 0x19), (0xF1, 0xEA, 0xDC)),
            (.prominentForeground, (0xF1, 0xEA, 0xDC), (0x17, 0x16, 0x19)),
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

    private func rgb24(_ color: NSColor) throws -> UInt32 {
        let sRGB = try XCTUnwrap(color.usingColorSpace(.sRGB))
        let red = UInt32((sRGB.redComponent * 255).rounded())
        let green = UInt32((sRGB.greenComponent * 255).rounded())
        let blue = UInt32((sRGB.blueComponent * 255).rounded())
        return red << 16 | green << 8 | blue
    }

    @MainActor
    private func renderBitmap<V: View>(
        _ view: V,
        appearance: NSAppearance,
        size: CGSize
    ) throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = appearance
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    private func bitmapContainsVisibleRecordFill(_ bitmap: NSBitmapImageRep) -> Bool {
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                if abs(color.redComponent - CGFloat(0xE7) / 255) < 0.01,
                   abs(color.greenComponent - CGFloat(0x38) / 255) < 0.01,
                   abs(color.blueComponent - CGFloat(0x36) / 255) < 0.01,
                   color.alphaComponent > 0.8 {
                    return true
                }
            }
        }
        return false
    }

    private func pixelFraction(
        in bitmap: NSBitmapImageRep,
        near target: NSColor,
        tolerance: CGFloat
    ) -> CGFloat {
        guard let target = target.usingColorSpace(.sRGB) else { return 0 }
        var matches = 0
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                if abs(color.redComponent - target.redComponent) <= tolerance,
                   abs(color.greenComponent - target.greenComponent) <= tolerance,
                   abs(color.blueComponent - target.blueComponent) <= tolerance {
                    matches += 1
                }
            }
        }
        return CGFloat(matches) / CGFloat(bitmap.pixelsWide * bitmap.pixelsHigh)
    }

    private func pixelFraction(
        in bitmap: NSBitmapImageRep,
        region: CGRect,
        near target: NSColor,
        tolerance: CGFloat
    ) -> CGFloat {
        guard let target = target.usingColorSpace(.sRGB) else { return 0 }
        let minX = max(0, Int(region.minX.rounded(.down)))
        let maxX = min(bitmap.pixelsWide, Int(region.maxX.rounded(.up)))
        let minY = max(0, Int(region.minY.rounded(.down)))
        let maxY = min(bitmap.pixelsHigh, Int(region.maxY.rounded(.up)))
        guard minX < maxX, minY < maxY else { return 0 }
        var matches = 0
        for y in minY ..< maxY {
            for x in minX ..< maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                if abs(color.redComponent - target.redComponent) <= tolerance,
                   abs(color.greenComponent - target.greenComponent) <= tolerance,
                   abs(color.blueComponent - target.blueComponent) <= tolerance {
                    matches += 1
                }
            }
        }
        return CGFloat(matches) / CGFloat((maxX - minX) * (maxY - minY))
    }


    private func isTrailRed(_ color: NSColor) -> Bool {
        guard let sRGB = color.usingColorSpace(.sRGB) else { return false }
        return sRGB.redComponent == CGFloat(0xE7) / 255
            && sRGB.greenComponent == CGFloat(0x38) / 255
            && sRGB.blueComponent == CGFloat(0x36) / 255
    }

    private func contrastRatio(_ lhs: NSColor, _ rhs: NSColor) throws -> CGFloat {
        let first = try relativeLuminance(lhs)
        let second = try relativeLuminance(rhs)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private func relativeLuminance(_ color: NSColor) throws -> CGFloat {
        guard let color = color.usingColorSpace(.sRGB) else {
            throw ColorConversionError.cannotConvertToSRGB
        }
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

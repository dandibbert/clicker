import AppKit
import ClickerCore
import SwiftUI
import XCTest
@testable import Clicker

final class FinalVisualConsumerTests: XCTestCase {
    @MainActor
    func testPermissionSecondaryActionRemainsBorderedAndLowEmphasis() throws {
        try assertPermissionActionHierarchy()
    }

    @MainActor
    func testAuxiliarySurfacesUseApprovedNeutralSystem() throws {
        try assertAuxiliarySurfaceSystem()
    }

    @MainActor
    func testActionsRenderAsSeparatedRowsWithoutOuterCards() throws {
        let script = Script(
            name: "检查动作行",
            blocks: [
                .wait(WaitBlock(duration: 1)),
                .click(ClickBlock(x: 320, y: 240, button: .left, clickCount: 1)),
            ]
        )
        let size = CGSize(width: 600, height: 280)
        let fixture = try HostedScriptDetailFixture(
            script: script,
            size: size,
            phase: .playing(iteration: 1, currentBlockID: script.blocks[0].id)
        )
        defer { fixture.tearDown() }
        let appearance = fixture.appearance
        let hosting = fixture.hosting

        let outline = try XCTUnwrap(
            nativeControls(in: hosting).compactMap { $0 as? NSOutlineView }.first,
            "The real ScriptDetailView action stack must render"
        )
        XCTAssertEqual(outline.numberOfRows, 2)
        let rowFrames = (0 ..< 2).map {
            hosting.convert(outline.rect(ofRow: $0), from: outline)
        }
        for frame in rowFrames {
            XCTAssertTrue(
                (54 ... 64).contains(frame.height),
                "A compact action row must be 54–64pt high: \(frame)"
            )
        }

        let bitmap = try bitmap(for: hosting)
        let canvas = ClickerVisualTheme.resolvedColor(for: .canvas, appearance: appearance)
        let separator = ClickerVisualTheme.resolvedColor(for: .separator, appearance: appearance)
        let first = rowFrames[0]
        let second = rowFrames[1]
        let selection = ClickerVisualTheme.resolvedColor(for: .selection, appearance: appearance)
        let firstBody = CGRect(
            x: first.minX + 180,
            y: first.minY + 8,
            width: 220,
            height: first.height - 16
        )
        let secondBody = CGRect(
            x: second.minX + 180,
            y: second.minY + 8,
            width: 220,
            height: second.height - 16
        )
        XCTAssertGreaterThan(
            renderedPixelFraction(
                in: bitmap,
                logicalSize: size,
                region: firstBody,
                near: selection,
                tolerance: 0.03
            ),
            0.9,
            "The playing row must render the subtle selection background"
        )
        XCTAssertGreaterThan(
            renderedPixelFraction(
                in: bitmap,
                logicalSize: size,
                region: secondBody,
                near: canvas,
                tolerance: 0.03
            ),
            0.9,
            "The inactive row must remain the flat canvas background"
        )
        XCTAssertLessThan(
            renderedPixelFraction(
                in: bitmap,
                logicalSize: size,
                region: secondBody,
                near: selection,
                tolerance: 0.03
            ),
            0.02,
            "The inactive row must not render an active selection background"
        )

        let activeTrail = try XCTUnwrap(
            visibleRecordCueBounds(
                in: bitmap,
                within: first,
                logicalSize: size
            ),
            "The playing row must render its leading active trail"
        )
        XCTAssertTrue((2.5 ... 3.5).contains(activeTrail.width), "Trail width: \(activeTrail)")
        XCTAssertTrue((29.5 ... 30.5).contains(activeTrail.minX), "Trail position: \(activeTrail)")
        XCTAssertTrue((47.5 ... 48.5).contains(activeTrail.height), "Trail height: \(activeTrail)")
        XCTAssertNil(
            visibleRecordCueBounds(
                in: bitmap,
                within: second,
                logicalSize: size
            ),
            "The inactive row must not render an active trail"
        )
        let outerCornerRegions = [
            CGRect(x: first.minX + 22, y: first.minY + 1, width: 9, height: 9),
            CGRect(x: first.maxX - 31, y: first.minY + 1, width: 9, height: 9),
            CGRect(x: second.minX + 22, y: second.maxY - 10, width: 9, height: 9),
            CGRect(x: second.maxX - 31, y: second.maxY - 10, width: 9, height: 9),
        ]
        for region in outerCornerRegions.suffix(2) {
            XCTAssertGreaterThan(
                renderedPixelFraction(
                    in: bitmap,
                    logicalSize: size,
                    region: region,
                    near: canvas,
                    tolerance: 0.06
                ),
                0.9,
                "Full-row outer corners must remain the flat list background: \(region)"
            )
        }
        for region in outerCornerRegions {
            XCTAssertLessThan(
                renderedPixelFraction(
                    in: bitmap,
                    logicalSize: size,
                    region: region,
                    near: separator,
                    tolerance: 0.06
                ),
                0.02,
                "A rounded outer stroke must not reappear around an action row: \(region)"
            )
        }

        let separatorBounds = try XCTUnwrap(
            visibleColorBounds(
                in: bitmap,
                near: separator,
                tolerance: 0.08,
                within: CGRect(
                    x: first.minX + 22,
                    y: first.maxY - 2,
                    width: first.width - 44,
                    height: 5
                ),
                logicalSize: size
            ),
            "A visible separator must divide adjacent action rows"
        )
        XCTAssertGreaterThan(separatorBounds.width, first.width * 0.8)
        XCTAssertLessThanOrEqual(separatorBounds.height, 2)

        let iconSurface = ClickerVisualTheme.resolvedColor(
            for: .elevatedSurface,
            appearance: appearance
        )
        let iconBounds = try XCTUnwrap(
            visibleRoleBounds(
                in: bitmap,
                logicalSize: size,
                within: CGRect(
                    x: second.minX + 18,
                    y: second.minY + 8,
                    width: 44,
                    height: second.height - 16
                ),
                target: iconSurface,
                excluding: canvas
            ),
            "The 30pt icon surface must remain visibly distinct from the flat row"
        )
        XCTAssertTrue((29 ... 31).contains(iconBounds.width), "Icon width: \(iconBounds)")
        XCTAssertTrue((29 ... 31).contains(iconBounds.height), "Icon height: \(iconBounds)")
    }

    @MainActor
    func testBottomAddActionBarStaysFixedEnabledAndClearOfLastRow() throws {
        let script = Script(
            name: "检查底部动作栏",
            blocks: (0 ..< 12).map { .wait(WaitBlock(duration: Double($0 + 1))) }
        )
        let size = CGSize(width: 760, height: 480)
        let fixture = try HostedScriptDetailFixture(script: script, size: size)
        defer { fixture.tearDown() }
        let state = fixture.state
        let appearance = fixture.appearance
        let hosting = fixture.hosting

        let bitmap = try bitmap(for: hosting)
        let recognizedText = try recognizedTextFrames(in: bitmap, logicalSize: size)
        let buttons = (nativeControls(in: hosting) + descendants(of: hosting))
            .compactMap { $0 as? NSButton }
        let addButton = try XCTUnwrap(
            buttons.first {
                controlLabel($0)?
                    .replacingOccurrences(of: " ", with: "")
                    .contains("添加动作") == true
            } ?? nativeButton(
                recognizing: "添加动作",
                among: buttons,
                recognizedText: recognizedText,
                in: hosting
            ),
            "添加动作 must remain a real native NSButton hit target"
        )
        let bottom48 = CGRect(x: 0, y: size.height - 48, width: size.width, height: 48)
        let buttonFrame = hosting.convert(addButton.bounds, from: addButton)
        XCTAssertTrue(bottom48.contains(buttonFrame), "Add hit target escaped bottom 48pt: \(buttonFrame)")
        XCTAssertTrue(addButton.isEnabled)
        let outline = try XCTUnwrap(
            (nativeControls(in: hosting) + descendants(of: hosting))
                .compactMap { $0 as? NSOutlineView }
                .first
        )

        let barSurface = ClickerVisualTheme.resolvedColor(
            for: .elevatedSurface,
            appearance: appearance
        )
        let canvas = ClickerVisualTheme.resolvedColor(for: .canvas, appearance: appearance)
        for xFraction in [0.01, 0.5, 0.99] {
            let insideBar = try color(
                in: bitmap,
                xFraction: xFraction,
                yFraction: (size.height - 47) / size.height
            )
            let aboveBar = try color(
                in: bitmap,
                xFraction: xFraction,
                yFraction: (size.height - 49) / size.height
            )
            XCTAssertLessThan(
                renderedColorDistance(insideBar, barSurface),
                renderedColorDistance(insideBar, canvas),
                "The fixed full-width bar must begin inside the bottom 48pt"
            )
            XCTAssertLessThan(
                renderedColorDistance(aboveBar, canvas),
                renderedColorDistance(aboveBar, barSurface),
                "The compact bottom bar must not exceed 48pt"
            )
        }

        state.phase = .playing(iteration: 1, currentBlockID: nil)
        fixture.settle()
        XCTAssertFalse(addButton.isEnabled, "Add action must disable while scripts cannot be edited")
        state.phase = .idle
        fixture.settle()
        XCTAssertTrue(addButton.isEnabled, "Add action must re-enable with state.canEditScripts")

        let lastRow = outline.numberOfRows - 1
        XCTAssertGreaterThan(lastRow, 0)
        outline.scrollRowToVisible(lastRow)
        fixture.settle()
        let lastRowFrame = hosting.convert(outline.rect(ofRow: lastRow), from: outline)
        XCTAssertLessThanOrEqual(
            lastRowFrame.maxY,
            bottom48.minY + 1,
            "The fixed add bar must not cover the last scrollable action row"
        )
        XCTAssertGreaterThan(lastRowFrame.minY, 0)
    }

    @MainActor
    func testSelectedScriptKeepsCompactHeaderControlsAndActionListVisibleAtMinimumWindowSize() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(store: ScriptStore(directory: directory))
        let script = Script(
            name: "发布网页并整理窗口",
            blocks: [
                .wait(WaitBlock(duration: 1)),
                .click(ClickBlock(x: 320, y: 240, button: .left, clickCount: 1)),
                .wait(WaitBlock(duration: 0.5)),
            ],
            repeatCount: 3,
            repeatForever: false,
            repeatInterval: 1.5
        )
        state.scripts = [script]
        state.selectedScriptID = script.id
        let size = CGSize(width: 760, height: 480)

        for fixture in [
            (NSAppearance.Name.aqua, ColorScheme.light),
            (.darkAqua, .dark),
        ] {
            let appearance = try XCTUnwrap(NSAppearance(named: fixture.0))
            let hosting = NSHostingView(
                rootView: ScriptDetailView()
                    .environmentObject(state)
                    .environment(\.colorScheme, fixture.1)
                    .frame(width: size.width, height: size.height)
            )
            hosting.appearance = appearance
            hosting.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hosting
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))

            let bitmap = try bitmap(for: hosting)
            let controls = nativeControls(in: hosting)
            let actionList = try XCTUnwrap(
                controls.compactMap { $0 as? NSOutlineView }.first,
                "The real selected-script action list must render"
            )
            let actionListFrame = hosting.convert(actionList.bounds, from: actionList)
            XCTAssertTrue(
                (96 ... 104).contains(actionListFrame.minY),
                "The measured header boundary is \(actionListFrame.minY)pt in \(fixture.0.rawValue)"
            )
            let headerBounds = CGRect(
                x: 0,
                y: 0,
                width: size.width,
                height: actionListFrame.minY
            )

            let recognizedText = try recognizedTextFrames(in: bitmap, logicalSize: size)
            let recordText = try XCTUnwrap(
                recognizedText.first {
                    $0.text.replacingOccurrences(of: " ", with: "").contains("录制")
                },
                "The real selected-script consumer must render the record action"
            )
            let playbackText = try XCTUnwrap(
                recognizedText.first {
                    $0.text.replacingOccurrences(of: " ", with: "").contains("回放")
                },
                "The real selected-script consumer must render the playback action"
            )
            let headerSurface = try XCTUnwrap(
                visibleColorBounds(
                    in: bitmap,
                    near: ClickerVisualTheme.resolvedColor(for: .controlSurface, appearance: appearance),
                    tolerance: 0.08,
                    within: headerBounds,
                    logicalSize: size
                ),
                "The compact header must render its approved neutral surface"
            )
            XCTAssertTrue(headerSurface.contains(recordText.frame))
            XCTAssertTrue(headerSurface.contains(playbackText.frame))
            let midpoint = (recordText.frame.maxX + playbackText.frame.minX) / 2
            let recordBounds = try XCTUnwrap(
                visibleRecordCueBounds(
                    in: bitmap,
                    within: CGRect(x: 0, y: 0, width: midpoint, height: headerBounds.height),
                    logicalSize: size
                ),
                "The selected-script record action must retain its approved red cue"
            )
            let playbackBounds = try XCTUnwrap(
                visibleColorBounds(
                    in: bitmap,
                    near: ClickerVisualTheme.resolvedColor(for: .playbackFill, appearance: appearance),
                    tolerance: 0.08,
                    within: playbackText.frame
                        .insetBy(dx: -24, dy: -14)
                        .intersection(headerBounds),
                    logicalSize: size
                ),
                "The selected-script playback action must retain its approved neutral fill"
            )
            for (name, bounds, text) in [
                ("record", recordBounds, recordText.frame),
                ("playback", playbackBounds, playbackText.frame),
            ] {
                XCTAssertTrue(headerBounds.contains(bounds), "\(name) escaped the compact header: \(bounds)")
                XCTAssertTrue(bounds.contains(text), "\(name) label escaped its semantic boundary")
                XCTAssertTrue((36 ... 40).contains(bounds.height), "\(name) height: \(bounds)")
                XCTAssertLessThan(bounds.width, 96, "\(name) width: \(bounds)")
            }

            for label in ["次数", "秒"] {
                let element = try XCTUnwrap(
                    controls.first { controlLabel($0) == label },
                    "\(label) must remain rendered by the real repeat/interval controls"
                )
                XCTAssertTrue(
                    hosting.bounds.contains(hosting.convert(element.bounds, from: element)),
                    "\(label) must remain inside the 760×480 viewport"
                )
            }

            XCTAssertTrue(hosting.bounds.contains(actionListFrame))
            XCTAssertGreaterThan(
                actionListFrame.height,
                316,
                "The compact header must expose more list pixels than the previous 316pt baseline"
            )
        }
    }

    @MainActor
    func testPrimaryActionsRenderAsCompactPeerControls() throws {
        _ = NSApplication.shared

        for fixture in [
            (NSAppearance.Name.aqua, ColorScheme.light),
            (.darkAqua, .dark),
        ] {
            let appearance = try XCTUnwrap(NSAppearance(named: fixture.0))
            let hosting = NSHostingView(
                rootView: PrimaryActionBar(phase: .idle, hasPlayableScript: true)
                    .environment(\.colorScheme, fixture.1)
                    .frame(width: 260, height: 60, alignment: .leading)
                    .background(ClickerVisualTheme.windowBackground)
            )
            hosting.appearance = appearance
            hosting.frame = CGRect(x: 0, y: 0, width: 260, height: 60)
            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hosting
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))

            let bitmap = try bitmap(for: hosting)
            let recognizedText = try recognizedTextFrames(in: bitmap, logicalSize: hosting.bounds.size)
            let recordText = try XCTUnwrap(
                recognizedText.first {
                    $0.text.replacingOccurrences(of: " ", with: "").contains("录制")
                },
                "The real record action must remain rendered: \(recognizedText)"
            )
            let playbackText = try XCTUnwrap(
                recognizedText.first {
                    $0.text.replacingOccurrences(of: " ", with: "").contains("回放")
                },
                "The real playback action must remain rendered: \(recognizedText)"
            )

            let playbackFill = ClickerVisualTheme.resolvedColor(for: .playbackFill, appearance: appearance)
            let midpoint = (recordText.frame.maxX + playbackText.frame.minX) / 2
            let recordBounds = try XCTUnwrap(
                visibleRecordCueBounds(
                    in: bitmap,
                    within: CGRect(x: 0, y: 0, width: midpoint, height: hosting.bounds.height),
                    logicalSize: hosting.bounds.size
                ),
                "The record action must render a visible red boundary cue"
            )
            let playbackBounds = try XCTUnwrap(
                visibleColorBounds(
                    in: bitmap,
                    near: playbackFill,
                    tolerance: 0.08,
                    within: CGRect(
                        x: midpoint,
                        y: 0,
                        width: hosting.bounds.width - midpoint,
                        height: hosting.bounds.height
                    ),
                    logicalSize: hosting.bounds.size
                ),
                "The playback action must render its explicit neutral fill"
            )

            for (name, bounds, text) in [
                ("record", recordBounds, recordText.frame),
                ("playback", playbackBounds, playbackText.frame),
            ] {
                XCTAssertTrue((36 ... 40).contains(bounds.height), "\(name) height: \(bounds)")
                XCTAssertLessThan(bounds.width, 96, "\(name) width: \(bounds)")
                XCTAssertTrue(bounds.contains(text), "\(name) label escaped its rendered control: \(text), \(bounds)")
            }
        }
    }

    @MainActor
    func testProminentButtonRendersReadableForegroundAgainstItsActualFill() throws {
        for fixture in [
            (NSAppearance.Name.aqua, ColorScheme.light),
            (.darkAqua, .dark),
        ] {
            for role in [ClickerProminentButtonRole.recording, .neutral] {
                let appearance = try XCTUnwrap(NSAppearance(named: fixture.0))
                let bitmap = try renderBitmap(
                    ClickerProminentButton(role: role, action: {}) {
                        Rectangle()
                            .fill(.foreground)
                            .frame(width: 12, height: 12)
                    }
                    .environment(\.colorScheme, fixture.1)
                    .frame(width: 160, height: 44)
                    .background(ClickerVisualTheme.canvas),
                    appearance: appearance,
                    size: CGSize(width: 160, height: 44)
                )
                let foreground = try color(
                    in: bitmap,
                    xFraction: 0.5,
                    yFraction: 0.5
                )
                let fill = try color(
                    in: bitmap,
                    xFraction: 0.44,
                    yFraction: 0.5
                )

                XCTAssertGreaterThanOrEqual(
                    contrastRatio(foreground, fill),
                    4.5,
                    "\(role) must render readable foreground in \(fixture.0.rawValue)"
                )
            }
        }
    }

    @MainActor
    func testPulsingActiveTrailRendersAtLeastThreeToOneAtItsLowPoint() throws {
        for fixture in [
            (NSAppearance.Name.aqua, ColorScheme.light),
            (.darkAqua, .dark),
        ] {
            let appearance = try XCTUnwrap(NSAppearance(named: fixture.0))
            let bitmap = try renderBitmap(
                ActionCardActiveTrail(feedbackStyle: .pulsingTrail, isDimmed: true)
                    .environment(\.colorScheme, fixture.1)
                    .frame(width: 24, height: 80, alignment: .leading)
                    .background(ClickerVisualTheme.cardSurface),
                appearance: appearance,
                size: CGSize(width: 24, height: 80)
            )
            let background = try color(
                in: bitmap,
                xFraction: 0.9,
                yFraction: 0.5
            )
            let centerY = bitmap.pixelsHigh / 2
            let trailContrast = try (0 ..< min(12, bitmap.pixelsWide))
                .map { x in
                    try contrastRatio(color(in: bitmap, x: x, y: centerY), background)
                }
                .max() ?? 0

            XCTAssertGreaterThanOrEqual(
                trailContrast,
                3,
                "The rendered pulse low point must retain 3:1 in \(fixture.0.rawValue)"
            )
        }
    }

    @MainActor
    func testRecordingSettingsRendersAppearanceChoicesAndReplacesLegacyShortcutForm() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(store: ScriptStore(directory: directory))
        let size = CGSize(width: 440, height: 360)

        for fixture in [
            (NSAppearance.Name.aqua, ColorScheme.light),
            (.darkAqua, .dark),
        ] {
            let appearance = try XCTUnwrap(NSAppearance(named: fixture.0))
            let bitmap = try renderBitmap(
                RecordingSettingsView()
                    .environmentObject(state)
                    .environment(\.colorScheme, fixture.1),
                appearance: appearance,
                size: size
            )
            let renderedCopy = try recognizedTextFrames(in: bitmap, logicalSize: size)
                .map(\.text)
                .joined()
                .replacingOccurrences(of: " ", with: "")

            for expected in [
                "通用", "外观", "跟随系统", "浅色", "深色",
                "录制", "停止录制快捷键", "恢复默认设置",
            ] {
                XCTAssertTrue(
                    renderedCopy.contains(expected),
                    "The real settings consumer must render \(expected) in \(fixture.0.rawValue): \(renderedCopy)"
                )
            }
            XCTAssertFalse(renderedCopy.contains("当前快捷键"), renderedCopy)
            XCTAssertFalse(renderedCopy.contains("更改快捷键"), renderedCopy)
            XCTAssertFalse(renderedCopy.contains("完成"), renderedCopy)
        }
    }

    @MainActor
    func testResetRemainsLowEmphasisAndNoFooterAppearsInStandardViewport() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let shortcutStore = FinalVisualShortcutStoreStub(shortcut: RecordingStopShortcut(
            keyCode: 1,
            modifierFlags: KeyCodeMap.maskControl
        ))
        let appearanceStore = FinalVisualAppearanceStoreStub(preference: .dark)
        let state = AppState(
            store: ScriptStore(directory: directory),
            stopShortcutStore: shortcutStore,
            appearancePreferenceStore: appearanceStore
        )
        let hosting = NSHostingView(
            rootView: RecordingSettingsView()
                .environmentObject(state)
                .environment(\.colorScheme, .light)
        )
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = CGRect(x: 0, y: 0, width: 440, height: 360)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let renderedText = try recognizedTextFrames(
            in: bitmap(for: hosting),
            logicalSize: hosting.bounds.size
        )
        let restoreLabel = try XCTUnwrap(
            renderedText.first { $0.text.replacingOccurrences(of: " ", with: "").contains("恢复默认设置") }
        )
        XCTAssertTrue(hosting.bounds.contains(restoreLabel.frame))
        XCTAssertFalse(renderedText.contains { $0.text.contains("完成") })

        let restoreButton = try XCTUnwrap(
            nativeButton(
                recognizing: "恢复默认设置",
                among: nativeControls(in: hosting).compactMap { $0 as? NSButton },
                recognizedText: renderedText,
                in: hosting
            ),
            "Reset must remain a stable native action boundary"
        )
        let restoreBounds = hosting.convert(restoreButton.bounds, from: restoreButton)
        XCTAssertTrue(restoreButton.isEnabled)
        XCTAssertTrue(hosting.bounds.contains(restoreBounds))
        XCTAssertTrue(restoreBounds.contains(restoreLabel.frame))
        restoreButton.performClick(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(shortcutStore.shortcut, .defaultValue)
        XCTAssertEqual(appearanceStore.preference, .system)

        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        XCTAssertLessThan(
            renderedPixelFraction(
                in: try bitmap(for: hosting),
                logicalSize: hosting.bounds.size,
                region: restoreBounds,
                near: ClickerVisualTheme.resolvedColor(for: .playbackFill, appearance: appearance),
                tolerance: 0.04
            ),
            0.35,
            "Reset must not use a large prominent primary fill"
        )

        let renderedCopy = renderedText
            .map(\.text)
            .joined()
            .replacingOccurrences(of: " ", with: "")
        for expected in ["通用", "外观", "录制", "停止录制快捷键", "恢复默认设置"] {
            XCTAssertTrue(
                renderedCopy.contains(expected),
                "\(expected) must remain rendered in the standard hosted viewport: \(renderedCopy)"
            )
        }
    }

}

private final class FinalVisualShortcutStoreStub: RecordingStopShortcutProviding {
    var shortcut: RecordingStopShortcut

    init(shortcut: RecordingStopShortcut) {
        self.shortcut = shortcut
    }
}

private final class FinalVisualAppearanceStoreStub: AppAppearancePreferenceProviding {
    var preference: AppAppearancePreference

    init(preference: AppAppearancePreference) {
        self.preference = preference
    }
}

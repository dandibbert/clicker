import AppKit
import ClickerCore
import SwiftUI
import XCTest
@testable import Clicker

final class FinalVisualConsumerTests: XCTestCase {
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

            for expected in ["外观", "跟随系统", "浅色", "深色"] {
                XCTAssertTrue(
                    renderedCopy.contains(expected),
                    "The real settings consumer must render \(expected) in \(fixture.0.rawValue): \(renderedCopy)"
                )
            }
            XCTAssertFalse(renderedCopy.contains("当前快捷键"), renderedCopy)
            XCTAssertFalse(renderedCopy.contains("更改快捷键"), renderedCopy)
        }
    }

    @MainActor
    func testFooterControlsRemainEnabledDistinctAndInsideStandardViewport() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(store: ScriptStore(directory: directory))
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
            renderedText.first { $0.text.replacingOccurrences(of: " ", with: "").contains("恢复默认值") }
        )
        let doneLabel = try XCTUnwrap(
            renderedText.first { $0.text.replacingOccurrences(of: " ", with: "").contains("完成") }
        )
        XCTAssertTrue(hosting.bounds.contains(restoreLabel.frame))
        XCTAssertTrue(hosting.bounds.contains(doneLabel.frame))

        let restoreButton = try XCTUnwrap(
            nativeButton(
                recognizing: "恢复默认值",
                among: nativeControls(in: hosting).compactMap { $0 as? NSButton },
                recognizedText: renderedText,
                in: hosting
            ),
            "The bordered restore action must remain a native hit target"
        )
        let restoreBounds = hosting.convert(restoreButton.bounds, from: restoreButton)
        XCTAssertTrue(restoreButton.isEnabled)
        XCTAssertTrue(hosting.bounds.contains(restoreBounds))
        XCTAssertTrue(restoreBounds.contains(restoreLabel.frame))

        let midpoint = (restoreLabel.frame.maxX + doneLabel.frame.minX) / 2
        let footerRegion = CGRect(
            x: midpoint,
            y: hosting.bounds.height - 80,
            width: hosting.bounds.width - midpoint,
            height: 80
        )
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let doneBounds = try XCTUnwrap(
            visibleColorBounds(
                in: bitmap(for: hosting),
                near: ClickerVisualTheme.resolvedColor(for: .playbackFill, appearance: appearance),
                tolerance: 0.08,
                within: footerRegion,
                logicalSize: hosting.bounds.size
            ),
            "The enabled Done action must render the shared prominent neutral fill"
        )
        XCTAssertTrue(hosting.bounds.contains(doneBounds))
        XCTAssertTrue(doneBounds.contains(doneLabel.frame))
        XCTAssertFalse(doneBounds.intersects(restoreBounds))
        XCTAssertTrue((36 ... 40).contains(doneBounds.height), "Done height: \(doneBounds)")

        let renderedCopy = renderedText
            .map(\.text)
            .joined()
            .replacingOccurrences(of: " ", with: "")
        for expected in ["外观", "停止录制快捷键", "恢复默认值", "完成"] {
            XCTAssertTrue(
                renderedCopy.contains(expected),
                "\(expected) must remain rendered in the standard hosted viewport: \(renderedCopy)"
            )
        }
    }

}

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
            let separator = ClickerVisualTheme.resolvedColor(for: .separator, appearance: appearance)
            let primaryText = ClickerVisualTheme.resolvedColor(for: .primaryText, appearance: appearance)
            let headerBottomPixel = try XCTUnwrap(
                highestFullWidthSeparatorRow(in: bitmap, near: [separator, primaryText]),
                "The real header consumer must keep a visible bottom separator"
            )
            let scale = CGFloat(bitmap.pixelsHigh) / size.height
            let headerHeight = CGFloat(headerBottomPixel) / scale
            XCTAssertLessThanOrEqual(
                headerHeight,
                104,
                "The real header is \(headerHeight)pt tall in \(fixture.0.rawValue)"
            )

            let controls = nativeControls(in: hosting)
            XCTAssertEqual(
                PrimaryActionPresentation.pair(phase: .idle, hasPlayableScript: true).map(\.title),
                ["录制", "回放"]
            )
            let primaryButtons = controls.compactMap { $0 as? NSButton }.filter {
                !($0 is NSPopUpButton)
            }
            XCTAssertEqual(primaryButtons.count, 2, "Both labeled primary actions must render")
            for button in primaryButtons {
                let frame = hosting.convert(button.bounds, from: button)
                XCTAssertGreaterThanOrEqual(frame.width, 44)
                XCTAssertGreaterThanOrEqual(frame.height, 44)
                XCTAssertLessThanOrEqual(frame.maxY, headerHeight)
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

            let actionList = try XCTUnwrap(
                controls.compactMap { $0 as? NSOutlineView }.first,
                "The real selected-script action list must render"
            )
            let actionListFrame = hosting.convert(actionList.bounds, from: actionList)
            XCTAssertGreaterThanOrEqual(actionListFrame.minY, headerHeight)
            XCTAssertGreaterThan(
                actionListFrame.height,
                316,
                "The compact header must expose more list pixels than the previous 316pt baseline"
            )
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
    func testMaximumDynamicTypeFooterControlsAreEnabledNativeHitTargetsInsideViewport() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(store: ScriptStore(directory: directory))
        let hosting = NSHostingView(
            rootView: RecordingSettingsView()
                .environmentObject(state)
                .environment(\.dynamicTypeSize, .accessibility5)
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

        let restorePoint = NSPoint(x: 78, y: 28)
        let donePoint = NSPoint(x: 392, y: 28)
        XCTAssertTrue(hosting.bounds.contains(restorePoint))
        XCTAssertTrue(hosting.bounds.contains(donePoint))
        let restoreButton = try XCTUnwrap(hosting.hitTest(restorePoint) as? NSButton)
        let doneButton = try XCTUnwrap(hosting.hitTest(donePoint) as? NSButton)
        XCTAssertFalse(restoreButton === doneButton)
        XCTAssertTrue(restoreButton.isEnabled)
        XCTAssertTrue(doneButton.isEnabled)
        XCTAssertTrue(hosting.bounds.contains(restoreButton.convert(restoreButton.bounds, to: hosting)))
        XCTAssertTrue(hosting.bounds.contains(doneButton.convert(doneButton.bounds, to: hosting)))
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

    @MainActor
    private func bitmap(for hosting: NSHostingView<some View>) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    private func highestFullWidthSeparatorRow(
        in bitmap: NSBitmapImageRep,
        near expected: [NSColor]
    ) -> Int? {
        let expectedSRGB = expected.compactMap { $0.usingColorSpace(.sRGB) }
        return (1 ..< bitmap.pixelsHigh - 1).first { y in
            let matchingPixels = (0 ..< bitmap.pixelsWide).reduce(into: 0) { count, x in
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return }
                if expectedSRGB.contains(where: { expected in
                    abs(pixel.redComponent - expected.redComponent)
                        + abs(pixel.greenComponent - expected.greenComponent)
                        + abs(pixel.blueComponent - expected.blueComponent) < 0.3
                }) {
                    count += 1
                }
            }
            return CGFloat(matchingPixels) / CGFloat(bitmap.pixelsWide) > 0.99
        }
    }

    @MainActor
    private func nativeControls<V: View>(in hosting: NSHostingView<V>) -> [NSView] {
        var controls: [ObjectIdentifier: NSView] = [:]
        for y in stride(from: 0, through: Int(hosting.bounds.height), by: 4) {
            for x in stride(from: 0, through: Int(hosting.bounds.width), by: 4) {
                guard let view = hosting.hitTest(CGPoint(x: x, y: y)) else { continue }
                controls[ObjectIdentifier(view)] = view
            }
        }
        return Array(controls.values)
    }

    private func controlLabel(_ view: NSView) -> String? {
        if let label = view.accessibilityLabel(), !label.isEmpty { return label }
        if let field = view as? NSTextField { return field.placeholderString }
        if let button = view as? NSButton, !button.title.isEmpty { return button.title }
        return nil
    }

    private func color(
        in bitmap: NSBitmapImageRep,
        xFraction: CGFloat,
        yFraction: CGFloat
    ) throws -> NSColor {
        try color(
            in: bitmap,
            x: min(bitmap.pixelsWide - 1, Int(CGFloat(bitmap.pixelsWide) * xFraction)),
            y: min(bitmap.pixelsHigh - 1, Int(CGFloat(bitmap.pixelsHigh) * yFraction))
        )
    }

    private func color(in bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
        try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
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

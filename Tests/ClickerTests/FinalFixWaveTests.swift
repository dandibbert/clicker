import AppKit
import ClickerCore
import SwiftUI
import Vision
import XCTest
@testable import Clicker

final class FinalFixWaveTests: XCTestCase {
    @MainActor
    func testRecordAndPlaybackRasterKeepTheirSemanticRolesInBothAppearances() throws {
        for fixture in [
            (NSAppearance.Name.aqua, ColorScheme.light, rgb(0xF7, 0xF7, 0xF8)),
            (.darkAqua, .dark, rgb(0xF5, 0xF5, 0xF7)),
        ] {
            let appearance = try XCTUnwrap(NSAppearance(named: fixture.0))
            let record = try renderButton(
                role: .recording,
                title: "录制",
                appearance: appearance,
                scheme: fixture.1
            )
            let playback = try renderButton(
                role: .neutral,
                title: "回放",
                appearance: appearance,
                scheme: fixture.1
            )
            let fillProbe = CGRect(x: 25, y: 16, width: 14, height: 22)
            let textProbe = CGRect(x: 40, y: 15, width: 40, height: 24)
            let controlRegion = CGRect(x: 16, y: 8, width: 88, height: 38)

            XCTAssertGreaterThan(
                pixelFraction(in: record, region: fillProbe, near: fixture.2, tolerance: 0.05),
                0.8,
                "Recording must use a light surface in \(fixture.0.rawValue)"
            )
            XCTAssertGreaterThan(
                pixelFraction(in: record, region: textProbe, matching: isRed),
                0.015,
                "Recording text must render red in \(fixture.0.rawValue)"
            )
            XCTAssertGreaterThan(
                pixelFraction(in: record, region: controlRegion, matching: isBrightRed),
                0.025,
                "Recording must retain a red boundary in \(fixture.0.rawValue)"
            )

            let charcoal = rgb(0x3C, 0x3C, 0x40)
            let white = rgb(0xF5, 0xF5, 0xF7)
            XCTAssertGreaterThan(
                pixelFraction(in: playback, region: fillProbe, near: charcoal, tolerance: 0.04),
                0.8,
                "Playback must keep its charcoal fill in \(fixture.0.rawValue)"
            )
            XCTAssertGreaterThan(
                pixelFraction(in: playback, region: textProbe, near: white, tolerance: 0.08),
                0.015,
                "Playback text must remain white in \(fixture.0.rawValue)"
            )
            XCTAssertLessThan(
                pixelFraction(in: playback, region: controlRegion, matching: isRed),
                0.001,
                "Playback must not inherit the recording boundary"
            )
        }
    }

    @MainActor
    func testCheckedNativeControlsRejectBlueInMainSettingsAndEditor() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(store: ScriptStore(directory: directory))
        let script = Script(
            name: "中性色检查",
            blocks: [.wait(WaitBlock(duration: 1))],
            repeatForever: true
        )
        state.hasPermission = true
        state.scripts = [script]
        state.selectedScriptID = script.id
        state.appearancePreference = .light

        for appearanceFixture in [
            (NSAppearance.Name.aqua, ColorScheme.light),
            (.darkAqua, .dark),
        ] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceFixture.0))
            let main = try HostedViewFixture(
                rootView: AnyView(
                    MainView()
                        .environmentObject(state)
                        .environment(\.colorScheme, appearanceFixture.1)
                        .tint(.blue)
                ),
                appearance: appearance,
                size: CGSize(width: 760, height: 480)
            )
            defer { main.tearDown() }
            try assertNoBlue(
                in: main,
                region: try renderedControlRegion(containing: "无限", in: main),
                name: "main 无限 in \(appearanceFixture.0.rawValue)"
            )

            let settings = try HostedViewFixture(
                rootView: AnyView(
                    RecordingSettingsView()
                        .environmentObject(state)
                        .environment(\.colorScheme, appearanceFixture.1)
                        .tint(.blue)
                ),
                appearance: appearance,
                size: CGSize(width: 440, height: 360)
            )
            defer { settings.tearDown() }
            let segmented = try XCTUnwrap(
                descendants(of: settings.hosting).compactMap { $0 as? NSSegmentedControl }.first
            )
            try assertNoBlue(
                in: settings,
                region: settings.hosting.convert(segmented.bounds, from: segmented),
                name: "settings appearance segmented in \(appearanceFixture.0.rawValue)"
            )

            let editor = try HostedViewFixture(
                rootView: AnyView(
                    BlockEditorView(
                        block: .shortcut(ShortcutBlock(
                            keyCode: 8,
                            flags: KeyCodeMap.maskCommand
                        )),
                        onSave: { _ in true }
                    )
                    .environment(\.colorScheme, appearanceFixture.1)
                    .tint(.blue)
                ),
                appearance: appearance,
                size: CGSize(width: 380, height: 340)
            )
            defer { editor.tearDown() }
            try assertNoBlue(
                in: editor,
                region: try renderedControlRegion(containing: "Command", in: editor),
                name: "editor Command toggle in \(appearanceFixture.0.rawValue)"
            )
        }
    }

    @MainActor
    func testNeutralControlScopeOverridesAnInjectedBlueTint() throws {
        for appearanceFixture in [
            (NSAppearance.Name.aqua, ColorScheme.light),
            (.darkAqua, .dark),
        ] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceFixture.0))
            let fixture = try HostedViewFixture(
                rootView: AnyView(
                    ClickerNeutralControlScope {
                        Rectangle()
                            .fill(.tint)
                            .frame(width: 32, height: 32)
                    }
                    .environment(\.colorScheme, appearanceFixture.1)
                    .tint(.blue)
                ),
                appearance: appearance,
                size: CGSize(width: 40, height: 40)
            )
            defer { fixture.tearDown() }
            let bitmap = try XCTUnwrap(
                fixture.hosting.bitmapImageRepForCachingDisplay(in: fixture.hosting.bounds)
            )
            fixture.hosting.cacheDisplay(in: fixture.hosting.bounds, to: bitmap)
            let center = try XCTUnwrap(
                bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
                    .usingColorSpace(.sRGB)
            )
            let expected = ClickerVisualTheme.resolvedColor(
                for: .focusRing,
                appearance: appearance
            )
            XCTAssertLessThan(colorDistance(center, expected), 0.09)
            XCTAssertFalse(isSystemBlue(center))
        }
    }

    @MainActor
    func testProminentAndShortcutSurfacesRenderStatesAndRetainRealClickActions() throws {
        var prominentClicks = 0
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let normal = try renderInteractiveSurface(state: .init(), appearance: appearance)
        for state in [
            ClickerInteractiveSurfaceState(isHovered: true),
            ClickerInteractiveSurfaceState(isPressed: true),
            ClickerInteractiveSurfaceState(isEnabled: false),
            ClickerInteractiveSurfaceState(isFocused: true),
        ] {
            let rendered = try renderInteractiveSurface(state: state, appearance: appearance)
            XCTAssertGreaterThan(
                differingPixelCount(normal, rendered),
                80,
                "The hosted shared surface must visibly distinguish \(state)"
            )
        }

        let prominent = try HostedViewFixture(
            rootView: AnyView(
                ClickerProminentButton(role: .neutral, action: { prominentClicks += 1 }) {
                    Text("回放").frame(width: 72)
                }
                .frame(width: 160, height: 54)
            ),
            appearance: appearance,
            size: CGSize(width: 160, height: 54)
        )
        defer { prominent.tearDown() }
        try click(at: CGPoint(x: 80, y: 27), in: prominent.window)
        XCTAssertEqual(prominentClicks, 1, "The surface must retain Button action semantics")

        var shortcutClicks = 0
        let shortcut = try HostedViewFixture(
            rootView: AnyView(
                ShortcutCaptureCard(
                    shortcut: .defaultValue,
                    isCapturing: false,
                    action: { shortcutClicks += 1 }
                )
                .frame(width: 392)
            ),
            appearance: appearance,
            size: CGSize(width: 392, height: 80)
        )
        defer { shortcut.tearDown() }
        try click(at: CGPoint(x: 196, y: 40), in: shortcut.window)
        XCTAssertEqual(shortcutClicks, 1, "The capture card must remain one Button action")
    }

    func testInteractiveSurfaceModelMakesEveryRequiredStateExplicit() {
        let normal = ClickerInteractiveSurfacePresentation(state: .init())
        let hover = ClickerInteractiveSurfacePresentation(state: .init(isHovered: true))
        let pressed = ClickerInteractiveSurfacePresentation(state: .init(isPressed: true))
        let disabled = ClickerInteractiveSurfacePresentation(state: .init(isEnabled: false))
        let focused = ClickerInteractiveSurfacePresentation(state: .init(isFocused: true))

        XCTAssertEqual(normal.overlayOpacity, 0)
        XCTAssertGreaterThan(hover.overlayOpacity, normal.overlayOpacity)
        XCTAssertGreaterThan(pressed.overlayOpacity, hover.overlayOpacity)
        XCTAssertLessThan(pressed.scale, normal.scale)
        XCTAssertLessThan(disabled.contentOpacity, normal.contentOpacity)
        XCTAssertEqual(disabled.overlayOpacity, 0)
        XCTAssertEqual(disabled.focusLineWidth, 0)
        XCTAssertGreaterThan(focused.focusLineWidth, normal.focusLineWidth)
        XCTAssertEqual(focused.contentOpacity, normal.contentOpacity)
    }

    @MainActor
    func testAddActionMenuProvidesARealThirtyTwoPointEdgeToEdgeHitTarget() throws {
        let script = Script(
            name: "动作菜单命中",
            blocks: [.wait(WaitBlock(duration: 1))]
        )
        let fixture = try HostedScriptDetailFixture(
            script: script,
            size: CGSize(width: 760, height: 480)
        )
        defer { fixture.tearDown() }
        let hosting = fixture.hosting
        let hitViews = hitTestViews(
            in: hosting,
            region: CGRect(x: 0, y: 432, width: 240, height: 48)
        )
        let addButton = try XCTUnwrap(
            (descendants(of: hosting) + hitViews).compactMap { $0 as? NSButton }.first {
                $0.title.replacingOccurrences(of: " ", with: "").contains("添加动作")
                    || $0.accessibilityLabel()?
                        .replacingOccurrences(of: " ", with: "")
                        .contains("添加动作") == true
            },
            "添加动作 must remain a real native NSButton"
        )
        let frame = hosting.convert(addButton.bounds, from: addButton)
        XCTAssertGreaterThanOrEqual(frame.width, 32, "Add action width: \(frame)")
        XCTAssertGreaterThanOrEqual(frame.height, 32, "Add action height: \(frame)")
        let points = [
            CGPoint(x: frame.minX + 2, y: frame.midY),
            CGPoint(x: frame.maxX - 2, y: frame.midY),
            CGPoint(x: frame.midX, y: frame.minY + 2),
            CGPoint(x: frame.midX, y: frame.maxY - 2),
            CGPoint(x: frame.midX, y: frame.midY),
        ]
        for point in points {
            let localPoint = addButton.convert(point, from: hosting)
            let hit = try XCTUnwrap(addButton.hitTest(localPoint), "No native hit at \(point)")
            XCTAssertTrue(
                hit === addButton || hit.isDescendant(of: addButton),
                "Add action edge escaped its native hit target at \(point): \(hit)"
            )
        }
    }

    @MainActor
    func testAccessibilityFiveGrowsHeaderAndCardWithoutClippingContent() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(store: ScriptStore(directory: directory))
        state.hasPermission = true
        let script = Script(
            name: "辅助字号脚本",
            blocks: [.wait(WaitBlock(duration: 1))],
            repeatCount: 3,
            repeatForever: true,
            repeatInterval: 1.5
        )
        state.scripts = [script]
        state.selectedScriptID = script.id
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))

        let normalHeader = try fittingFixture(
            AnyView(
                ScriptHeaderView(script: script)
                    .environmentObject(state)
                    .environment(\.dynamicTypeSize, .large)
                    .frame(width: 760)
            ),
            appearance: appearance
        )
        defer { normalHeader.tearDown() }
        XCTAssertEqual(normalHeader.hosting.bounds.height, 100, accuracy: 1)

        let largeHeader = try fittingFixture(
            AnyView(
                ScriptHeaderView(script: script)
                    .environmentObject(state)
                    .environment(\.dynamicTypeSize, .accessibility5)
                    .frame(width: 760)
            ),
            appearance: appearance
        )
        defer { largeHeader.tearDown() }
        XCTAssertGreaterThan(largeHeader.hosting.bounds.height, 100)
        try assertRenderedContentIsContained(
            in: largeHeader,
            required: ["辅助字号脚本", "录制", "回放", "重复", "无限", "间隔"]
        )
        let headerFields = descendants(of: largeHeader.hosting).compactMap { $0 as? NSTextField }
            .filter { ["次数", "秒"].contains($0.placeholderString) }
        XCTAssertEqual(headerFields.count, 2)
        for field in headerFields {
            XCTAssertTrue(
                largeHeader.hosting.bounds.contains(
                    largeHeader.hosting.convert(field.bounds, from: field)
                ),
                "An accessibility-size repeat control escaped the header"
            )
        }

        let shortcut = RecordingStopShortcut(
            keyCode: 14,
            modifierFlags: KeyCodeMap.maskControl
                | KeyCodeMap.maskOption
                | KeyCodeMap.maskShift
                | KeyCodeMap.maskCommand
        )
        let normalCard = try fittingFixture(
            AnyView(
                ShortcutCaptureCard(shortcut: shortcut, isCapturing: false, action: {})
                    .environment(\.dynamicTypeSize, .large)
                    .frame(width: 392)
            ),
            appearance: appearance
        )
        defer { normalCard.tearDown() }
        XCTAssertEqual(normalCard.hosting.bounds.height, 80, accuracy: 1)

        let idleCard = try fittingFixture(
            AnyView(
                ShortcutCaptureCard(shortcut: shortcut, isCapturing: false, action: {})
                    .environment(\.dynamicTypeSize, .accessibility5)
                    .frame(width: 392)
            ),
            appearance: appearance
        )
        defer { idleCard.tearDown() }
        let captureCard = try fittingFixture(
            AnyView(
                ShortcutCaptureCard(shortcut: shortcut, isCapturing: true, action: {})
                    .environment(\.dynamicTypeSize, .accessibility5)
                    .frame(width: 392)
            ),
            appearance: appearance
        )
        defer { captureCard.tearDown() }
        XCTAssertGreaterThan(idleCard.hosting.bounds.height, 80)
        XCTAssertEqual(
            idleCard.hosting.bounds.height,
            captureCard.hosting.bounds.height,
            accuracy: 1
        )
        try assertRenderedContentIsContained(
            in: idleCard,
            required: ["停止录制快捷键", "点击重新录入"]
        )
        try assertRenderedContentIsContained(
            in: captureCard,
            required: ["停止录制快捷键", "请按下新的组合键"]
        )
        for card in [idleCard, captureCard] {
            XCTAssertGreaterThanOrEqual(
                separatorRunCount(in: try cachedBitmap(of: card.hosting)),
                5,
                "All five accessibility-size keycap boundaries must remain visible"
            )
        }
    }

    @MainActor
    private func renderButton(
        role: ClickerProminentButtonRole,
        title: String,
        appearance: NSAppearance,
        scheme: ColorScheme
    ) throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let size = CGSize(width: 120, height: 54)
        let hosting = NSHostingView(
            rootView: ClickerProminentButton(role: role, action: {}) {
                Text(title).frame(width: 64)
            }
            .environment(\.colorScheme, scheme)
            .frame(width: size.width, height: size.height)
            .background(Color(red: 0.1, green: 0.7, blue: 0.2))
        )
        hosting.appearance = appearance
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    private func pixelFraction(
        in bitmap: NSBitmapImageRep,
        region: CGRect,
        near target: NSColor,
        tolerance: CGFloat
    ) -> CGFloat {
        pixelFraction(in: bitmap, region: region) { color in
            guard let target = target.usingColorSpace(.sRGB) else { return false }
            return abs(color.redComponent - target.redComponent) <= tolerance
                && abs(color.greenComponent - target.greenComponent) <= tolerance
                && abs(color.blueComponent - target.blueComponent) <= tolerance
        }
    }

    @MainActor
    private func assertNoBlue(
        in fixture: HostedViewFixture,
        region: CGRect,
        name: String
    ) throws {
        let bitmap = try XCTUnwrap(
            fixture.hosting.bitmapImageRepForCachingDisplay(in: fixture.hosting.bounds)
        )
        fixture.hosting.cacheDisplay(in: fixture.hosting.bounds, to: bitmap)
        XCTAssertEqual(
            bluePixelCount(
                in: bitmap,
                logicalSize: fixture.hosting.bounds.size,
                region: region.insetBy(dx: -2, dy: -2)
            ),
            0,
            "\(name) must explicitly reject system blue"
        )
    }

    private func bluePixelCount(
        in bitmap: NSBitmapImageRep,
        logicalSize: CGSize,
        region: CGRect
    ) -> Int {
        let scaleX = CGFloat(bitmap.pixelsWide) / logicalSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / logicalSize.height
        let minX = max(0, Int((region.minX * scaleX).rounded(.down)))
        let maxX = min(bitmap.pixelsWide, Int((region.maxX * scaleX).rounded(.up)))
        let minY = max(0, Int((region.minY * scaleY).rounded(.down)))
        let maxY = min(bitmap.pixelsHigh, Int((region.maxY * scaleY).rounded(.up)))
        var count = 0
        for y in minY ..< maxY {
            for x in minX ..< maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                if isSystemBlue(color) {
                    count += 1
                }
            }
        }
        return count
    }

    private func isSystemBlue(_ color: NSColor) -> Bool {
        color.blueComponent > 0.7
            && color.blueComponent - color.redComponent > 0.25
            && color.blueComponent - color.greenComponent > 0.08
    }

    private func colorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        guard let lhs = lhs.usingColorSpace(.sRGB),
              let rhs = rhs.usingColorSpace(.sRGB) else { return .infinity }
        return max(
            abs(lhs.redComponent - rhs.redComponent),
            max(
                abs(lhs.greenComponent - rhs.greenComponent),
                abs(lhs.blueComponent - rhs.blueComponent)
            )
        )
    }

    @MainActor
    private func fittingFixture(
        _ rootView: AnyView,
        appearance: NSAppearance
    ) throws -> HostedViewFixture {
        let probe = NSHostingView(rootView: rootView)
        probe.appearance = appearance
        let size = probe.fittingSize
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
        return try HostedViewFixture(rootView: rootView, appearance: appearance, size: size)
    }

    @MainActor
    private func assertRenderedContentIsContained(
        in fixture: HostedViewFixture,
        required: [String]
    ) throws {
        let frames = try recognizedFrames(in: fixture)
        let normalizedCopy = frames.map(\.0).joined().replacingOccurrences(of: " ", with: "")
        for expected in required {
            XCTAssertTrue(
                normalizedCopy.contains(expected),
                "Missing \(expected) from \(frames.map(\.0))"
            )
        }
        for (text, frame) in frames {
            XCTAssertTrue(
                fixture.hosting.bounds.insetBy(dx: 1, dy: 1).contains(frame),
                "\(text) clipped outside \(fixture.hosting.bounds): \(frame)"
            )
        }
        for (index, first) in frames.enumerated() {
            for second in frames.dropFirst(index + 1) {
                let overlap = first.1.intersection(second.1)
                XCTAssertTrue(
                    overlap.isNull || overlap.width * overlap.height < 1,
                    "Rendered copy overlaps: \(first.0) \(first.1), \(second.0) \(second.1)"
                )
            }
        }
    }

    @MainActor
    private func recognizedFrames(
        in fixture: HostedViewFixture
    ) throws -> [(String, CGRect)] {
        let bitmap = try cachedBitmap(of: fixture.hosting)
        let image = try XCTUnwrap(bitmap.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        let size = fixture.hosting.bounds.size
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return (
                candidate.string,
                CGRect(
                    x: box.minX * size.width,
                    y: (1 - box.maxY) * size.height,
                    width: box.width * size.width,
                    height: box.height * size.height
                )
            )
        }
    }

    private func separatorRunCount(in bitmap: NSBitmapImageRep) -> Int {
        let target = rgb(0x74, 0x74, 0x7A)
        var maximum = 0
        for y in 0 ..< bitmap.pixelsHigh {
            var runs = 0
            var length = 0
            for x in 0 ..< bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                if colorDistance(color, target) <= 0.08 {
                    length += 1
                } else {
                    if length >= 4 { runs += 1 }
                    length = 0
                }
            }
            if length >= 4 { runs += 1 }
            maximum = max(maximum, runs)
        }
        return maximum
    }

    @MainActor
    private func hitTestViews(
        in hosting: NSHostingView<AnyView>,
        region: CGRect
    ) -> [NSView] {
        var views: [ObjectIdentifier: NSView] = [:]
        for y in stride(from: Int(region.minY), through: Int(region.maxY), by: 2) {
            for x in stride(from: Int(region.minX), through: Int(region.maxX), by: 2) {
                guard let view = hosting.hitTest(CGPoint(x: x, y: y)) else { continue }
                var current: NSView? = view
                while let candidate = current {
                    views[ObjectIdentifier(candidate)] = candidate
                    current = candidate.superview
                }
            }
        }
        return Array(views.values)
    }

    @MainActor
    private func cachedBitmap(of hosting: NSHostingView<AnyView>) throws -> NSBitmapImageRep {
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    private func differingPixelCount(
        _ lhs: NSBitmapImageRep,
        _ rhs: NSBitmapImageRep
    ) -> Int {
        guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh else {
            return .max
        }
        var count = 0
        for y in 0 ..< lhs.pixelsHigh {
            for x in 0 ..< lhs.pixelsWide {
                guard let first = lhs.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let second = rhs.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                if colorDistance(first, second) > 0.02 { count += 1 }
            }
        }
        return count
    }

    @MainActor
    private func renderInteractiveSurface(
        state: ClickerInteractiveSurfaceState,
        appearance: NSAppearance
    ) throws -> NSBitmapImageRep {
        let size = CGSize(width: 120, height: 54)
        let hosting = NSHostingView(
            rootView: RoundedRectangle(
                cornerRadius: ClickerVisualTheme.controlCornerRadius,
                style: .continuous
            )
            .fill(ClickerVisualTheme.cardSurface)
            .frame(width: 88, height: 38)
            .modifier(ClickerInteractiveSurfaceModifier(
                state: state,
                cornerRadius: ClickerVisualTheme.controlCornerRadius
            ))
            .frame(width: size.width, height: size.height)
            .background(Color(red: 0.1, green: 0.7, blue: 0.2))
        )
        hosting.appearance = appearance
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    @MainActor
    private func click(at point: CGPoint, in window: NSWindow) throws {
        for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: eventType,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: eventType == .leftMouseDown ? 1 : 0
            ))
            window.sendEvent(event)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    @MainActor
    private func renderedControlRegion(
        containing expected: String,
        in fixture: HostedViewFixture
    ) throws -> CGRect {
        let bitmap = try XCTUnwrap(
            fixture.hosting.bitmapImageRepForCachingDisplay(in: fixture.hosting.bounds)
        )
        fixture.hosting.cacheDisplay(in: fixture.hosting.bounds, to: bitmap)
        let image = try XCTUnwrap(bitmap.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        let size = fixture.hosting.bounds.size
        let frames = (request.results ?? []).compactMap { observation -> (String, CGRect)? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return (
                candidate.string.replacingOccurrences(of: " ", with: ""),
                CGRect(
                    x: box.minX * size.width,
                    y: (1 - box.maxY) * size.height,
                    width: box.width * size.width,
                    height: box.height * size.height
                )
            )
        }
        let label = try XCTUnwrap(
            frames.first { $0.0.contains(expected) }?.1,
            "Expected rendered control label \(expected), got \(frames.map(\.0))"
        )
        return label.insetBy(dx: -24, dy: -12)
    }

    @MainActor
    private func descendants(of root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private func pixelFraction(
        in bitmap: NSBitmapImageRep,
        region: CGRect,
        matching predicate: (NSColor) -> Bool
    ) -> CGFloat {
        let scaleX = CGFloat(bitmap.pixelsWide) / 120
        let scaleY = CGFloat(bitmap.pixelsHigh) / 54
        let minX = max(0, Int((region.minX * scaleX).rounded(.down)))
        let maxX = min(bitmap.pixelsWide, Int((region.maxX * scaleX).rounded(.up)))
        let minY = max(0, Int((region.minY * scaleY).rounded(.down)))
        let maxY = min(bitmap.pixelsHigh, Int((region.maxY * scaleY).rounded(.up)))
        guard minX < maxX, minY < maxY else { return 0 }
        var matches = 0
        var samples = 0
        for y in minY ..< maxY {
            for x in minX ..< maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                samples += 1
                if predicate(color) { matches += 1 }
            }
        }
        return samples == 0 ? 0 : CGFloat(matches) / CGFloat(samples)
    }

    private func isRed(_ color: NSColor) -> Bool {
        color.redComponent - color.greenComponent > 0.25
            && color.redComponent - color.blueComponent > 0.2
    }

    private func isBrightRed(_ color: NSColor) -> Bool {
        isRed(color) && color.redComponent > 0.75
    }

    private func rgb(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> NSColor {
        NSColor(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}

import AppKit
import ClickerCore
import SwiftUI
import Vision
import XCTest
@testable import Clicker

@MainActor
final class HostedScriptDetailFixture {
    let directory: URL
    let state: AppState
    let appearance: NSAppearance
    let hosting: NSHostingView<AnyView>
    let window: NSWindow

    init(
        script: Script,
        size: CGSize,
        phase: AppPhase = .idle,
        playbackScript: Script? = nil,
        appearanceName: NSAppearance.Name = .aqua,
        colorScheme: ColorScheme = .light
    ) throws {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        state = AppState(
            store: ScriptStore(directory: directory),
            application: VisualFixtureApplicationController(),
            playbackEngine: VisualFixturePlaybackEngine(),
            playbackIndicator: SilentPlaybackIndicator()
        )
        state.hasPermission = true
        state.scripts = [script]
        if let playbackScript, playbackScript.id != script.id {
            state.scripts.append(playbackScript)
        }
        state.selectedScriptID = script.id
        if case .playing = phase {
            // Establish the real session identity before freezing its visual progress.
            // The fixture engine never posts input or completes the session on its own.
            state.playScriptFromShortcut(id: playbackScript?.id ?? script.id)
        }
        state.phase = phase
        appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
        hosting = NSHostingView(
            rootView: AnyView(
                ScriptDetailView()
                    .environmentObject(state)
                    .environment(\.colorScheme, colorScheme)
                    .frame(width: size.width, height: size.height)
            )
        )
        hosting.appearance = appearance
        hosting.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        settle()
    }

    func settle() {
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
    }

    /// Pump native layout/scroll updates until the measured result is ready, rather
    /// than assuming every CI host completes an animated scroll within 50ms.
    func settle(until isReady: () -> Bool, timeout: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            if isReady() || Date() >= deadline { return }
            _ = RunLoop.current.run(
                mode: .default,
                before: min(deadline, Date().addingTimeInterval(0.01))
            )
        }
    }

    func tearDown() {
        if case .playing = state.phase { state.togglePlay() }
        window.orderOut(nil)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class VisualFixturePlaybackEngine: PlaybackControlling {
    func play(
        script: Script,
        onIteration: @escaping (Int) -> Void,
        onBlock: @escaping (UUID?) -> Void,
        onFinish: @escaping () -> Void
    ) {}

    func stop() {}
}

@MainActor
private final class VisualFixtureApplicationController: ApplicationControlling {
    func activateExternalApplication(bundleIdentifier: String) -> Bool { false }
    func hideClicker() {}
    func restoreClicker() {}
}

@MainActor
final class HostedViewFixture {
    let hosting: NSHostingView<AnyView>
    let window: NSWindow

    init(rootView: AnyView, appearance: NSAppearance, size: CGSize) throws {
        _ = NSApplication.shared
        hosting = NSHostingView(rootView: rootView)
        hosting.appearance = appearance
        hosting.frame = CGRect(origin: .zero, size: size)
        window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    func tearDown() {
        window.orderOut(nil)
    }
}

extension FinalVisualConsumerTests {
    @MainActor
    func assertAuxiliarySurfaceSystem() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let permissionState = AppState(store: ScriptStore(directory: directory))
        permissionState.hasPermission = false
        permissionState.hasAccessibilityPermission = false
        permissionState.hasInputMonitoringPermission = false
        let noSelectionState = AppState(store: ScriptStore(directory: directory))
        noSelectionState.hasPermission = true
        noSelectionState.scripts = [Script(name: "尚未选择的脚本")]
        noSelectionState.selectedScriptID = nil
        let emptyScriptState = AppState(store: ScriptStore(directory: directory))
        emptyScriptState.hasPermission = true
        let emptyScript = Script(name: "空动作", blocks: [])
        emptyScriptState.scripts = [emptyScript]
        emptyScriptState.selectedScriptID = emptyScript.id
        let surfaces: [(String, [String], (ColorScheme) -> AnyView)] = [
            ("permission", ["系统权限", "辅助功能", "输入监控", "重新检测"], { scheme in
                AnyView(PermissionGuideView().environmentObject(permissionState).environment(\.colorScheme, scheme))
            }),
            ("empty library", ["还没有脚本", "新建空白脚本", "开始录制"], { scheme in
                AnyView(ScriptSidebarView(scripts: [], selectedScriptID: .constant(nil), canEditScripts: true, canStartRecording: true, onRename: { _, _ in }, onDuplicate: { _ in }, onDelete: { _ in }, onRecord: {}).environment(\.colorScheme, scheme))
            }),
            ("no selection", ["选择一个脚本"], { scheme in
                AnyView(MainView().environmentObject(noSelectionState).environment(\.colorScheme, scheme))
            }),
            ("empty script", ["这个脚本还没有动作", "开始录制"], { scheme in
                AnyView(ScriptDetailView().environmentObject(emptyScriptState).environment(\.colorScheme, scheme))
            }),
            ("block editor", ["点击", "取消", "保存"], { scheme in
                AnyView(BlockEditorView(block: .click(ClickBlock(x: 80, y: 120, button: .left, clickCount: 1)), onSave: { _ in true }).environment(\.colorScheme, scheme))
            }),
        ]

        for appearanceFixture in [(NSAppearance.Name.aqua, ColorScheme.light), (.darkAqua, .dark)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceFixture.0))
            for surface in surfaces {
                let fixture = try HostedViewFixture(rootView: surface.2(appearanceFixture.1), appearance: appearance, size: CGSize(width: 480, height: 320))
                defer { fixture.tearDown() }
                let bitmap = try bitmap(for: fixture.hosting)
                let renderedCopy = try recognizedTextFrames(in: bitmap, logicalSize: fixture.hosting.bounds.size).map(\.text).joined().replacingOccurrences(of: " ", with: "")
                XCTAssertEqual(systemBluePixelCount(in: bitmap), 0, "\(surface.0) must not restore a system-blue action")
                XCTAssertEqual(legacyWarmPixelCount(in: bitmap), 0, "\(surface.0) must not restore the warm-yellow system")
                for label in surface.1 {
                    XCTAssertTrue(renderedCopy.contains(label), "\(surface.0) must visibly render \(label): \(renderedCopy)")
                }
            }
            try assertEmptyContentRegion(appearance: appearance, scheme: appearanceFixture.1)
            try assertEditorFormRegion(appearance: appearance, scheme: appearanceFixture.1)
        }
    }

    @MainActor
    private func assertEmptyContentRegion(appearance: NSAppearance, scheme: ColorScheme) throws {
        let size = CGSize(width: 480, height: 320)
        let window = ClickerVisualTheme.resolvedColor(for: .windowBackground, appearance: appearance)
        for kind in [
            ClickerEmptyStateKind.permissionRequired,
            .emptyLibrary,
            .noSelection,
            .emptyScript,
        ] {
            let fixture = try HostedViewFixture(
                rootView: AnyView(
                    ZStack {
                        ClickerVisualTheme.controlSurface
                        ClickerEmptyStateView(kind: kind, action: {}, secondaryAction: {})
                            .environment(\.colorScheme, scheme)
                    }
                    .frame(width: size.width, height: size.height)
                ),
                appearance: appearance,
                size: size
            )
            defer { fixture.tearDown() }
            let bitmap = try bitmap(for: fixture.hosting)
            let contentCorners = [
                CGRect(x: 12, y: 12, width: 32, height: 32),
                CGRect(x: size.width - 44, y: 12, width: 32, height: 32),
                CGRect(x: 12, y: size.height - 44, width: 32, height: 32),
                CGRect(x: size.width - 44, y: size.height - 44, width: 32, height: 32),
            ]
            for corner in contentCorners {
                XCTAssertGreaterThan(
                    renderedPixelFraction(in: bitmap, logicalSize: size, region: corner, near: window, tolerance: 0.04),
                    0.98,
                    "\(kind) must own the neutral background at its unobstructed content corners"
                )
            }
        }
    }

    @MainActor
    private func assertEditorFormRegion(appearance: NSAppearance, scheme: ColorScheme) throws {
        let size = CGSize(width: 380, height: 320)
        let fixture = try HostedViewFixture(rootView: AnyView(ZStack { ClickerVisualTheme.controlSurface; BlockEditorView(block: .click(ClickBlock(x: 80, y: 120, button: .left, clickCount: 1)), onSave: { _ in true }).environment(\.colorScheme, scheme) }.frame(width: size.width, height: size.height)), appearance: appearance, size: size)
        defer { fixture.tearDown() }
        let form = try XCTUnwrap(descendants(of: fixture.hosting).compactMap { $0 as? NSScrollView }.first)
        let bitmap = try bitmap(for: fixture.hosting)
        // Overlay scrollers can cover the clip view's edge as well as the scroll
        // view's edge. Keep the native controls visible and account for their
        // exact rendered footprint rather than treating no samples as black.
        let formBounds = fixture.hosting.convert(form.contentView.bounds, from: form.contentView)
        let controls = descendants(of: form)
            .compactMap { $0 as? NSControl }
            .filter { !$0.isHiddenOrHasHiddenAncestor && $0.alphaValue > 0 && !$0.visibleRect.isEmpty }
        let subcontrolBounds = controls
            .map { fixture.hosting.convert($0.bounds, from: $0).insetBy(dx: -2, dy: -2) }
        let scrollerBounds = controls.compactMap { $0 as? NSScroller }
            .map { fixture.hosting.convert($0.visibleRect, from: $0) }
        let formEdges = [
            CGRect(x: formBounds.minX + 2, y: formBounds.minY + 2, width: formBounds.width - 4, height: 4),
            CGRect(x: formBounds.minX + 2, y: formBounds.maxY - 6, width: formBounds.width - 4, height: 4),
            CGRect(x: formBounds.minX + 2, y: formBounds.minY + 6, width: 4, height: formBounds.height - 12),
            CGRect(x: formBounds.maxX - 6, y: formBounds.minY + 6, width: 4, height: formBounds.height - 12),
        ]
        XCTAssertFalse(form.drawsBackground, "The real editor scroll content must remain transparent")
        XCTAssertFalse(form.contentView.drawsBackground, "The real editor clip view must remain transparent")
        let window = ClickerVisualTheme.resolvedColor(for: .windowBackground, appearance: appearance)
        let mode = scheme == .dark ? "dark" : "light"
        var diagnostics = [
            "Editor form \(mode): scroll=\(fixture.hosting.convert(form.bounds, from: form)) clip=\(formBounds) scrollerStyle=\(form.scrollerStyle.rawValue)",
            "document=\(form.documentView.map { fixture.hosting.convert($0.bounds, from: $0).description } ?? "nil") scrollers=\(scrollerBounds)",
        ]
        diagnostics += controls.map {
            "control=\(type(of: $0)) bounds=\(fixture.hosting.convert($0.bounds, from: $0)) visible=\(fixture.hosting.convert($0.visibleRect, from: $0))"
        }
        let scaleX = CGFloat(bitmap.pixelsWide) / size.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / size.height
        var measuredEdges = 0
        var fullyScrollerCoveredEdges = 0
        for (index, edge) in formEdges.enumerated() {
            let minX = max(0, Int((edge.minX * scaleX).rounded(.down)))
            let maxX = min(bitmap.pixelsWide, Int((edge.maxX * scaleX).rounded(.up)))
            let minY = max(0, Int((edge.minY * scaleY).rounded(.down)))
            let maxY = min(bitmap.pixelsHigh, Int((edge.maxY * scaleY).rounded(.up)))
            var total = 0
            var sampled = 0
            var scrollerCovered = 0
            if minX < maxX, minY < maxY {
                for y in minY ..< maxY {
                    for x in minX ..< maxX {
                        let point = CGPoint(x: CGFloat(x) / scaleX, y: CGFloat(y) / scaleY)
                        total += 1
                        if !subcontrolBounds.contains(where: { $0.contains(point) }) { sampled += 1 }
                        if scrollerBounds.contains(where: { $0.contains(point) }) { scrollerCovered += 1 }
                    }
                }
            }
            let fraction = renderedPixelFraction(in: bitmap, logicalSize: size, region: edge,
                near: window, tolerance: 0.04, excluding: subcontrolBounds)
            diagnostics.append("edge[\(index)]=\(edge) total=\(total) sampled=\(sampled) excluded=\(total - sampled) nativeScroller=\(scrollerCovered) matching=\(fraction)")
            XCTAssertGreaterThan(total, 0, "Every requested margin must lie inside the bitmap")
            if sampled == 0, total > 0, scrollerCovered == total {
                // There are no background pixels under this actual native
                // control. Do not move the sample into the grouped surface.
                // The other three original margins must still be measured.
                fullyScrollerCoveredEdges += 1
                continue
            }
            XCTAssertGreaterThan(sampled, 0, "An empty color sample is allowed only when every pixel belongs to a visible NSScroller: \(edge)")
            measuredEdges += 1
            XCTAssertGreaterThan(
                fraction,
                0.85,
                "Editor form edge outside real subcontrols must use windowBackground: \(edge)"
            )
        }
        XCTAssertGreaterThanOrEqual(measuredEdges, 3, "Native scrollbars cannot exempt most of the form's background margins")
        XCTAssertEqual(measuredEdges + fullyScrollerCoveredEdges, formEdges.count)
        let report = diagnostics.joined(separator: "\n")
        print(report)
        if let destination = ProcessInfo.processInfo.environment["CLICKER_SNAPSHOT_DIR"] {
            let directory = URL(fileURLWithPath: destination, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("\(mode)-editor-form-380x320.png"))
            try report.write(to: directory.appendingPathComponent("\(mode)-editor-form-diagnostics.txt"), atomically: true, encoding: .utf8)
        }
    }

    @MainActor
    func assertPermissionActionHierarchy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(store: ScriptStore(directory: directory))
        state.hasPermission = false
        state.hasAccessibilityPermission = false
        state.hasInputMonitoringPermission = false
        let size = CGSize(width: 480, height: 320)

        for fixture in [(NSAppearance.Name.aqua, ColorScheme.light), (.darkAqua, .dark)] {
            let appearance = try XCTUnwrap(NSAppearance(named: fixture.0))
            var accessibilityRequests = 0
            var inputMonitoringRequests = 0
            let hosted = try HostedViewFixture(
                rootView: AnyView(PermissionChecklistView(
                    onRequestAccessibility: { accessibilityRequests += 1 },
                    onRequestInputMonitoring: { inputMonitoringRequests += 1 }
                ).environmentObject(state).environment(\.colorScheme, fixture.1)),
                appearance: appearance,
                size: size
            )
            defer { hosted.tearDown() }
            let bitmap = try bitmap(for: hosted.hosting)
            let text = try recognizedTextFrames(in: bitmap, logicalSize: size)
            let secondary = try XCTUnwrap(text.first { $0.text.contains("重新检测") }).frame
            let fill = ClickerVisualTheme.resolvedColor(for: .playbackFill, appearance: appearance)
            let buttons = (nativeControls(in: hosted.hosting) + descendants(of: hosted.hosting))
                .compactMap { $0 as? NSButton }
            var seenButtons = Set<ObjectIdentifier>()
            let grantButtons = buttons.filter { button in
                seenButtons.insert(ObjectIdentifier(button)).inserted
                    && (normalizedVisualText(button.title).contains("授予权限")
                        || nativeButton(recognizing: "授予权限", among: [button], recognizedText: text, in: hosted.hosting) != nil)
            }
            let controlInventory = buttons.map {
                "\(type(of: $0)) title=\($0.title) label=\($0.accessibilityLabel() ?? "nil") frame=\(hosted.hosting.convert($0.bounds, from: $0))"
            }.joined(separator: "\n")
            XCTAssertEqual(grantButtons.count, 2, "Two distinct native grant buttons are required. Controls: \(controlInventory); OCR: \(text)")
            var matchedGrants = Set<ObjectIdentifier>()
            for permission in ["辅助功能", "输入监控"] {
                let title = try XCTUnwrap(text.first { normalizedVisualText($0.text).hasPrefix(permission) }?.frame,
                                         "Missing visible permission title \(permission): \(text)")
                let grantButton = try XCTUnwrap(grantButtons.first { button in
                    let frame = hosted.hosting.convert(button.bounds, from: button)
                    return frame.midX > hosted.hosting.bounds.midX && frame.minY < title.maxY && frame.maxY > title.minY
                }, "Each visible permission row must have its own native grant button. Controls: \(controlInventory); OCR: \(text)")
                XCTAssertTrue(matchedGrants.insert(ObjectIdentifier(grantButton)).inserted,
                              "One grant button cannot represent both permission rows")
                XCTAssertTrue(grantButton.isBordered)
                XCTAssertTrue(grantButton.isEnabled)
                let frame = hosted.hosting.convert(grantButton.bounds, from: grantButton)
                XCTAssertTrue(hosted.hosting.bounds.contains(frame))
                XCTAssertLessThan(
                    renderedPixelFraction(in: bitmap, logicalSize: size, region: frame,
                                          near: fill, tolerance: 0.04),
                    0.2,
                    "Granular permission actions must remain low-emphasis, not playback-style primary fills"
                )
                grantButton.performClick(nil)
                XCTAssertEqual(accessibilityRequests, 1, "Only the Accessibility row may request Accessibility")
                XCTAssertEqual(inputMonitoringRequests, permission == "输入监控" ? 1 : 0,
                               "Only the Input Monitoring row may request Input Monitoring")
            }
            let secondaryButton = try XCTUnwrap(
                nativeButton(
                    recognizing: "重新检测",
                    among: buttons,
                    recognizedText: text,
                    in: hosted.hosting
                ),
                "The permission secondary action must remain a native bordered button"
            )
            let secondaryFrame = hosted.hosting.convert(
                secondaryButton.bounds,
                from: secondaryButton
            )
            let secondaryPaddingInView = CGRect(
                x: secondaryFrame.minX + 6,
                y: secondary.minY + 2,
                width: 6,
                height: secondary.height - 4
            )
            let secondaryPadding = CGRect(
                x: secondaryPaddingInView.minX,
                y: size.height - secondaryPaddingInView.maxY,
                width: secondaryPaddingInView.width,
                height: secondaryPaddingInView.height
            )
            XCTAssertLessThan(
                renderedPixelFraction(
                    in: bitmap,
                    logicalSize: size,
                    region: secondaryPadding,
                    near: fill,
                    tolerance: 0.04
                ),
                0.1,
                "The permission secondary action must remain bordered and low-emphasis"
            )
        }
    }

    @MainActor
    func renderBitmap<V: View>(
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
        return try retinaBitmap(for: hosting)
    }

    @MainActor
    func bitmap(for hosting: NSHostingView<some View>) throws -> NSBitmapImageRep {
        try retinaBitmap(for: hosting)
    }

    func recognizedTextFrames(
        in bitmap: NSBitmapImageRep,
        logicalSize: CGSize
    ) throws -> [(text: String, frame: CGRect)] {
        let image = try XCTUnwrap(bitmap.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return (
                text: candidate.string,
                frame: CGRect(
                    x: box.minX * logicalSize.width,
                    y: (1 - box.maxY) * logicalSize.height,
                    width: box.width * logicalSize.width,
                    height: box.height * logicalSize.height
                )
            )
        }
    }

    @MainActor
    func nativeControls<V: View>(in hosting: NSHostingView<V>) -> [NSView] {
        var controls: [ObjectIdentifier: NSView] = [:]
        for y in stride(from: 0, through: Int(hosting.bounds.height), by: 4) {
            for x in stride(from: 0, through: Int(hosting.bounds.width), by: 4) {
                guard let view = hosting.hitTest(CGPoint(x: x, y: y)) else { continue }
                controls[ObjectIdentifier(view)] = view
            }
        }
        return Array(controls.values)
    }

    @MainActor
    func descendants(of root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    func controlLabel(_ view: NSView) -> String? {
        if let label = view.accessibilityLabel(), !label.isEmpty { return label }
        if let field = view as? NSTextField { return field.placeholderString }
        if let button = view as? NSButton, !button.title.isEmpty { return button.title }
        return nil
    }

    func nativeButton<V: View>(
        recognizing expectedText: String,
        among buttons: [NSButton],
        recognizedText: [(text: String, frame: CGRect)],
        in hosting: NSHostingView<V>
    ) -> NSButton? {
        buttons.first { button in
            let buttonFrame = hosting.convert(button.bounds, from: button)
            return recognizedText.contains { match in
                match.text.replacingOccurrences(of: " ", with: "").contains(expectedText)
                    && buttonFrame.contains(match.frame)
            }
        }
    }

    func color(
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

    func color(in bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
        try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    }

    func visibleColorBounds(
        in bitmap: NSBitmapImageRep,
        near target: NSColor,
        tolerance: CGFloat,
        within region: CGRect,
        logicalSize: CGSize
    ) -> CGRect? {
        guard let target = target.usingColorSpace(.sRGB) else { return nil }
        let scaleX = CGFloat(bitmap.pixelsWide) / logicalSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / logicalSize.height
        let minX = max(0, Int((region.minX * scaleX).rounded(.down)))
        let maxX = min(bitmap.pixelsWide, Int((region.maxX * scaleX).rounded(.up)))
        let minY = max(0, Int((region.minY * scaleY).rounded(.down)))
        let maxY = min(bitmap.pixelsHigh, Int((region.maxY * scaleY).rounded(.up)))
        var matchedMinX = bitmap.pixelsWide
        var matchedMaxX = -1
        var matchedMinY = bitmap.pixelsHigh
        var matchedMaxY = -1

        for y in minY ..< maxY {
            for x in minX ..< maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                if abs(color.redComponent - target.redComponent) <= tolerance,
                   abs(color.greenComponent - target.greenComponent) <= tolerance,
                   abs(color.blueComponent - target.blueComponent) <= tolerance {
                    matchedMinX = min(matchedMinX, x)
                    matchedMaxX = max(matchedMaxX, x)
                    matchedMinY = min(matchedMinY, y)
                    matchedMaxY = max(matchedMaxY, y)
                }
            }
        }
        guard matchedMaxX >= matchedMinX, matchedMaxY >= matchedMinY else { return nil }
        return CGRect(
            x: CGFloat(matchedMinX) / scaleX,
            y: CGFloat(matchedMinY) / scaleY,
            width: CGFloat(matchedMaxX - matchedMinX + 1) / scaleX,
            height: CGFloat(matchedMaxY - matchedMinY + 1) / scaleY
        )
    }

    func visibleRecordCueBounds(
        in bitmap: NSBitmapImageRep,
        within region: CGRect,
        logicalSize: CGSize
    ) -> CGRect? {
        let scaleX = CGFloat(bitmap.pixelsWide) / logicalSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / logicalSize.height
        let minX = max(0, Int((region.minX * scaleX).rounded(.down)))
        let maxX = min(bitmap.pixelsWide, Int((region.maxX * scaleX).rounded(.up)))
        let minY = max(0, Int((region.minY * scaleY).rounded(.down)))
        let maxY = min(bitmap.pixelsHigh, Int((region.maxY * scaleY).rounded(.up)))
        var matchedMinX = bitmap.pixelsWide
        var matchedMaxX = -1
        var matchedMinY = bitmap.pixelsHigh
        var matchedMaxY = -1

        for y in minY ..< maxY {
            for x in minX ..< maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.redComponent - color.greenComponent > 0.08,
                      color.redComponent - color.blueComponent > 0.08 else {
                    continue
                }
                matchedMinX = min(matchedMinX, x)
                matchedMaxX = max(matchedMaxX, x)
                matchedMinY = min(matchedMinY, y)
                matchedMaxY = max(matchedMaxY, y)
            }
        }
        guard matchedMaxX >= matchedMinX, matchedMaxY >= matchedMinY else { return nil }
        return CGRect(
            x: CGFloat(matchedMinX) / scaleX,
            y: CGFloat(matchedMinY) / scaleY,
            width: CGFloat(matchedMaxX - matchedMinX + 1) / scaleX,
            height: CGFloat(matchedMaxY - matchedMinY + 1) / scaleY
        )
    }

    func renderedPixelFraction(
        in bitmap: NSBitmapImageRep,
        logicalSize: CGSize,
        region: CGRect,
        near target: NSColor,
        tolerance: CGFloat,
        excluding excludedRegions: [CGRect] = []
    ) -> CGFloat {
        guard let target = target.usingColorSpace(.sRGB) else { return 0 }
        let scaleX = CGFloat(bitmap.pixelsWide) / logicalSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / logicalSize.height
        let minX = max(0, Int((region.minX * scaleX).rounded(.down)))
        let maxX = min(bitmap.pixelsWide, Int((region.maxX * scaleX).rounded(.up)))
        let minY = max(0, Int((region.minY * scaleY).rounded(.down)))
        let maxY = min(bitmap.pixelsHigh, Int((region.maxY * scaleY).rounded(.up)))
        guard minX < maxX, minY < maxY else { return 0 }
        var matches = 0
        var sampled = 0
        for y in minY ..< maxY {
            for x in minX ..< maxX {
                let logicalPoint = CGPoint(x: CGFloat(x) / scaleX, y: CGFloat(y) / scaleY)
                guard !excludedRegions.contains(where: { $0.contains(logicalPoint) }) else { continue }
                sampled += 1
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
        return sampled == 0 ? 0 : CGFloat(matches) / CGFloat(sampled)
    }

    func renderedColorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
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

    func systemBluePixelCount(in bitmap: NSBitmapImageRep) -> Int {
        (0 ..< bitmap.pixelsHigh).reduce(0) { count, y in
            count + (0 ..< bitmap.pixelsWide).reduce(0) { rowCount, x in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return rowCount }
                return rowCount + (color.blueComponent > 0.7
                    && color.blueComponent - color.redComponent > 0.25
                    && color.blueComponent - color.greenComponent > 0.08 ? 1 : 0)
            }
        }
    }

    func legacyWarmPixelCount(in bitmap: NSBitmapImageRep) -> Int {
        (0 ..< bitmap.pixelsHigh).reduce(0) { count, y in
            count + (0 ..< bitmap.pixelsWide).reduce(0) { rowCount, x in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return rowCount }
                return rowCount + (abs(color.redComponent - 0xF1 / 255) <= 0.02
                    && abs(color.greenComponent - 0xEA / 255) <= 0.02
                    && abs(color.blueComponent - 0xDC / 255) <= 0.02 ? 1 : 0)
            }
        }
    }


    func visibleRoleBounds(
        in bitmap: NSBitmapImageRep,
        logicalSize: CGSize,
        within region: CGRect,
        target: NSColor,
        excluding background: NSColor
    ) -> CGRect? {
        guard let target = target.usingColorSpace(.sRGB),
              let background = background.usingColorSpace(.sRGB) else { return nil }
        let scaleX = CGFloat(bitmap.pixelsWide) / logicalSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / logicalSize.height
        let minX = max(0, Int((region.minX * scaleX).rounded(.down)))
        let maxX = min(bitmap.pixelsWide, Int((region.maxX * scaleX).rounded(.up)))
        let minY = max(0, Int((region.minY * scaleY).rounded(.down)))
        let maxY = min(bitmap.pixelsHigh, Int((region.maxY * scaleY).rounded(.up)))
        var bounds: (minX: Int, maxX: Int, minY: Int, maxY: Int)?

        for y in minY ..< maxY {
            for x in minX ..< maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                let targetDistance = max(
                    abs(color.redComponent - target.redComponent),
                    max(
                        abs(color.greenComponent - target.greenComponent),
                        abs(color.blueComponent - target.blueComponent)
                    )
                )
                let backgroundDistance = max(
                    abs(color.redComponent - background.redComponent),
                    max(
                        abs(color.greenComponent - background.greenComponent),
                        abs(color.blueComponent - background.blueComponent)
                    )
                )
                guard targetDistance < backgroundDistance, targetDistance <= 0.08 else { continue }
                if let current = bounds {
                    bounds = (
                        min(current.minX, x), max(current.maxX, x),
                        min(current.minY, y), max(current.maxY, y)
                    )
                } else {
                    bounds = (x, x, y, y)
                }
            }
        }
        guard let bounds else { return nil }
        return CGRect(
            x: CGFloat(bounds.minX) / scaleX,
            y: CGFloat(bounds.minY) / scaleY,
            width: CGFloat(bounds.maxX - bounds.minX + 1) / scaleX,
            height: CGFloat(bounds.maxY - bounds.minY + 1) / scaleY
        )
    }

    func contrastRatio(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
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

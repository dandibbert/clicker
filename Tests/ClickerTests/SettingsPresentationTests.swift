import AppKit
import ClickerCore
import SwiftUI
import Vision
import XCTest
@testable import Clicker

final class SettingsPresentationTests: XCTestCase {
    func testRecordingSettingsOffersAllThreeAppearanceChoices() {
        XCTAssertEqual(
            AppAppearancePreference.allCases.map(\.title),
            ["跟随系统", "浅色", "深色"]
        )
    }

    @MainActor
    func testSettingsRendersLivePreferenceSectionsWithoutDoneFooter() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(store: ScriptStore(directory: directory))
        let (hosting, window) = hostSettings(state)
        defer { window.orderOut(nil) }

        let rendered = try recognizedTextFrames(
            in: bitmap(for: hosting),
            logicalSize: hosting.bounds.size
        )
        let copy = rendered.map(\.text).joined()
        for expected in ["通用", "外观", "录制", "停止录制快捷键", "恢复默认设置"] {
            XCTAssertTrue(copy.contains(expected), "Missing \(expected) in \(copy)")
        }
        XCTAssertFalse(copy.contains("完成"), "Live settings must not render a Done footer: \(copy)")

        let segmented = try XCTUnwrap(
            descendants(of: hosting).compactMap { $0 as? NSSegmentedControl }.first
        )
        XCTAssertEqual(segmented.segmentCount, 3)
        XCTAssertEqual((0 ..< 3).map { segmented.label(forSegment: $0) }, [
            "跟随系统", "浅色", "深色",
        ])
        XCTAssertTrue(segmented.isEnabled)
        XCTAssertTrue((0 ..< 3).allSatisfy { segmented.isEnabled(forSegment: $0) })
    }

    @MainActor
    func testCompactShortcutCardKeepsFullCardHitTargetAndStableFrame() throws {
        _ = NSApplication.shared
        let shortcut = RecordingStopShortcut(
            keyCode: 14,
            modifierFlags: KeyCodeMap.maskControl
                | KeyCodeMap.maskOption
                | KeyCodeMap.maskShift
                | KeyCodeMap.maskCommand
        )
        let idle = try hostShortcutCard(shortcut: shortcut, isCapturing: false)
        defer { idle.window.orderOut(nil) }
        let capturing = try hostShortcutCard(shortcut: shortcut, isCapturing: true)
        defer { capturing.window.orderOut(nil) }

        XCTAssertTrue((72 ... 84).contains(idle.cardFrame.height), "Idle card: \(idle.cardFrame)")
        XCTAssertTrue((72 ... 84).contains(capturing.cardFrame.height), "Capture card: \(capturing.cardFrame)")
        XCTAssertEqual(idle.cardFrame.height, capturing.cardFrame.height, accuracy: 1)
        XCTAssertEqual(idle.cardFrame.width, 392, accuracy: 1)
        XCTAssertEqual(capturing.cardFrame.width, 392, accuracy: 1)

        for fixture in [idle, capturing] {
            let cardBitmap = try bitmap(for: fixture.hosting)
            let separator = ClickerVisualTheme.resolvedColor(
                for: .separator,
                appearance: try XCTUnwrap(NSAppearance(named: .aqua))
            )
            let keycapRegionMaxX = Int(
                230 * CGFloat(cardBitmap.pixelsWide) / fixture.hosting.bounds.width
            )
            XCTAssertGreaterThanOrEqual(
                maximumHorizontalRuns(
                    in: cardBitmap,
                    near: separator,
                    xRange: 0 ..< min(keycapRegionMaxX, cardBitmap.pixelsWide),
                    minimumRunLength: 4
                ),
                5,
                "All five rendered keycap boundaries must remain visible"
            )
        }
        let idleCopy = try recognizedTextFrames(
            in: bitmap(for: idle.hosting),
            logicalSize: idle.hosting.bounds.size
        ).map(\.text).joined()
        let captureCopy = try recognizedTextFrames(
            in: bitmap(for: capturing.hosting),
            logicalSize: capturing.hosting.bounds.size
        ).map(\.text).joined()
        XCTAssertTrue(idleCopy.contains("点击重新录入"), idleCopy)
        XCTAssertTrue(captureCopy.contains("请按下新的组合键"), captureCopy)
    }

    @MainActor
    func testCaptureModeKeepsSettingsContentFramesStable() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(store: ScriptStore(directory: directory))
        let size = CGSize(width: 440, height: 360)
        let hosting = NSHostingView(
            rootView: RecordingSettingsView()
                .environmentObject(state)
                .environment(\.colorScheme, .light)
        )
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = CGRect(origin: .zero, size: size)
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

        let before = try recognizedTextFrames(in: bitmap(for: hosting), logicalSize: size)
        let appearanceBefore = try frame(containing: "外观", in: before)
        let captureBefore = try frame(containing: "停止录制快捷键", in: before)
        let messageBefore = try frame(containing: "录制时可在任意应用中按此快捷键停止", in: before)
        try click(
            CGPoint(x: captureBefore.midX, y: size.height - captureBefore.midY),
            in: window
        )
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        try sendKeyDown(keyCode: 15, modifiers: [.option, .command], to: window)

        let after = try recognizedTextFrames(in: bitmap(for: hosting), logicalSize: size)
        let appearanceAfter = try frame(containing: "外观", in: after)
        let captureAfter = try frame(containing: "停止录制快捷键", in: after)
        let messageAfter = try frame(containing: "与全局快捷键", in: after)

        XCTAssertEqual(appearanceAfter.minY, appearanceBefore.minY, accuracy: 1)
        XCTAssertEqual(captureAfter.minY, captureBefore.minY, accuracy: 1)
        XCTAssertGreaterThan(messageAfter.minY, captureAfter.maxY)
        XCTAssertGreaterThan(messageBefore.minY, captureBefore.maxY)
    }

    @MainActor
    func testSettingsCaptureUsesLocalFirstResponderAndUpdatesInjectedShortcutStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let shortcutStore = SettingsShortcutStoreStub(shortcut: .defaultValue)
        let state = AppState(
            store: ScriptStore(directory: directory),
            stopShortcutStore: shortcutStore
        )
        let (hosting, window) = hostSettings(state)
        defer { window.orderOut(nil) }

        try clickCaptureCard(in: hosting, window: window)
        XCTAssertTrue(window.firstResponder is CaptureKeyView)

        let valid = RecordingStopShortcut(
            keyCode: 1,
            modifierFlags: KeyCodeMap.maskControl
        )
        try sendKeyDown(keyCode: valid.keyCode, modifiers: [.control], to: window)
        XCTAssertEqual(shortcutStore.shortcut, valid)
        XCTAssertEqual(state.recordingStopShortcut, valid)

        try clickCaptureCard(in: hosting, window: window)
        XCTAssertTrue(window.firstResponder is CaptureKeyView)
        try sendKeyDown(keyCode: 15, modifiers: [.option, .command], to: window)
        XCTAssertEqual(shortcutStore.shortcut, valid)
        XCTAssertEqual(state.recordingStopShortcut, valid)
    }

    @MainActor
    func testAppearanceSegmentsImmediatelyUpdateStateAndInjectedStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let appearanceStore = SettingsAppearanceStoreStub(preference: .system)
        let state = AppState(
            store: ScriptStore(directory: directory),
            appearancePreferenceStore: appearanceStore
        )
        let (hosting, window) = hostSettings(state)
        defer { window.orderOut(nil) }
        let segmented = try XCTUnwrap(
            descendants(of: hosting).compactMap { $0 as? NSSegmentedControl }.first
        )

        XCTAssertEqual(segmented.segmentCount, 3)
        XCTAssertEqual((0 ..< 3).map { segmented.label(forSegment: $0) }, [
            "跟随系统", "浅色", "深色",
        ])
        try selectSegment(1, in: segmented)
        XCTAssertEqual(state.appearancePreference, .light)
        XCTAssertEqual(appearanceStore.preference, .light)

        try selectSegment(2, in: segmented)
        XCTAssertEqual(state.appearancePreference, .dark)
        XCTAssertEqual(appearanceStore.preference, .dark)
    }

    @MainActor
    func testNonIdleSettingsRemainPresentedWithEditingDisabled() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(store: ScriptStore(directory: directory))
        let (hosting, window) = hostSettings(state)
        defer { window.orderOut(nil) }

        let copy = try recognizedTextFrames(
            in: bitmap(for: hosting),
            logicalSize: hosting.bounds.size
        ).map(\.text).joined()
        XCTAssertTrue(copy.contains("外观"), copy)
        XCTAssertTrue(copy.contains("停止录制快捷键"), copy)
        let segmented = try XCTUnwrap(
            descendants(of: hosting).compactMap { $0 as? NSSegmentedControl }.first
        )
        try clickCaptureCard(in: hosting, window: window)
        XCTAssertTrue(window.firstResponder is CaptureKeyView)

        state.phase = .recording
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        XCTAssertFalse(segmented.isEnabled)
        XCTAssertFalse(window.firstResponder is CaptureKeyView)
    }

    @MainActor
    private func hostSettings(
        _ state: AppState
    ) -> (hosting: NSHostingView<AnyView>, window: NSWindow) {
        _ = NSApplication.shared
        let size = CGSize(width: 440, height: 360)
        let hosting = NSHostingView(
            rootView: AnyView(
                RecordingSettingsView()
                    .environmentObject(state)
                    .environment(\.colorScheme, .light)
            )
        )
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        return (hosting, window)
    }

    @MainActor
    private func hostShortcutCard(
        shortcut: RecordingStopShortcut,
        isCapturing: Bool
    ) throws -> (hosting: NSHostingView<AnyView>, window: NSWindow, cardFrame: CGRect) {
        let hosting = NSHostingView(
            rootView: AnyView(
                ShortcutCaptureCard(
                    shortcut: shortcut,
                    isCapturing: isCapturing,
                    action: {}
                )
                .frame(width: 392)
                .environment(\.colorScheme, .light)
            )
        )
        hosting.appearance = NSAppearance(named: .aqua)
        let size = hosting.fittingSize
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        return (hosting, window, hosting.bounds)
    }

    @MainActor
    private func clickCaptureCard(
        in hosting: NSHostingView<AnyView>,
        window: NSWindow
    ) throws {
        let size = hosting.bounds.size
        let matches = try recognizedTextFrames(in: bitmap(for: hosting), logicalSize: size)
        let capture = try frame(containing: "停止录制快捷键", in: matches)
        try click(CGPoint(x: capture.midX, y: size.height - capture.midY), in: window)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
    }

    @MainActor
    private func sendKeyDown(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        to window: NSWindow
    ) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        ))
        window.sendEvent(event)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    @MainActor
    private func selectSegment(
        _ index: Int,
        in segmented: NSSegmentedControl
    ) throws {
        let action = try XCTUnwrap(segmented.action)
        segmented.selectedSegment = index
        XCTAssertTrue(segmented.sendAction(action, to: segmented.target))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    @MainActor
    private func descendants(of root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor
    private func bitmap(for hosting: NSHostingView<some View>) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    private func recognizedTextFrames(
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
                text: candidate.string.replacingOccurrences(of: " ", with: ""),
                frame: CGRect(
                    x: box.minX * logicalSize.width,
                    y: (1 - box.maxY) * logicalSize.height,
                    width: box.width * logicalSize.width,
                    height: box.height * logicalSize.height
                )
            )
        }
    }

    private func maximumHorizontalRuns(
        in bitmap: NSBitmapImageRep,
        near target: NSColor,
        xRange: Range<Int>,
        minimumRunLength: Int
    ) -> Int {
        guard let target = target.usingColorSpace(.sRGB) else { return 0 }
        var maximum = 0
        for y in 0 ..< bitmap.pixelsHigh {
            var runs = 0
            var length = 0
            for x in xRange {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                let matches = abs(color.redComponent - target.redComponent) <= 0.08
                    && abs(color.greenComponent - target.greenComponent) <= 0.08
                    && abs(color.blueComponent - target.blueComponent) <= 0.08
                if matches {
                    length += 1
                } else {
                    if length >= minimumRunLength { runs += 1 }
                    length = 0
                }
            }
            if length >= minimumRunLength { runs += 1 }
            maximum = max(maximum, runs)
        }
        return maximum
    }

    private func frame(
        containing expected: String,
        in matches: [(text: String, frame: CGRect)]
    ) throws -> CGRect {
        try XCTUnwrap(
            matches.first { $0.text.contains(expected) }?.frame,
            "Expected rendered text \(expected), got \(matches.map(\.text))"
        )
    }

    @MainActor
    private func click(_ point: CGPoint, in window: NSWindow) throws {
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
}

private final class SettingsShortcutStoreStub: RecordingStopShortcutProviding {
    var shortcut: RecordingStopShortcut

    init(shortcut: RecordingStopShortcut) {
        self.shortcut = shortcut
    }
}

private final class SettingsAppearanceStoreStub: AppAppearancePreferenceProviding {
    var preference: AppAppearancePreference

    init(preference: AppAppearancePreference) {
        self.preference = preference
    }
}

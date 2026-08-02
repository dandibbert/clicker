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
    func testRecordingSettingsUsesAppearancePickerAndSingleShortcutCaptureCard() {
        let body = String(reflecting: RecordingSettingsView.Body.self)

        XCTAssertTrue(body.contains("Picker"), body)
        XCTAssertTrue(body.contains("ShortcutCaptureCard"), body)
        XCTAssertTrue(body.contains("ScrollView"), body)
        XCTAssertTrue(body.contains("_InsetViewModifier"), body)
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
        let captureBefore = try frame(containing: "停止录制快捷键", in: before)
        let messageBefore = try frame(containing: "录制时可在任意应用中按此快捷键停止", in: before)
        try click(
            CGPoint(x: captureBefore.midX, y: size.height - captureBefore.midY),
            in: window
        )
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        let after = try recognizedTextFrames(in: bitmap(for: hosting), logicalSize: size)
        let captureAfter = try frame(containing: "停止录制快捷键", in: after)
        let messageAfter = try frame(containing: "录制时可在任意应用中按此快捷键停止", in: after)

        XCTAssertEqual(captureAfter.minY, captureBefore.minY, accuracy: 1)
        XCTAssertEqual(messageAfter.minY, messageBefore.minY, accuracy: 1)
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

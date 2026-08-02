import AppKit
import SwiftUI
import XCTest
@testable import Clicker
import ClickerCore

final class ShortcutCaptureTests: XCTestCase {
    func testShortcutPresentationUsesSeparateOrderedKeycaps() {
        let shortcut = RecordingStopShortcut(
            keyCode: 14,
            modifierFlags: KeyCodeMap.maskControl
                | KeyCodeMap.maskOption
                | KeyCodeMap.maskShift
                | KeyCodeMap.maskCommand
        )

        let model = ShortcutKeycapPresentation(shortcut: shortcut, isCapturing: false)

        XCTAssertEqual(model.keys, ["⌃", "⌥", "⇧", "⌘", "E"])
        XCTAssertEqual(model.title, "停止录制快捷键")
        XCTAssertEqual(model.instruction, "点击重新录入")
        XCTAssertTrue(model.accessibilityLabel.contains(shortcut.displayName))
    }

    func testCapturingPresentationPromptsForACombination() {
        let model = ShortcutKeycapPresentation(shortcut: .defaultValue, isCapturing: true)

        XCTAssertEqual(model.instruction, "请按下新的组合键…")
    }

    @MainActor
    func testCaptureCardKeepsItsDimensionsWhileListeningAtMaximumDynamicType() {
        let shortcut = RecordingStopShortcut(
            keyCode: 14,
            modifierFlags: KeyCodeMap.maskControl
                | KeyCodeMap.maskOption
                | KeyCodeMap.maskShift
                | KeyCodeMap.maskCommand
        )
        let idle = NSHostingView(
            rootView: ShortcutCaptureCard(
                shortcut: shortcut,
                isCapturing: false,
                action: {}
            )
            .environment(\.dynamicTypeSize, .accessibility5)
            .frame(width: 392)
        )
        let capturing = NSHostingView(
            rootView: ShortcutCaptureCard(
                shortcut: shortcut,
                isCapturing: true,
                action: {}
            )
            .environment(\.dynamicTypeSize, .accessibility5)
            .frame(width: 392)
        )

        XCTAssertEqual(idle.fittingSize.width, capturing.fittingSize.width, accuracy: 0.5)
        XCTAssertEqual(idle.fittingSize.height, capturing.fittingSize.height, accuracy: 0.5)
    }

    @MainActor
    func testCaptureCardInvokesExactlyOneTapAcrossItsWholeSurface() throws {
        _ = NSApplication.shared
        var tapCount = 0
        let shortcut = RecordingStopShortcut(
            keyCode: 14,
            modifierFlags: KeyCodeMap.maskControl
                | KeyCodeMap.maskOption
                | KeyCodeMap.maskShift
                | KeyCodeMap.maskCommand
        )
        let hosting = NSHostingView(
            rootView: ShortcutCaptureCard(
                shortcut: shortcut,
                isCapturing: true,
                action: { tapCount += 1 }
            )
            .environment(\.dynamicTypeSize, .accessibility5)
            .frame(width: 392)
        )
        hosting.frame = CGRect(
            origin: .zero,
            size: CGSize(width: 392, height: hosting.fittingSize.height)
        )
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

        let body = String(reflecting: ShortcutCaptureCard.Body.self)
        XCTAssertTrue(body.contains("Button"), body)
        XCTAssertTrue(body.contains("AccessibilityAttachment"), body)
        let points = [
            CGPoint(x: 12, y: 12),
            CGPoint(x: hosting.bounds.midX, y: hosting.bounds.midY),
            CGPoint(x: hosting.bounds.maxX - 12, y: hosting.bounds.maxY - 12),
        ]
        for (index, point) in points.enumerated() {
            for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(
                    with: eventType,
                    location: point,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: index,
                    clickCount: 1,
                    pressure: eventType == .leftMouseDown ? 1 : 0
                ))
                window.sendEvent(event)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            XCTAssertEqual(tapCount, index + 1)
        }
    }

    func testModifierOnlyKeyDoesNotProduceCandidate() {
        XCTAssertNil(
            ShortcutCaptureController().candidate(
                keyCode: 55,
                flags: KeyCodeMap.maskCommand
            )
        )
    }

    func testCandidateNormalizesModifiers() {
        let candidate = ShortcutCaptureController().candidate(
            keyCode: 1,
            flags: KeyCodeMap.maskOption | (1 << 16)
        )

        XCTAssertEqual(
            candidate,
            RecordingStopShortcut(
                keyCode: 1,
                modifierFlags: KeyCodeMap.maskOption
            )
        )
    }

    func testConflictingShortcutPreservesPreviousValue() {
        let previous = RecordingStopShortcut(keyCode: 53, modifierFlags: 0)
        var editor = RecordingShortcutEditor(shortcut: previous)

        let saved = editor.accept(RecordingStopShortcut(
            keyCode: 15,
            modifierFlags: KeyCodeMap.maskOption | KeyCodeMap.maskCommand
        ))

        XCTAssertFalse(saved)
        XCTAssertEqual(editor.shortcut, previous)
        XCTAssertEqual(editor.message, "与全局快捷键「开始/停止录制」冲突")
    }

    func testPlainTextKeySavesWithWarning() {
        var editor = RecordingShortcutEditor(shortcut: .defaultValue)
        let plainA = RecordingStopShortcut(keyCode: 0, modifierFlags: 0)

        XCTAssertTrue(editor.accept(plainA))
        XCTAssertEqual(editor.shortcut, plainA)
        XCTAssertEqual(editor.message, "裸文本键可能在输入文字时误触发")
    }

    func testRestoreDefaultSavesEscape() {
        var editor = RecordingShortcutEditor(shortcut: RecordingStopShortcut(
            keyCode: 1,
            modifierFlags: KeyCodeMap.maskControl
        ))

        editor.restoreDefault()

        XCTAssertEqual(editor.shortcut, .defaultValue)
        XCTAssertNil(editor.message)
    }

    @MainActor
    func testAppStateShortcutAccessReadsAndWritesInjectedStore() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-ShortcutAccess-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let shortcutStore = ShortcutStoreStub(shortcut: .defaultValue)
        let state = AppState(
            store: ScriptStore(directory: directory),
            stopShortcutStore: shortcutStore
        )
        let custom = RecordingStopShortcut(
            keyCode: 1,
            modifierFlags: KeyCodeMap.maskControl
        )

        XCTAssertEqual(state.recordingStopShortcut, .defaultValue)
        state.recordingStopShortcut = custom

        XCTAssertEqual(shortcutStore.shortcut, custom)
        XCTAssertEqual(state.recordingStopShortcut, custom)
    }
}

private final class ShortcutStoreStub: RecordingStopShortcutProviding {
    var shortcut: RecordingStopShortcut

    init(shortcut: RecordingStopShortcut) {
        self.shortcut = shortcut
    }
}

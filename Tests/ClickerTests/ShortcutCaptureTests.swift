import XCTest
@testable import Clicker
import ClickerCore

final class ShortcutCaptureTests: XCTestCase {
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

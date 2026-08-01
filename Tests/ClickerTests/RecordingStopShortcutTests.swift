import XCTest
@testable import Clicker
import ClickerCore

final class RecordingStopShortcutTests: XCTestCase {
    func testDefaultIsEscapeAndDisplaysEsc() {
        XCTAssertEqual(RecordingStopShortcut.defaultValue.keyCode, 53)
        XCTAssertEqual(RecordingStopShortcut.defaultValue.modifierFlags, 0)
        XCTAssertEqual(RecordingStopShortcut.defaultValue.displayName, "Esc")
    }

    func testMatchingIgnoresUnsupportedFlagsButRequiresConfiguredModifiers() {
        let shortcut = RecordingStopShortcut(keyCode: 1, modifierFlags: KeyCodeMap.maskOption)
        XCTAssertTrue(shortcut.matches(keyCode: 1, flags: KeyCodeMap.maskOption | (1 << 16)))
        XCTAssertFalse(shortcut.matches(keyCode: 1, flags: 0))
    }

    func testValidationRejectsGlobalConflictsAndFlagsPlainTextKeysAsRisky() {
        let record = RecordingStopShortcut(keyCode: 15, modifierFlags: KeyCodeMap.maskOption | KeyCodeMap.maskCommand)
        let play = RecordingStopShortcut(keyCode: 35, modifierFlags: KeyCodeMap.maskOption | KeyCodeMap.maskCommand)

        XCTAssertEqual(record.validation(globalRecord: record, globalPlay: play), .conflict("开始/停止录制"))
        XCTAssertEqual(
            RecordingStopShortcut(keyCode: 0, modifierFlags: 0).validation(globalRecord: record, globalPlay: play),
            .riskyTextKey
        )
    }

    func testStoreRoundTripsShortcutAndFallsBackFromInvalidData() {
        let defaults = UserDefaults(suiteName: "Clicker-StopShortcut-\(UUID())")!
        let store = RecordingStopShortcutStore(defaults: defaults)
        let custom = RecordingStopShortcut(keyCode: 100, modifierFlags: KeyCodeMap.maskControl)

        store.shortcut = custom

        XCTAssertEqual(RecordingStopShortcutStore(defaults: defaults).shortcut, custom)
        defaults.set(Data("invalid".utf8), forKey: RecordingStopShortcutStore.storageKey)
        XCTAssertEqual(RecordingStopShortcutStore(defaults: defaults).shortcut, .defaultValue)
    }

    func testStoreFallsBackFromPersistedModifierOnlyShortcut() throws {
        let defaults = UserDefaults(suiteName: "Clicker-StopShortcut-\(UUID())")!
        let modifierOnly = RecordingStopShortcut(keyCode: 55, modifierFlags: KeyCodeMap.maskCommand)
        let data = try JSONEncoder().encode(modifierOnly)

        defaults.set(data, forKey: RecordingStopShortcutStore.storageKey)

        XCTAssertEqual(RecordingStopShortcutStore(defaults: defaults).shortcut, .defaultValue)
    }
}

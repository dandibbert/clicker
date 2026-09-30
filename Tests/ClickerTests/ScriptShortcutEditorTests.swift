import XCTest
@testable import Clicker
import ClickerCore

final class ScriptShortcutEditorTests: XCTestCase {
    func testRequiresModifierAndRejectsBuiltInAndScriptConflicts() {
        let scriptID = UUID()
        let otherID = UUID()
        let otherShortcut = ScriptShortcut(
            keyCode: 18,
            modifierFlags: KeyCodeMap.maskControl | KeyCodeMap.maskOption
        )

        XCTAssertEqual(
            ScriptShortcutEditor.validate(
                candidate: ScriptShortcut(keyCode: 0, modifierFlags: 0),
                scriptID: scriptID,
                scripts: []
            ),
            .failure("脚本回放快捷键必须包含至少一个修饰键")
        )
        XCTAssertEqual(
            ScriptShortcutEditor.validate(
                candidate: ScriptShortcut(
                    keyCode: 15,
                    modifierFlags: KeyCodeMap.maskOption | KeyCodeMap.maskCommand
                ),
                scriptID: scriptID,
                scripts: []
            ),
            .failure("与全局快捷键「开始/停止录制」冲突")
        )
        XCTAssertEqual(
            ScriptShortcutEditor.validate(
                candidate: otherShortcut,
                scriptID: scriptID,
                scripts: [Script(id: otherID, name: "另一组", playbackShortcut: otherShortcut)]
            ),
            .failure("与脚本「另一组」的回放快捷键冲突")
        )
    }

    func testAcceptsUniqueModifiedShortcutAndCurrentScriptValue() {
        let scriptID = UUID()
        let shortcut = ScriptShortcut(
            keyCode: 18,
            modifierFlags: KeyCodeMap.maskControl | KeyCodeMap.maskOption
        )
        let script = Script(id: scriptID, name: "当前", playbackShortcut: shortcut)

        XCTAssertEqual(
            ScriptShortcutEditor.validate(
                candidate: shortcut,
                scriptID: scriptID,
                scripts: [script]
            ),
            .success(shortcut)
        )
    }
}

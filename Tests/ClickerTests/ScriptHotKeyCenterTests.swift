import Carbon.HIToolbox
import XCTest
@testable import Clicker
import ClickerCore

final class ScriptHotKeyCenterTests: XCTestCase {
    func testRefreshRegistersEveryUniqueScriptShortcutWithStableIDs() {
        let firstID = UUID()
        let secondID = UUID()
        let firstShortcut = ScriptShortcut(
            keyCode: 18,
            modifierFlags: KeyCodeMap.maskControl | KeyCodeMap.maskOption
        )
        let secondShortcut = ScriptShortcut(
            keyCode: 19,
            modifierFlags: KeyCodeMap.maskControl | KeyCodeMap.maskOption
        )
        var registrations: [(UInt32, UInt32, UInt32)] = []
        let center = ScriptHotKeyCenter(registerHotKey: { keyCode, modifiers, hotKeyID in
            registrations.append((keyCode, modifiers, hotKeyID.id))
            return HotKeyRegistrationResult(status: noErr, reference: nil)
        })

        let issues = center.refresh(scripts: [
            Script(name: "A", playbackShortcut: firstShortcut),
            Script(id: firstID, name: "B", playbackShortcut: firstShortcut),
            Script(id: secondID, name: "C", playbackShortcut: secondShortcut),
        ])

        XCTAssertEqual(registrations.map(\.0), [18, 19])
        XCTAssertEqual(Set(registrations.map(\.2)).count, 2)
        XCTAssertEqual(issues.map(\.scriptID), [firstID])
    }

    func testRegistrationFailureReturnsNamedIssue() {
        let script = Script(
            name: "日报",
            playbackShortcut: ScriptShortcut(
                keyCode: 18,
                modifierFlags: KeyCodeMap.maskControl | KeyCodeMap.maskOption
            )
        )
        let center = ScriptHotKeyCenter(registerHotKey: { _, _, _ in
            HotKeyRegistrationResult(status: -9_878, reference: nil)
        })

        XCTAssertEqual(center.refresh(scripts: [script]), [
            ScriptHotKeyRegistrationIssue(
                scriptID: script.id,
                scriptName: "日报",
                shortcut: script.playbackShortcut!,
                status: -9_878
            ),
        ])
    }

    func testRefreshRejectsPersistedShortcutWithoutModifierBeforeRegistration() {
        let script = Script(
            name: "不安全",
            playbackShortcut: ScriptShortcut(keyCode: 0, modifierFlags: 0)
        )
        var registrationCount = 0
        let center = ScriptHotKeyCenter(registerHotKey: { _, _, _ in
            registrationCount += 1
            return HotKeyRegistrationResult(status: noErr, reference: nil)
        })

        let issues = center.refresh(scripts: [script])

        XCTAssertEqual(registrationCount, 0)
        XCTAssertEqual(issues.map(\.scriptID), [script.id])
        XCTAssertEqual(issues.map(\.status), [OSStatus(paramErr)])
    }
}

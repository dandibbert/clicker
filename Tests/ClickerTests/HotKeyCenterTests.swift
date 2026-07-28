import Carbon.HIToolbox
import XCTest
@testable import Clicker
import ClickerCore

final class HotKeyCenterTests: XCTestCase {
    func testRegistrationReportsOnlyPlaybackFailureStatus() {
        let failedStatus = OSStatus(-9_878)
        let center = HotKeyCenter { _, _, hotKeyID in
            HotKeyRegistrationResult(
                status: hotKeyID.id == 2 ? failedStatus : noErr,
                reference: nil
            )
        }

        let issues = center.registerHotKeys()

        XCTAssertEqual(issues, [
            HotKeyRegistrationIssue(shortcut: .playback, status: failedStatus),
        ])
    }

    func testRegistrationReportsOnlyRecordingFailureStatus() {
        let failedStatus = OSStatus(-50)
        let center = HotKeyCenter { _, _, hotKeyID in
            HotKeyRegistrationResult(
                status: hotKeyID.id == 1 ? failedStatus : noErr,
                reference: nil
            )
        }

        let issues = center.registerHotKeys()

        XCTAssertEqual(issues, [
            HotKeyRegistrationIssue(shortcut: .recording, status: failedStatus),
        ])
    }

    func testSuccessfulRegistrationsReturnNoIssues() {
        let center = HotKeyCenter { _, _, _ in
            HotKeyRegistrationResult(status: noErr, reference: nil)
        }

        XCTAssertTrue(center.registerHotKeys().isEmpty)
    }

    @MainActor
    func testAppStatePublishesFirstRegistrationFailureForPresentation() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-HotKeyIssue-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(store: ScriptStore(directory: directory))
        let issues = [
            HotKeyRegistrationIssue(shortcut: .recording, status: -50),
            HotKeyRegistrationIssue(shortcut: .playback, status: -51),
        ]

        state.reportHotKeyRegistrationIssues(issues)

        XCTAssertEqual(state.hotKeyRegistrationIssue, issues[0])
    }
}

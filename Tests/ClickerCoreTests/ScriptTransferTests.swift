import Foundation
import XCTest
@testable import ClickerCore

final class ScriptTransferTests: XCTestCase {
    func testExportRoundTripUsesStorageDatesAndRetainsAllPreviewMetadata() throws {
        let script = Script(
            name: "共享脚本", createdAt: Date(timeIntervalSince1970: 1234),
            modifiedAt: Date(timeIntervalSince1970: 2345),
            blocks: [.wait(WaitBlock(duration: 2, startOffset: 1))],
            targetBundleIdentifier: "com.example.app", startApplicationBeforePlayback: true,
            playbackShortcut: ScriptShortcut(keyCode: 9, modifierFlags: KeyCodeMap.maskCommand)
        )
        let data = try ScriptTransfer.encode(script)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["createdAt"] as? Double, 1_234_000)
        XCTAssertEqual(try ScriptTransfer.decode(data: data), script)
    }

    func testImportCreatesSafeCopyWithoutAffectingPreviewIdentity() throws {
        let original = Script(
            name: "Imported", blocks: [.wait(WaitBlock(duration: 2))],
            targetBundleIdentifier: "com.example.app", startApplicationBeforePlayback: true,
            playbackShortcut: ScriptShortcut(keyCode: 9, modifierFlags: KeyCodeMap.maskCommand)
        )
        let data = try ScriptTransfer.encode(original)
        let preview = try ScriptTransfer.decode(data)
        let now = Date(timeIntervalSince1970: 50)
        let imported = try ScriptJSONCodec.importScript(from: data, now: now)
        XCTAssertEqual(preview.id, original.id)
        XCTAssertNotEqual(imported.id, original.id)
        XCTAssertNotEqual(imported.blocks[0].id, original.blocks[0].id)
        XCTAssertNil(imported.playbackShortcut)
        XCTAssertFalse(imported.startApplicationBeforePlayback)
        XCTAssertEqual(imported.targetBundleIdentifier, original.targetBundleIdentifier)
        XCTAssertEqual(imported.createdAt, now)
        XCTAssertEqual(imported.modifiedAt, now)
    }

    func testLegacyFixturesStillMigrateAndHaveNoStartApplicationOptIn() throws {
        let script = try ScriptTransfer.decode(legacyV1ScriptData)
        XCTAssertEqual(script.schemaVersion, Script.currentSchemaVersion)
        XCTAssertFalse(script.startApplicationBeforePlayback)
        XCTAssertFalse(script.blocks.isEmpty)
        XCTAssertEqual(script.blocks.map(\.delayBefore), Array(repeating: 0, count: script.blocks.count))
    }

    func testExistingV4TargetDoesNotSilentlyEnableApplicationSwitching() throws {
        let script = Script(name: "Existing", targetBundleIdentifier: "com.example.target")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: ScriptTransfer.encode(script))
                                  as? [String: Any])
        object.removeValue(forKey: "startApplicationBeforePlayback")
        let decoded = try ScriptTransfer.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(decoded.startApplicationBeforePlayback)
        XCTAssertEqual(decoded.targetBundleIdentifier, "com.example.target")
    }

    func testUnsupportedVersionHasSpecificError() throws {
        for version in [0, Script.currentSchemaVersion + 1] {
            let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": version])
            XCTAssertThrowsError(try ScriptTransfer.decode(data)) { error in
                XCTAssertEqual(error as? ScriptTransferError, .unsupportedSchemaVersion(version))
            }
        }
    }

    func testMalformedOrWrongShapeJSONIsRejectedWithoutPartialImport() {
        for text in ["not json", "[]", "null", "{}", #"{"schemaVersion":"four"}"#] {
            XCTAssertThrowsError(try ScriptTransfer.decode(Data(text.utf8))) { error in
                guard let transferError = error as? ScriptTransferError,
                      case .invalidDocument = transferError else {
                    return XCTFail("Expected invalid-document error, got \(error)")
                }
            }
        }
    }

    func testNonFiniteExportFailsExplicitly() {
        let script = Script(name: "Invalid", blocks: [.wait(WaitBlock(duration: .infinity))])
        XCTAssertThrowsError(try ScriptTransfer.encode(script)) { error in
            guard let transferError = error as? ScriptTransferError,
                  case .encodingFailed = transferError else {
                return XCTFail("Expected encoding error, got \(error)")
            }
        }
    }
}

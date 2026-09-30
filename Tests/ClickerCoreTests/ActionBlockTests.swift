import Foundation
import XCTest
@testable import ClickerCore

let legacyV1ScriptData = Data(#"""
{
  "blocks" : [
    {
      "move" : {
        "_0" : {
          "duration" : 0.5,
          "id" : "22222222-2222-2222-2222-222222222222",
          "points" : [
            { "t" : 0, "x" : 1, "y" : 2 }
          ]
        }
      }
    },
    {
      "click" : {
        "_0" : {
          "button" : "left",
          "clickCount" : 1,
          "id" : "33333333-3333-3333-3333-333333333333",
          "x" : 3,
          "y" : 4
        }
      }
    },
    {
      "drag" : {
        "_0" : {
          "button" : "right",
          "duration" : 0.4,
          "id" : "44444444-4444-4444-4444-444444444444",
          "points" : [
            { "t" : 0, "x" : 5, "y" : 6 },
            { "t" : 0.4, "x" : 7, "y" : 8 }
          ]
        }
      }
    },
    {
      "scroll" : {
        "_0" : {
          "duration" : 0.1,
          "id" : "55555555-5555-5555-5555-555555555555",
          "steps" : [
            { "dx" : 1, "dy" : -2, "t" : 0 }
          ],
          "x" : 9,
          "y" : 10
        }
      }
    },
    {
      "typeText" : {
        "_0" : {
          "id" : "66666666-6666-6666-6666-666666666666",
          "keystrokes" : [
            { "chars" : "a", "keyCode" : 0, "t" : 0 }
          ],
          "text" : "a"
        }
      }
    },
    {
      "shortcut" : {
        "_0" : {
          "flags" : 1048576,
          "id" : "77777777-7777-7777-7777-777777777777",
          "keyCode" : 8
        }
      }
    },
    {
      "wait" : {
        "_0" : {
          "duration" : 2,
          "id" : "88888888-8888-8888-8888-888888888888"
        }
      }
    }
  ],
  "createdAt" : 0,
  "id" : "11111111-1111-1111-1111-111111111111",
  "modifiedAt" : 0,
  "name" : "Legacy",
  "repeatCount" : 1,
  "repeatForever" : false,
  "repeatInterval" : 0
}
"""#.utf8)

final class ActionBlockTests: XCTestCase {
    func testV1SynthesizedJSONDecodesWithLegacyDefaults() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let script = try decoder.decode(Script.self, from: legacyV1ScriptData)

        XCTAssertEqual(script.schemaVersion, 4)
        XCTAssertEqual(script.trailingDelay, 0)
        XCTAssertNil(script.targetBundleIdentifier)
        XCTAssertEqual(script.blocks.count, 7)
        XCTAssertEqual(script.blocks.map(\.overlapBefore), [0, 0, 0, 0, 0, 0, 0])

        guard case .move(let move) = script.blocks[0] else { return XCTFail("expected move") }
        XCTAssertEqual(move.delayBefore, 0)
        XCTAssertEqual(move.points[0].flags, 0)

        guard case .click(let click) = script.blocks[1] else { return XCTFail("expected click") }
        XCTAssertEqual(click.delayBefore, 0)
        XCTAssertEqual(click.duration, 0.03, accuracy: 0.000_001)
        XCTAssertEqual(click.upX, click.x)
        XCTAssertEqual(click.upY, click.y)
        XCTAssertEqual(click.upClickCount, click.clickCount)
        XCTAssertEqual(click.downFlags, 0)
        XCTAssertEqual(click.upFlags, 0)

        guard case .drag(let drag) = script.blocks[2] else { return XCTFail("expected drag") }
        XCTAssertEqual(drag.delayBefore, 0)
        XCTAssertEqual(drag.points.map(\.flags), [0, 0])
        XCTAssertTrue(drag.hasRecordedMouseUp)

        guard case .scroll(let scroll) = script.blocks[3] else { return XCTFail("expected scroll") }
        XCTAssertEqual(scroll.delayBefore, 0)
        XCTAssertEqual(scroll.steps[0].flags, 0)
        XCTAssertEqual(scroll.steps[0].x, 9)
        XCTAssertEqual(scroll.steps[0].y, 10)
        XCTAssertEqual(
            BlockExpander.plan(blocks: [.scroll(scroll)]).steps.first?.action,
            .scroll(x: 9, y: 10, dx: 1, dy: -2, flags: 0)
        )

        guard case .typeText(let typeText) = script.blocks[4] else { return XCTFail("expected typeText") }
        XCTAssertEqual(typeText.delayBefore, 0)
        XCTAssertEqual(typeText.duration, 0.02, accuracy: 0.000_001)
        XCTAssertEqual(typeText.keystrokes[0].upT, 0.02, accuracy: 0.000_001)
        XCTAssertEqual(typeText.keystrokes[0].downFlags, 0)
        XCTAssertEqual(typeText.keystrokes[0].upFlags, 0)

        guard case .shortcut(let shortcut) = script.blocks[5] else { return XCTFail("expected shortcut") }
        XCTAssertEqual(shortcut.delayBefore, 0)
        XCTAssertEqual(shortcut.duration, 0.02, accuracy: 0.000_001)
        XCTAssertEqual(shortcut.upFlags, shortcut.flags)
    }

    func testAcceptsCurrentSchemaAndRejectsUnsupportedVersions() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        var currentObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: legacyV1ScriptData) as? [String: Any]
        )
        currentObject["schemaVersion"] = 4
        let currentData = try JSONSerialization.data(withJSONObject: currentObject)
        XCTAssertEqual(try decoder.decode(Script.self, from: currentData).schemaVersion, 4)

        for schemaVersion in [0, 5, 99] {
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: legacyV1ScriptData) as? [String: Any]
            )
            object["schemaVersion"] = schemaVersion
            let data = try JSONSerialization.data(withJSONObject: object)

            XCTAssertThrowsError(try decoder.decode(Script.self, from: data))
        }
    }

    func testV2ScrollWithoutStepLocationsUsesBlockLocationFallback() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: legacyV1ScriptData) as? [String: Any]
        )
        object["schemaVersion"] = 2
        let data = try JSONSerialization.data(withJSONObject: object)

        let script = try decoder.decode(Script.self, from: data)

        XCTAssertEqual(script.blocks.map(\.overlapBefore), [0, 0, 0, 0, 0, 0, 0])
        guard case .drag(let drag) = script.blocks[2] else { return XCTFail() }
        XCTAssertTrue(drag.hasRecordedMouseUp)
        guard case .scroll(let scroll) = script.blocks[3] else { return XCTFail() }
        XCTAssertEqual(scroll.steps[0].x, 9)
        XCTAssertEqual(scroll.steps[0].y, 10)
        XCTAssertEqual(
            BlockExpander.plan(blocks: [.scroll(scroll)]).steps.first?.action,
            .scroll(x: 9, y: 10, dx: 1, dy: -2, flags: 0)
        )
    }

    func testV4RoundTripPreservesLosslessTimelineFields() throws {
        let script = Script(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Lossless",
            createdAt: Date(timeIntervalSince1970: 1_000),
            modifiedAt: Date(timeIntervalSince1970: 2_000),
            blocks: [
                ActionBlock.move(MoveBlock(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                    duration: 0.4,
                    points: [TrackPoint(t: 0.1, x: 1, y: 2, flags: 11)],
                    startOffset: 0.01
                )),
                ActionBlock.click(ClickBlock(
                    id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
                    x: 3,
                    y: 4,
                    button: .right,
                    clickCount: 2,
                    startOffset: 0.02,
                    duration: 0.25,
                    upX: 5,
                    upY: 6,
                    upClickCount: 3,
                    downFlags: 12,
                    upFlags: 13
                )),
                ActionBlock.drag(DragBlock(
                    id: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
                    button: .left,
                    duration: 0.5,
                    points: [
                        TrackPoint(t: 0, x: 7, y: 8, flags: 14),
                        TrackPoint(t: 0.5, x: 9, y: 10, flags: 15),
                    ],
                    startOffset: 0.03,
                    hasRecordedMouseUp: false
                )),
                ActionBlock.scroll(ScrollBlock(
                    id: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
                    x: 11,
                    y: 12,
                    duration: 0.6,
                    steps: [ScrollStep(
                        t: 0.2,
                        x: 21,
                        y: 22,
                        dx: 13,
                        dy: -14,
                        flags: 16
                    )],
                    startOffset: 0.04
                )),
                ActionBlock.typeText(TypeTextBlock(
                    id: UUID(uuidString: "50000000-0000-0000-0000-000000000005")!,
                    text: "A",
                    keystrokes: [Keystroke(
                        t: 0.1,
                        keyCode: 0,
                        chars: "A",
                        upT: 0.35,
                        downFlags: 17,
                        upFlags: 18
                    )],
                    startOffset: 0.05,
                    duration: 0.4
                )),
                ActionBlock.shortcut(ShortcutBlock(
                    id: UUID(uuidString: "60000000-0000-0000-0000-000000000006")!,
                    keyCode: 8,
                    flags: 19,
                    startOffset: 0.06,
                    upFlags: 20,
                    duration: 0.45
                )),
                .wait(WaitBlock(
                    id: UUID(uuidString: "70000000-0000-0000-0000-000000000007")!,
                    duration: 2,
                    startOffset: 0.07
                )),
            ],
            repeatCount: 3,
            repeatForever: true,
            repeatInterval: 0.7,
            schemaVersion: 4,
            trailingDelay: 0.8,
            targetBundleIdentifier: "com.example.target"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let data = try encoder.encode(script)
        let decoded = try decoder.decode(Script.self, from: data)

        XCTAssertEqual(decoded, script)
        XCTAssertEqual(
            decoded.blocks.map(\.startOffset),
            [0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.07]
        )
        XCTAssertEqual(decoded.blocks.map(\.overlapBefore), Array(repeating: 0, count: 7))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 4)
    }

    func testTimelineDefaultsAndActionBlockHelpers() {
        let keystroke = Keystroke(t: 0.5, keyCode: 4, chars: "h")
        XCTAssertEqual(keystroke.upT, 0.52, accuracy: 0.000_001)
        XCTAssertEqual(keystroke.downFlags, 0)
        XCTAssertEqual(keystroke.upFlags, 0)

        let generatedText = TypeTextBlock(text: "AB", keystrokes: [])
        XCTAssertEqual(generatedText.duration, 0.08, accuracy: 0.000_001)

        let shortcut = ShortcutBlock(keyCode: 8, flags: 123)
        XCTAssertEqual(shortcut.upFlags, 123)
        XCTAssertEqual(shortcut.duration, 0.02, accuracy: 0.000_001)

        let id = UUID()
        let block = ActionBlock.click(ClickBlock(
            id: id,
            x: 1,
            y: 2,
            button: .left,
            clickCount: 1,
            delayBefore: 0.4,
            duration: 0.25
        ))
        let changed = block.withDelayBefore(0.9)
        let overlapping = block.withOverlapBefore(0.15)
        XCTAssertEqual(block.delayBefore, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(block.overlapBefore, 0, accuracy: 0.000_001)
        XCTAssertEqual(block.duration, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(changed.delayBefore, 0.9, accuracy: 0.000_001)
        XCTAssertEqual(changed.overlapBefore, 0, accuracy: 0.000_001)
        XCTAssertEqual(changed.id, id)
        XCTAssertEqual(overlapping.delayBefore, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(overlapping.overlapBefore, 0.15, accuracy: 0.000_001)
        XCTAssertEqual(overlapping.id, id)

        let dragFactory: (UUID, MouseButton, TimeInterval, [TrackPoint], TimeInterval) -> DragBlock
            = DragBlock.init
        let compatibleDrag = dragFactory(id, .left, 0.2, [], 0.1)
        XCTAssertTrue(compatibleDrag.hasRecordedMouseUp)
        XCTAssertEqual(compatibleDrag.delayBefore, 0.1, accuracy: 0.000_001)

        let wait = ActionBlock.wait(WaitBlock(id: id, duration: 2))
        XCTAssertEqual(wait.delayBefore, 0)
        XCTAssertEqual(wait.duration, 2)
        XCTAssertEqual(wait.withDelayBefore(1), wait)
    }

    func testScriptDefaultsToCurrentSchema() {
        let script = Script(name: "测试")
        XCTAssertEqual(script.schemaVersion, 4)
        XCTAssertEqual(script.repeatCount, 1)
        XCTAssertFalse(script.repeatForever)
        XCTAssertEqual(script.repeatInterval, 0)
        XCTAssertEqual(script.trailingDelay, 0)
        XCTAssertNil(script.targetBundleIdentifier)
        XCTAssertNil(script.playbackShortcut)
        XCTAssertTrue(script.blocks.isEmpty)
    }

    func testPlaybackShortcutRoundTripsAndOlderScriptsDefaultToNil() throws {
        let shortcut = ScriptShortcut(
            keyCode: 18,
            modifierFlags: KeyCodeMap.maskControl | KeyCodeMap.maskOption
        )
        let script = Script(name: "快捷回放", playbackShortcut: shortcut)

        let data = try JSONEncoder().encode(script)
        let decoded = try JSONDecoder().decode(Script.self, from: data)

        XCTAssertEqual(decoded.playbackShortcut, shortcut)
        XCTAssertEqual(shortcut.displayName, "⌃⌥1")

        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        legacyObject["schemaVersion"] = 4
        legacyObject.removeValue(forKey: "playbackShortcut")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        XCTAssertNil(try JSONDecoder().decode(Script.self, from: legacyData).playbackShortcut)
    }
}

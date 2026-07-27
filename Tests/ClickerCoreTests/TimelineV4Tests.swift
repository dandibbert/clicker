import Foundation
import XCTest
@testable import ClickerCore

final class TimelineV4Tests: XCTestCase {
    func testV4EncodingUsesAbsoluteOffsetsAndOrdinalsWithoutLegacyTimingKeys() throws {
        let script = Script(
            name: "Canonical",
            createdAt: Date(timeIntervalSince1970: 1),
            modifiedAt: Date(timeIntervalSince1970: 2),
            blocks: [
                .click(ClickBlock(
                    x: 1,
                    y: 2,
                    button: .left,
                    clickCount: 1,
                    startOffset: 0.25,
                    duration: 0.1,
                    downOrdinal: 3,
                    upOrdinal: 5
                )),
                .scroll(ScrollBlock(
                    x: 10,
                    y: 20,
                    duration: 0.2,
                    steps: [ScrollStep(
                        t: 0.2,
                        x: 30,
                        y: 40,
                        dx: 1,
                        dy: -2,
                        flags: 7,
                        ordinal: 8
                    )],
                    startOffset: 0.5
                )),
                .typeText(TypeTextBlock(
                    text: "a",
                    keystrokes: [Keystroke(
                        t: 0,
                        keyCode: 0,
                        chars: "a",
                        upT: 0.15,
                        downFlags: 9,
                        upFlags: 10,
                        downOrdinal: 11,
                        upOrdinal: 12
                    )],
                    startOffset: 0.75,
                    duration: 0.15
                )),
                .wait(WaitBlock(duration: 1, startOffset: 1))
            ],
            trailingDelay: 0.4
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let data = try encoder.encode(script)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try decoder.decode(Script.self, from: data)

        XCTAssertEqual(decoded, script)
        XCTAssertEqual(decoded.schemaVersion, 4)
        XCTAssertEqual(decoded.blocks.map(\.startOffset), [0.25, 0.5, 0.75, 1])
        XCTAssertEqual(encoded.components(separatedBy: "\"startOffset\"").count - 1, 4)
        XCTAssertFalse(encoded.contains("\"delayBefore\""))
        XCTAssertFalse(encoded.contains("\"overlapBefore\""))
        XCTAssertTrue(encoded.contains("\"ordinal\""))
        XCTAssertTrue(encoded.contains("\"downOrdinal\""))
        XCTAssertTrue(encoded.contains("\"upOrdinal\""))
    }

    func testV3MigrationProducesDeterministicAbsoluteOffsetsAndOrdinals() throws {
        let data = Data(#"""
        {
          "blocks": [
            { "click": { "_0": {
              "id": "10000000-0000-0000-0000-000000000001",
              "x": 1, "y": 2, "button": "left", "clickCount": 1,
              "delayBefore": 0.4, "duration": 1
            }}},
            { "shortcut": { "_0": {
              "id": "20000000-0000-0000-0000-000000000002",
              "keyCode": 8, "flags": 1048576,
              "delayBefore": 0.2, "overlapBefore": 0.5, "duration": 0.3
            }}},
            { "wait": { "_0": {
              "id": "30000000-0000-0000-0000-000000000003", "duration": 2
            }}},
            { "click": { "_0": {
              "id": "40000000-0000-0000-0000-000000000004",
              "x": 3, "y": 4, "button": "right", "clickCount": 1,
              "delayBefore": 0.1, "duration": 0.1
            }}}
          ],
          "createdAt": 0,
          "id": "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
          "modifiedAt": 0,
          "name": "Legacy v3",
          "repeatCount": 1,
          "repeatForever": false,
          "repeatInterval": 0,
          "schemaVersion": 3
        }
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let script = try decoder.decode(Script.self, from: data)

        XCTAssertEqual(script.schemaVersion, 4)
        for (actual, expected) in zip(script.blocks.map(\.startOffset), [0.4, 1.1, 1.6, 3.7]) {
            XCTAssertEqual(actual, expected, accuracy: 0.000_001)
        }
        guard case .click(let first) = script.blocks[0],
              case .shortcut(let shortcut) = script.blocks[1],
              case .click(let last) = script.blocks[3] else {
            return XCTFail("unexpected migrated blocks")
        }
        XCTAssertEqual([first.downOrdinal, first.upOrdinal], [0, 1])
        XCTAssertEqual([shortcut.downOrdinal, shortcut.upOrdinal], [2, 3])
        XCTAssertEqual([last.downOrdinal, last.upOrdinal], [4, 5])
        XCTAssertEqual(script.blocks.map(\.delayBefore), [0, 0, 0, 0])
        XCTAssertEqual(script.blocks.map(\.overlapBefore), [0, 0, 0, 0])
    }

    func testLegacyScrollWithPartialLocationFallsBackAtomicallyAndNormalizes() throws {
        let data = Data(#"""
        {
          "blocks": [
            { "scroll": { "_0": {
              "id": "50000000-0000-0000-0000-000000000005",
              "x": 10, "y": 20, "duration": 0,
              "steps": [{ "t": 0, "x": 999, "dx": 1, "dy": -2, "flags": 7 }]
            }}}
          ],
          "createdAt": 0,
          "id": "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
          "modifiedAt": 0,
          "name": "Legacy scroll",
          "repeatCount": 1,
          "repeatForever": false,
          "repeatInterval": 0,
          "schemaVersion": 2
        }
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        let script = try decoder.decode(Script.self, from: data)

        guard case .scroll(let scroll) = script.blocks[0] else { return XCTFail() }
        XCTAssertEqual(scroll.steps[0].x, 10)
        XCTAssertEqual(scroll.steps[0].y, 20)
        XCTAssertEqual(scroll.steps[0].flags, 7)
        XCTAssertEqual(
            BlockExpander.plan(for: script).steps[0].action,
            .scroll(x: 10, y: 20, dx: 1, dy: -2, flags: 7)
        )

        let encoded = try JSONEncoder().encode(script)
        let string = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertTrue(string.contains("\"x\":10"))
        XCTAssertTrue(string.contains("\"y\":20"))
    }

    func testInterruptedDragWithMaximumOrdinalDoesNotOverflow() {
        let drag = DragBlock(
            button: .left,
            duration: 1,
            points: [TrackPoint(t: 1, x: 2, y: 3, ordinal: Int.max)],
            hasRecordedMouseUp: false
        )

        XCTAssertEqual(drag.upOrdinal, Int.max)
    }

    func testAllBlockInitializersSanitizeStartOffset() {
        let blocks: [ActionBlock] = [
            .move(MoveBlock(duration: 0, points: [], startOffset: -.infinity)),
            .click(ClickBlock(
                x: 0,
                y: 0,
                button: .left,
                clickCount: 1,
                startOffset: -1
            )),
            .drag(DragBlock(
                button: .left,
                duration: 0,
                points: [],
                startOffset: .nan
            )),
            .scroll(ScrollBlock(x: 0, y: 0, duration: 0, steps: [], startOffset: -2)),
            .typeText(TypeTextBlock(text: "", keystrokes: [], startOffset: -.infinity)),
            .shortcut(ShortcutBlock(keyCode: 0, flags: 0, startOffset: -3)),
            .wait(WaitBlock(duration: 0, startOffset: .nan))
        ]

        XCTAssertEqual(blocks.map(\.startOffset), Array(repeating: 0, count: blocks.count))
        XCTAssertTrue(blocks.allSatisfy { $0.startOffset.isFinite && $0.startOffset >= 0 })
    }
}

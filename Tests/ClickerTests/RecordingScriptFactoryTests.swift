import XCTest
@testable import Clicker
import ClickerCore

final class RecordingScriptFactoryTests: XCTestCase {
    func testUIStopWritesGroupedBlocksTrailingDelayAndTargetApplication() {
        let capture = RecordingCapture(
            events: [
                RecordedEvent(t: 0.1, kind: .leftDown, x: 10, y: 20),
                RecordedEvent(t: 0.2, kind: .leftUp, x: 10, y: 20),
            ],
            duration: 0.35
        )

        let script = RecordingScriptFactory.makeScript(
            name: "UI recording",
            capture: capture,
            stopSource: .ui,
            targetBundleIdentifier: "com.example.target"
        )

        XCTAssertEqual(script.name, "UI recording")
        XCTAssertEqual(script.blocks.count, 1)
        XCTAssertEqual(script.trailingDelay, 0.15, accuracy: 0.000_001)
        XCTAssertEqual(script.targetBundleIdentifier, "com.example.target")
    }

    func testHotKeyStopRemovesStopGestureButRetainsCutoffDuration() {
        let stopFlags = KeyCodeMap.maskOption | KeyCodeMap.maskCommand
        let capture = RecordingCapture(
            events: [
                RecordedEvent(t: 0.1, kind: .leftDown, x: 10, y: 20),
                RecordedEvent(t: 0.2, kind: .leftUp, x: 10, y: 20),
                RecordedEvent(t: 0.8, kind: .flagsChanged, keyCode: 58,
                              flags: KeyCodeMap.maskOption),
                RecordedEvent(t: 0.9, kind: .flagsChanged, keyCode: 55,
                              flags: stopFlags),
                RecordedEvent(t: 1.0, kind: .keyDown, keyCode: 15,
                              flags: stopFlags, chars: "r"),
            ],
            duration: 1.2
        )

        let script = RecordingScriptFactory.makeScript(
            name: "Hotkey recording",
            capture: capture,
            stopSource: .hotkey,
            targetBundleIdentifier: nil
        )

        XCTAssertFalse(script.blocks.contains { block in
            if case .shortcut = block { return true }
            return false
        })
        let plan = BlockExpander.plan(
            blocks: script.blocks,
            trailingDelay: script.trailingDelay
        )
        XCTAssertEqual(plan.duration, 1.2, accuracy: 0.000_001)
    }

    func testMenuBarStopExcludesEventsAfterEstablishedCutoff() {
        let capture = RecordingCapture(
            events: [
                RecordedEvent(t: 0.1, kind: .leftDown, x: 10, y: 20),
                RecordedEvent(t: 0.2, kind: .leftUp, x: 10, y: 20),
                RecordedEvent(t: 0.8, kind: .mouseMove, x: 500, y: 10),
                RecordedEvent(t: 0.9, kind: .leftDown, x: 500, y: 10),
                RecordedEvent(t: 1.0, kind: .leftUp, x: 500, y: 10),
            ],
            duration: 1.1
        )

        let script = RecordingScriptFactory.makeScript(
            name: "Menu recording",
            capture: capture,
            stopSource: .menubar(cutoff: RecordingCutoff(
                eventCount: 2,
                duration: 0.7
            )),
            targetBundleIdentifier: nil
        )

        XCTAssertFalse(script.blocks.contains { block in
            if case .move = block { return true }
            return false
        })
        let plan = BlockExpander.plan(
            blocks: script.blocks,
            trailingDelay: script.trailingDelay
        )
        XCTAssertEqual(plan.duration, 0.7, accuracy: 0.000_001)
    }
}

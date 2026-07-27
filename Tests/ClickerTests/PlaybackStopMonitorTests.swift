import CoreGraphics
import XCTest
@testable import Clicker

final class PlaybackStopMonitorTests: XCTestCase {
    func testOnlyUnmarkedEscapeRequestsPlaybackStop() throws {
        let hardwareEscape = try XCTUnwrap(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 53,
            keyDown: true
        ))
        let syntheticEscape = try XCTUnwrap(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 53,
            keyDown: true
        ))
        syntheticEscape.setIntegerValueField(
            .eventSourceUserData,
            value: EventRecorder.syntheticMarker
        )
        let returnKey = try XCTUnwrap(CGEvent(
            keyboardEventSource: nil,
            virtualKey: 36,
            keyDown: true
        ))

        XCTAssertTrue(PlaybackStopEventClassifier.shouldStop(for: hardwareEscape))
        XCTAssertFalse(PlaybackStopEventClassifier.shouldStop(for: syntheticEscape))
        XCTAssertFalse(PlaybackStopEventClassifier.shouldStop(for: returnKey))
    }
}

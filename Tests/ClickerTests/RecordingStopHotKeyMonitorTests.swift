import Carbon.HIToolbox
import XCTest
@testable import Clicker
import ClickerCore

final class RecordingStopHotKeyMonitorTests: XCTestCase {
    func testCarbonModifiersAreDerivedFromSupportedCGEventFlags() {
        XCTAssertEqual(
            CarbonRecordingStopHotKeyMonitor.carbonModifiers(
                for: KeyCodeMap.maskControl
                    | KeyCodeMap.maskOption
                    | KeyCodeMap.maskShift
                    | KeyCodeMap.maskCommand
            ),
            UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        XCTAssertEqual(
            CarbonRecordingStopHotKeyMonitor.carbonModifiers(for: 1 << 16),
            0
        )
    }
}

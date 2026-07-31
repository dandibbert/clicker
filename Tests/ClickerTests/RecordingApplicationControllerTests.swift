import XCTest
@testable import Clicker

final class RecordingApplicationControllerTests: XCTestCase {
    func testHidingClickerKeepsApplicationAvailableForCountdownPanel() {
        let window = NSObject()
        var isWindowVisible = true
        var activationCount = 0
        let controller = SystemRecordingApplicationController(
            visibleWindows: { isWindowVisible ? [window] : [] },
            orderOut: { hiddenWindow in
                XCTAssertTrue(hiddenWindow === window)
                isWindowVisible = false
            },
            orderFront: { restoredWindow in
                XCTAssertTrue(restoredWindow === window)
                isWindowVisible = true
            },
            activateClicker: { activationCount += 1 }
        )

        controller.hideClicker()

        XCTAssertFalse(isWindowVisible)
        XCTAssertEqual(activationCount, 0)

        controller.restoreClicker()

        XCTAssertTrue(isWindowVisible)
        XCTAssertEqual(activationCount, 1)
    }
}

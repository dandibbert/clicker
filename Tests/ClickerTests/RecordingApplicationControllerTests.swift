import AppKit
import XCTest
@testable import Clicker

final class RecordingApplicationControllerTests: XCTestCase {
    func testHidingClickerConcealsWindowWithoutRemovingItAndDeactivatesApplication() {
        let window = NSObject()
        let isWindowVisible = true
        var isWindowConcealed = false
        var deactivationCount = 0
        var activationCount = 0
        let controller = SystemRecordingApplicationController(
            visibleWindows: { isWindowVisible ? [window] : [] },
            conceal: { hiddenWindow in
                XCTAssertTrue(hiddenWindow === window)
                isWindowConcealed = true
            },
            reveal: { restoredWindow in
                XCTAssertTrue(restoredWindow === window)
                isWindowConcealed = false
            },
            deactivateClicker: { deactivationCount += 1 },
            activateClicker: { activationCount += 1 }
        )

        controller.hideClicker()

        XCTAssertTrue(isWindowVisible)
        XCTAssertTrue(isWindowConcealed)
        XCTAssertEqual(deactivationCount, 1)
        XCTAssertEqual(activationCount, 0)

        controller.restoreClicker()

        XCTAssertTrue(isWindowVisible)
        XCTAssertFalse(isWindowConcealed)
        XCTAssertEqual(deactivationCount, 1)
        XCTAssertEqual(activationCount, 1)
    }

    func testProductionConcealAndRevealKeepWindowInLifecycle() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.orderFront(nil)

        SystemRecordingApplicationController.conceal(window)

        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertTrue(window.ignoresMouseEvents)

        SystemRecordingApplicationController.reveal(window)

        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.alphaValue, 1)
        XCTAssertFalse(window.ignoresMouseEvents)
        window.orderOut(nil)
    }
}

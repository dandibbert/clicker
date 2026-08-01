import AppKit
import XCTest
@testable import Clicker

@MainActor
final class ApplicationControllerTests: XCTestCase {
    func testActivationDelegatesOnlyToRequestedRunningBundleIdentifier() {
        var identifiers: [String] = []
        let controller = SystemApplicationController(
            visibleWindows: { [] },
            conceal: { _ in },
            reveal: { _ in },
            deactivateClicker: {},
            activateClicker: {},
            activateExternal: {
                identifiers.append($0)
                return $0 == "com.example.target"
            }
        )

        XCTAssertTrue(controller.activateExternalApplication(
            bundleIdentifier: "com.example.target"
        ))
        XCTAssertFalse(controller.activateExternalApplication(
            bundleIdentifier: "com.example.missing"
        ))
        XCTAssertEqual(identifiers, ["com.example.target", "com.example.missing"])
    }

    func testHidingClickerConcealsWindowWithoutRemovingItAndDeactivatesApplication() {
        let window = NSObject()
        let isWindowVisible = true
        var isWindowConcealed = false
        var deactivationCount = 0
        var activationCount = 0
        let controller = SystemApplicationController(
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
            activateClicker: { activationCount += 1 },
            activateExternal: { _ in false }
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

        SystemApplicationController.conceal(window)

        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.alphaValue, 0)
        XCTAssertTrue(window.ignoresMouseEvents)

        SystemApplicationController.reveal(window)

        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.alphaValue, 1)
        XCTAssertFalse(window.ignoresMouseEvents)
        window.orderOut(nil)
    }

    func testFailedExternalActivationLeavesClickerHiddenUntilRestore() {
        let window = NSObject()
        var isWindowConcealed = false
        var deactivationCount = 0
        var activationCount = 0
        let controller = SystemApplicationController(
            visibleWindows: { [window] },
            conceal: { _ in isWindowConcealed = true },
            reveal: { _ in isWindowConcealed = false },
            deactivateClicker: { deactivationCount += 1 },
            activateClicker: { activationCount += 1 },
            activateExternal: { _ in false }
        )

        controller.hideClicker()
        XCTAssertFalse(controller.activateExternalApplication(
            bundleIdentifier: "com.example.missing"
        ))

        XCTAssertTrue(isWindowConcealed)
        XCTAssertEqual(deactivationCount, 1)
        XCTAssertEqual(activationCount, 0)

        controller.restoreClicker()

        XCTAssertFalse(isWindowConcealed)
        XCTAssertEqual(deactivationCount, 1)
        XCTAssertEqual(activationCount, 1)
    }
}

import XCTest
@testable import Clicker

@MainActor
final class PlaybackApplicationControllerTests: XCTestCase {
    func testCaptureHappensBeforeActivationAndRestoreRunsOnce() {
        var events: [String] = []
        let controller = SystemPlaybackApplicationController(
            frontmostBundleIdentifier: {
                events.append("capture")
                return "com.example.previous"
            },
            activate: { bundleIdentifier in
                events.append("activate:\(bundleIdentifier)")
                return true
            }
        )

        let session = controller.captureAndActivate(target: "com.example.target")
        session.restore()
        session.restore()

        XCTAssertEqual(events, [
            "capture",
            "activate:com.example.target",
            "activate:com.example.previous",
        ])
    }

    func testNilTargetDoesNotActivateOrRestoreAnApplication() {
        var activatedBundleIdentifiers: [String] = []
        let controller = SystemPlaybackApplicationController(
            frontmostBundleIdentifier: { "com.example.previous" },
            activate: { bundleIdentifier in
                activatedBundleIdentifiers.append(bundleIdentifier)
                return true
            }
        )

        let session = controller.captureAndActivate(target: nil)
        session.restore()

        XCTAssertTrue(activatedBundleIdentifiers.isEmpty)
    }

    func testMissingTargetDoesNotRestoreAnApplicationThatWasNeverReplaced() {
        var activatedBundleIdentifiers: [String] = []
        let controller = SystemPlaybackApplicationController(
            frontmostBundleIdentifier: { "com.example.previous" },
            activate: { bundleIdentifier in
                activatedBundleIdentifiers.append(bundleIdentifier)
                return false
            }
        )

        let session = controller.captureAndActivate(target: "com.example.missing")
        session.restore()

        XCTAssertEqual(activatedBundleIdentifiers, ["com.example.missing"])
    }
}

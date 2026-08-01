import AppKit
import XCTest
@testable import Clicker

@MainActor
final class ExternalApplicationTrackerTests: XCTestCase {
    func testStartCapturesInitialExternalApplicationAndIsIdempotent() {
        let center = NotificationCenter()
        var initialReads = 0
        let tracker = SystemExternalApplicationTracker(
            initialFrontmostBundleIdentifier: {
                initialReads += 1
                return "com.example.editor"
            },
            notificationCenter: center,
            activatedBundleIdentifier: { $0.object as? String }
        )

        tracker.start()
        tracker.start()

        XCTAssertEqual(tracker.mostRecentExternalBundleIdentifier, "com.example.editor")
        XCTAssertEqual(initialReads, 1)
    }

    func testInitialNilEmptyAndClickerIdentifiersAreIgnored() {
        let cases: [(String, String?)] = [
            ("nil", nil),
            ("empty", ""),
            ("Clicker", "local.rayscripts.clicker"),
        ]

        for (name, initialBundleIdentifier) in cases {
            let tracker = SystemExternalApplicationTracker(
                initialFrontmostBundleIdentifier: { initialBundleIdentifier },
                notificationCenter: NotificationCenter(),
                activatedBundleIdentifier: { $0.object as? String }
            )

            tracker.start()

            XCTAssertNil(tracker.mostRecentExternalBundleIdentifier, "Expected \(name) identifier to be ignored")
        }
    }

    func testNotificationsIgnoreClickerAndEmptyIdentifiersButAcceptExternalApplication() {
        let center = NotificationCenter()
        let tracker = SystemExternalApplicationTracker(
            initialFrontmostBundleIdentifier: { "com.example.first" },
            notificationCenter: center,
            activatedBundleIdentifier: { $0.object as? String }
        )
        tracker.start()

        center.post(name: NSWorkspace.didActivateApplicationNotification, object: "")
        center.post(name: NSWorkspace.didActivateApplicationNotification, object: "local.rayscripts.clicker")
        XCTAssertEqual(tracker.mostRecentExternalBundleIdentifier, "com.example.first")

        center.post(name: NSWorkspace.didActivateApplicationNotification, object: "com.example.second")
        XCTAssertEqual(tracker.mostRecentExternalBundleIdentifier, "com.example.second")
    }

    func testClickerReactivationPreservesPreviouslyRecordedExternalApplication() {
        let center = NotificationCenter()
        let tracker = SystemExternalApplicationTracker(
            initialFrontmostBundleIdentifier: { "com.example.editor" },
            notificationCenter: center,
            activatedBundleIdentifier: { $0.object as? String }
        )
        tracker.start()

        center.post(name: NSWorkspace.didActivateApplicationNotification, object: "local.rayscripts.clicker")

        XCTAssertEqual(tracker.mostRecentExternalBundleIdentifier, "com.example.editor")
    }
}

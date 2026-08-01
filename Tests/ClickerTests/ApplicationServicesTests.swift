import XCTest
@testable import Clicker
import ClickerCore

@MainActor
final class ApplicationServicesTests: XCTestCase {
    func testSystemServicesStartTrackerOnlyOnce() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-ApplicationServices-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let tracker = StubExternalApplicationTracker()
        let state = AppState(store: ScriptStore(directory: directory), externalApplicationTracker: tracker)
        let services = ApplicationServiceCoordinator(
            state: state,
            makeStatusItem: { NSObject() },
            registerHotKeys: { [] }
        )

        services.start()
        services.start()

        XCTAssertEqual(tracker.startCallCount, 1)
    }

    func testSystemServicesAreDeferredUntilStartAndStartedOnlyOnce() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-ApplicationServices-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(store: ScriptStore(directory: directory))
        let retainedStatusItem = NSObject()
        let issue = HotKeyRegistrationIssue(shortcut: .recording, status: -50)
        var statusItemCreationCount = 0
        var hotKeyRegistrationCount = 0
        let services = ApplicationServiceCoordinator(
            state: state,
            makeStatusItem: {
                statusItemCreationCount += 1
                return retainedStatusItem
            },
            registerHotKeys: {
                hotKeyRegistrationCount += 1
                return [issue]
            }
        )

        XCTAssertEqual(statusItemCreationCount, 0)
        XCTAssertEqual(hotKeyRegistrationCount, 0)
        XCTAssertTrue(state.hotKeyRegistrationIssues.isEmpty)

        services.start()
        services.start()

        XCTAssertEqual(statusItemCreationCount, 1)
        XCTAssertEqual(hotKeyRegistrationCount, 1)
        XCTAssertEqual(state.hotKeyRegistrationIssues, [issue])
    }
}

private final class StubExternalApplicationTracker: ExternalApplicationTracking {
    var mostRecentExternalBundleIdentifier: String?
    private(set) var startCallCount = 0

    func start() {
        startCallCount += 1
    }
}

import CoreGraphics
import XCTest
@testable import Clicker
import ClickerCore

@MainActor
final class AppStateRecordingTests: XCTestCase {
    func testSuccessfulRecorderStartShowsIndicatorWithCountdownShortcutSnapshot() async {
        let custom = RecordingStopShortcut(
            keyCode: 100,
            modifierFlags: KeyCodeMap.maskControl
        )
        let store = StubStopShortcutStore(shortcut: custom)
        let recorder = StubEventRecorder(capture: .init(events: [], duration: 0))
        let countdown = ControlledCountdown()
        let indicator = StubRecordingIndicator()
        let state = makeState(
            recorder: recorder,
            countdown: countdown,
            stopStore: store,
            indicator: indicator
        )
        state.hasPermission = true

        state.toggleRecord(source: .ui)
        store.shortcut = .defaultValue
        countdown.finish()
        await Task.yield()

        XCTAssertEqual(recorder.startShortcuts, [custom])
        XCTAssertEqual(indicator.shownShortcuts, [custom])
    }

    func testRecorderStartFailureDoesNotShowIndicator() async {
        let recorder = StubEventRecorder(
            capture: .init(events: [], duration: 0),
            startResult: false
        )
        let indicator = StubRecordingIndicator()
        let application = StubApplicationController()
        let state = makeState(
            recorder: recorder,
            countdown: ImmediateCountdown(),
            application: application,
            indicator: indicator
        )
        state.hasPermission = true

        state.toggleRecord(source: .ui)
        await Task.yield()

        XCTAssertTrue(indicator.shownShortcuts.isEmpty)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(application.restoreCallCount, 1)
    }

    func testCountdownCancellationDoesNotShowAndClosesIndicator() {
        let countdown = ControlledCountdown()
        let indicator = StubRecordingIndicator()
        let application = StubApplicationController()
        let state = makeState(
            countdown: countdown,
            application: application,
            indicator: indicator
        )
        state.hasPermission = true

        state.toggleRecord(source: .ui)
        state.toggleRecord(source: .ui)

        XCTAssertTrue(indicator.shownShortcuts.isEmpty)
        XCTAssertEqual(indicator.closeCallCount, 1)
        XCTAssertEqual(application.restoreCallCount, 1)
    }

    func testCancelledCountdownCallbacksCannotBorrowReplacementCountdownState() async {
        let recorder = StubEventRecorder(capture: .init(events: [], duration: 0))
        let countdown = ControlledCountdown()
        let indicator = StubRecordingIndicator()
        let state = makeState(
            recorder: recorder,
            countdown: countdown,
            indicator: indicator
        )
        state.hasPermission = true

        state.toggleRecord(source: .ui)
        state.toggleRecord(source: .ui)
        state.toggleRecord(source: .ui)

        countdown.tick(remaining: 1, at: 0)
        await Task.yield()
        XCTAssertEqual(state.phase, .countdown(3))

        countdown.finish(at: 0)
        await Task.yield()
        XCTAssertTrue(recorder.startShortcuts.isEmpty)
        XCTAssertTrue(indicator.shownShortcuts.isEmpty)
        XCTAssertEqual(state.phase, .countdown(3))

        countdown.finish(at: 1)
        await Task.yield()
        XCTAssertEqual(recorder.startShortcuts, [.defaultValue])
        XCTAssertEqual(indicator.shownShortcuts, [.defaultValue])
        XCTAssertEqual(state.phase, .recording)
    }

    func testUIStopClosesIndicator() async {
        let indicator = StubRecordingIndicator()
        let application = StubApplicationController()
        let state = makeState(
            countdown: ImmediateCountdown(),
            application: application,
            indicator: indicator
        )
        state.hasPermission = true
        state.toggleRecord(source: .ui)
        await Task.yield()

        state.toggleRecord(source: .ui)

        XCTAssertEqual(indicator.closeCallCount, 1)
        XCTAssertEqual(application.restoreCallCount, 1)
    }

    func testMenuBarStopClosesIndicator() {
        let indicator = StubRecordingIndicator()
        let application = StubApplicationController()
        let state = makeState(application: application, indicator: indicator)
        state.phase = .recording

        state.stopRecordingFromMenuBar(
            cutoff: RecordingCutoff(eventCount: 0, duration: 0)
        )

        XCTAssertEqual(indicator.closeCallCount, 1)
        XCTAssertEqual(application.restoreCallCount, 1)
    }

    func testStopRequestClosesIndicator() async {
        let recorder = StubEventRecorder(capture: .init(events: [], duration: 0))
        let indicator = StubRecordingIndicator()
        let application = StubApplicationController()
        let state = makeState(
            recorder: recorder,
            application: application,
            indicator: indicator
        )
        state.setUp()
        state.phase = .recording

        recorder.onStopRequest?()
        await Task.yield()

        XCTAssertEqual(indicator.closeCallCount, 1)
        XCTAssertEqual(application.restoreCallCount, 1)
    }

    func testTapFailureClosesIndicator() async {
        let recorder = StubEventRecorder(capture: .init(events: [], duration: 0))
        let indicator = StubRecordingIndicator()
        let application = StubApplicationController()
        let state = makeState(
            recorder: recorder,
            application: application,
            indicator: indicator
        )
        state.setUp()
        state.phase = .recording

        recorder.onTapFailure?()
        await Task.yield()

        XCTAssertEqual(indicator.closeCallCount, 1)
        XCTAssertEqual(application.restoreCallCount, 1)
    }

    func testRecordingEntryAvailabilityFollowsPhase() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-RecordingAvailability-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(
            store: ScriptStore(directory: directory),
            recorder: StubEventRecorder(capture: RecordingCapture(events: [], duration: 0)),
            countdown: ImmediateCountdown(),
            application: StubApplicationController()
        )

        state.phase = .idle
        XCTAssertTrue(state.canStartRecording)
        state.phase = .countdown(3)
        XCTAssertFalse(state.canStartRecording)
        state.phase = .recording
        XCTAssertFalse(state.canStartRecording)
        state.phase = .playing(iteration: 1, currentBlockID: nil)
        XCTAssertFalse(state.canStartRecording)
    }

    func testRecordingSnapshotsTargetThenShowsHidesAndActivatesInOrder() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-CountdownOrder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var calls: [String] = []
        let tracker = StubExternalApplicationTracker(
            mostRecentExternalBundleIdentifier: "com.example.target",
            onRead: { calls.append("targetSnapshot") }
        )
        let stopStore = StubStopShortcutStore(
            shortcut: .defaultValue,
            onRead: { calls.append("shortcutSnapshot") }
        )
        let countdown = ImmediateCountdown(onShow: {
            calls.append("showCountdown")
        })
        let application = StubApplicationController(
            activationResult: true,
            onCall: { calls.append($0) }
        )
        let state = AppState(
            store: ScriptStore(directory: directory),
            recorder: StubEventRecorder(
                capture: RecordingCapture(events: [], duration: 0)
            ),
            countdown: countdown,
            application: application,
            externalApplicationTracker: tracker,
            stopShortcutStore: stopStore
        )
        state.hasPermission = true

        state.toggleRecord(source: .ui)

        XCTAssertEqual(
            calls,
            [
                "targetSnapshot",
                "shortcutSnapshot",
                "showCountdown",
                "hide",
                "activate:com.example.target",
            ]
        )
    }

    func testRecordingWithoutRecentTargetHidesWithoutActivatingApplication() {
        let application = StubApplicationController()
        let state = makeState(
            application: application,
            tracker: StubExternalApplicationTracker(
                mostRecentExternalBundleIdentifier: nil
            )
        )
        state.hasPermission = true

        state.toggleRecord(source: .ui)

        XCTAssertEqual(application.calls, ["hide"])
        XCTAssertTrue(application.activatedBundleIdentifiers.isEmpty)
        XCTAssertEqual(state.phase, .countdown(3))
    }

    func testFailedTargetActivationDoesNotPreventCountdownFromStartingRecorder() async {
        let recorder = StubEventRecorder(capture: .init(events: [], duration: 0))
        let countdown = ControlledCountdown()
        let application = StubApplicationController(activationResult: false)
        let state = makeState(
            recorder: recorder,
            countdown: countdown,
            application: application,
            tracker: StubExternalApplicationTracker(
                mostRecentExternalBundleIdentifier: "com.example.missing"
            )
        )
        state.hasPermission = true

        state.toggleRecord(source: .ui)
        countdown.finish()
        await Task.yield()

        XCTAssertEqual(application.activatedBundleIdentifiers, ["com.example.missing"])
        XCTAssertEqual(recorder.startShortcuts, [.defaultValue])
        XCTAssertEqual(state.phase, .recording)
    }

    func testTrackerMutationDuringCountdownDoesNotChangeSavedRecordingTarget() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-AppStateTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let recorder = StubEventRecorder(
            capture: RecordingCapture(events: [], duration: 0.2)
        )
        let countdown = ControlledCountdown()
        let tracker = StubExternalApplicationTracker(
            mostRecentExternalBundleIdentifier: "com.example.original"
        )
        let application = StubApplicationController()
        let state = AppState(
            store: ScriptStore(directory: directory),
            recorder: recorder,
            countdown: countdown,
            application: application,
            externalApplicationTracker: tracker
        )
        state.hasPermission = true

        state.toggleRecord(source: .ui)
        tracker.mostRecentExternalBundleIdentifier = "com.example.replacement"
        countdown.finish()
        await Task.yield()

        XCTAssertEqual(state.phase, .recording)

        state.toggleRecord(source: .ui)

        let script = try XCTUnwrap(state.scripts.first)
        XCTAssertTrue(script.blocks.isEmpty)
        XCTAssertEqual(script.trailingDelay, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(script.targetBundleIdentifier, "com.example.original")
    }

    func testMenuBarStopUsesTimestampCutoffBeforeBuildingScript() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-AppStateTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let recorder = StubEventRecorder(
            capture: RecordingCapture(
                events: [
                    RecordedEvent(t: 0.1, kind: .leftDown),
                    RecordedEvent(t: 0.2, kind: .leftUp),
                    RecordedEvent(t: 0.8, kind: .mouseMove),
                ],
                duration: 1
            ),
            cutoff: RecordingCutoff(eventCount: 2, duration: 0.7)
        )
        let state = AppState(
            store: ScriptStore(directory: directory),
            recorder: recorder,
            countdown: ImmediateCountdown(),
            application: StubApplicationController()
        )
        state.phase = .recording

        let cutoff = try XCTUnwrap(state.establishMenuBarCutoff(at: 9_000))

        XCTAssertEqual(recorder.cutoffTimestamps, [9_000])
        XCTAssertEqual(state.phase, .recording)
        XCTAssertTrue(state.scripts.isEmpty)

        state.stopRecordingFromMenuBar(cutoff: cutoff)

        let script = try XCTUnwrap(state.scripts.first)
        XCTAssertFalse(script.blocks.contains { block in
            if case .move = block { return true }
            return false
        })
        XCTAssertEqual(
            BlockExpander.plan(
                blocks: script.blocks,
                trailingDelay: script.trailingDelay
            ).duration,
            0.7,
            accuracy: 0.000_001
        )
    }

    func testDelayedTapFailureAfterRecordingStoppedDoesNotSaveAgain() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-AppStateTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let recorder = StubEventRecorder(capture: RecordingCapture(
            events: [
                RecordedEvent(t: 0.1, kind: .leftDown),
                RecordedEvent(t: 0.2, kind: .leftUp),
            ],
            duration: 0.2
        ))
        let state = AppState(
            store: ScriptStore(directory: directory),
            recorder: recorder,
            countdown: ImmediateCountdown(),
            application: StubApplicationController()
        )
        state.setUp()
        state.phase = .idle

        recorder.onTapFailure?()
        await Task.yield()

        XCTAssertEqual(recorder.stopCallCount, 0)
        XCTAssertTrue(state.scripts.isEmpty)
    }

    func testEscapeStopRequestFinishesActiveRecordingAndRestoresClicker() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-EscapeStop-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = StubEventRecorder(
            capture: RecordingCapture(events: [], duration: 0.2)
        )
        let application = StubApplicationController()
        let state = AppState(
            store: ScriptStore(directory: directory),
            recorder: recorder,
            countdown: ImmediateCountdown(),
            application: application
        )
        state.setUp()
        state.phase = .recording

        recorder.onStopRequest?()
        await Task.yield()

        XCTAssertEqual(recorder.stopCallCount, 1)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(application.calls, ["restore"])
        XCTAssertEqual(state.scripts.first?.trailingDelay, 0.2)
    }

    private func makeState(
        recorder: StubEventRecorder = StubEventRecorder(
            capture: .init(events: [], duration: 0)
        ),
        countdown: CountdownPresenting = ControlledCountdown(),
        application: StubApplicationController? = nil,
        tracker: StubExternalApplicationTracker = StubExternalApplicationTracker(
            mostRecentExternalBundleIdentifier: nil
        ),
        stopStore: RecordingStopShortcutProviding = StubStopShortcutStore(
            shortcut: .defaultValue
        ),
        indicator: StubRecordingIndicator? = nil
    ) -> AppState {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-IndicatorLifecycle-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppState(
            store: ScriptStore(directory: directory),
            recorder: recorder,
            countdown: countdown,
            application: application ?? StubApplicationController(),
            externalApplicationTracker: tracker,
            stopShortcutStore: stopStore,
            recordingIndicator: indicator ?? StubRecordingIndicator()
        )
    }
}

private final class StubEventRecorder: EventRecording {
    var onTapFailure: (() -> Void)?
    var onStopRequest: (() -> Void)?
    private let capture: RecordingCapture
    private let cutoffValue: RecordingCutoff
    private(set) var cutoffTimestamps: [CGEventTimestamp] = []
    private(set) var startShortcuts: [RecordingStopShortcut] = []
    private(set) var stopCallCount = 0

    init(
        capture: RecordingCapture,
        cutoff: RecordingCutoff = RecordingCutoff(eventCount: 0, duration: 0),
        startResult: Bool = true
    ) {
        self.capture = capture
        cutoffValue = cutoff
        self.startResult = startResult
    }

    private let startResult: Bool

    func start(stopShortcut: RecordingStopShortcut) -> Bool {
        startShortcuts.append(stopShortcut)
        return startResult
    }
    func stop() -> RecordingCapture {
        stopCallCount += 1
        return capture
    }

    func cutoff(at timestamp: CGEventTimestamp) -> RecordingCutoff {
        cutoffTimestamps.append(timestamp)
        return cutoffValue
    }
}

private final class StubStopShortcutStore: RecordingStopShortcutProviding {
    var shortcut: RecordingStopShortcut {
        get {
            onRead()
            return storedShortcut
        }
        set {
            storedShortcut = newValue
        }
    }

    private var storedShortcut: RecordingStopShortcut
    private let onRead: () -> Void

    init(shortcut: RecordingStopShortcut, onRead: @escaping () -> Void = {}) {
        storedShortcut = shortcut
        self.onRead = onRead
    }
}

private final class StubRecordingIndicator: RecordingIndicatorPresenting {
    private(set) var shownShortcuts: [RecordingStopShortcut] = []
    private(set) var closeCallCount = 0

    func show(shortcut: RecordingStopShortcut) {
        shownShortcuts.append(shortcut)
    }

    func close() {
        closeCallCount += 1
    }
}

private final class ControlledCountdown: CountdownPresenting {
    private let onShow: () -> Void
    private var onTicks: [(Int) -> Void] = []
    private var onFinishes: [() -> Void] = []

    init(onShow: @escaping () -> Void = {}) {
        self.onShow = onShow
    }

    func show(
        seconds _: Int,
        onTick: @escaping (Int) -> Void,
        onFinish: @escaping () -> Void
    ) {
        onShow()
        onTicks.append(onTick)
        onFinishes.append(onFinish)
    }

    func close() {}

    func tick(remaining: Int, at index: Int) {
        onTicks[index](remaining)
    }

    func finish(at index: Int = 0) {
        onFinishes[index]()
    }
}

private final class ImmediateCountdown: CountdownPresenting {
    private let onShow: () -> Void

    init(onShow: @escaping () -> Void = {}) {
        self.onShow = onShow
    }

    func show(
        seconds _: Int,
        onTick _: @escaping (Int) -> Void,
        onFinish: @escaping () -> Void
    ) {
        onShow()
        onFinish()
    }

    func close() {}
}

@MainActor
private final class StubApplicationController: ApplicationControlling {
    private let activationResult: Bool
    private let onCall: (String) -> Void
    private(set) var calls: [String] = []
    private(set) var activatedBundleIdentifiers: [String] = []
    private(set) var restoreCallCount = 0

    init(
        activationResult: Bool = false,
        onCall: @escaping (String) -> Void = { _ in }
    ) {
        self.activationResult = activationResult
        self.onCall = onCall
    }

    func activateExternalApplication(bundleIdentifier: String) -> Bool {
        activatedBundleIdentifiers.append(bundleIdentifier)
        onCall("activate:\(bundleIdentifier)")
        return activationResult
    }

    func hideClicker() {
        calls.append("hide")
        onCall("hide")
    }

    func restoreClicker() {
        restoreCallCount += 1
        calls.append("restore")
        onCall("restore")
    }
}

private final class StubExternalApplicationTracker: ExternalApplicationTracking {
    var mostRecentExternalBundleIdentifier: String? {
        get {
            onRead()
            return storedBundleIdentifier
        }
        set {
            storedBundleIdentifier = newValue
        }
    }

    private var storedBundleIdentifier: String?
    private let onRead: () -> Void

    init(
        mostRecentExternalBundleIdentifier: String?,
        onRead: @escaping () -> Void = {}
    ) {
        storedBundleIdentifier = mostRecentExternalBundleIdentifier
        self.onRead = onRead
    }

    func start() {}
}

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
        let state = makeState(
            recorder: recorder,
            countdown: ImmediateCountdown(),
            indicator: indicator
        )
        state.hasPermission = true

        state.toggleRecord(source: .ui)
        await Task.yield()

        XCTAssertTrue(indicator.shownShortcuts.isEmpty)
        XCTAssertEqual(state.phase, .idle)
    }

    func testCountdownCancellationDoesNotShowAndClosesIndicator() {
        let countdown = ControlledCountdown()
        let indicator = StubRecordingIndicator()
        let state = makeState(countdown: countdown, indicator: indicator)
        state.hasPermission = true

        state.toggleRecord(source: .ui)
        state.toggleRecord(source: .ui)

        XCTAssertTrue(indicator.shownShortcuts.isEmpty)
        XCTAssertEqual(indicator.closeCallCount, 1)
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
        let state = makeState(
            countdown: ImmediateCountdown(),
            indicator: indicator
        )
        state.hasPermission = true
        state.toggleRecord(source: .ui)
        await Task.yield()

        state.toggleRecord(source: .ui)

        XCTAssertEqual(indicator.closeCallCount, 1)
    }

    func testMenuBarStopClosesIndicator() {
        let indicator = StubRecordingIndicator()
        let state = makeState(indicator: indicator)
        state.phase = .recording

        state.stopRecordingFromMenuBar(
            cutoff: RecordingCutoff(eventCount: 0, duration: 0)
        )

        XCTAssertEqual(indicator.closeCallCount, 1)
    }

    func testStopRequestClosesIndicator() async {
        let recorder = StubEventRecorder(capture: .init(events: [], duration: 0))
        let indicator = StubRecordingIndicator()
        let state = makeState(recorder: recorder, indicator: indicator)
        state.setUp()
        state.phase = .recording

        recorder.onStopRequest?()
        await Task.yield()

        XCTAssertEqual(indicator.closeCallCount, 1)
    }

    func testTapFailureClosesIndicator() async {
        let recorder = StubEventRecorder(capture: .init(events: [], duration: 0))
        let indicator = StubRecordingIndicator()
        let state = makeState(recorder: recorder, indicator: indicator)
        state.setUp()
        state.phase = .recording

        recorder.onTapFailure?()
        await Task.yield()

        XCTAssertEqual(indicator.closeCallCount, 1)
    }

    func testRecordingEntryAvailabilityFollowsPhase() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-RecordingAvailability-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(
            store: ScriptStore(directory: directory),
            recorder: StubEventRecorder(capture: RecordingCapture(events: [], duration: 0)),
            countdown: ImmediateCountdown(),
            application: StubRecordingApplication(targetBundleIdentifier: nil)
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

    func testCountdownPanelIsShownBeforeLastMainWindowIsHidden() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-CountdownOrder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var calls: [String] = []
        let countdown = ImmediateCountdown(onShow: {
            calls.append("showCountdown")
        })
        let application = StubRecordingApplication(
            targetBundleIdentifier: "com.example.target",
            onCall: { calls.append($0) }
        )
        let state = AppState(
            store: ScriptStore(directory: directory),
            recorder: StubEventRecorder(
                capture: RecordingCapture(events: [], duration: 0)
            ),
            countdown: countdown,
            application: application
        )
        state.hasPermission = true

        state.toggleRecord(source: .ui)

        XCTAssertEqual(
            calls,
            ["frontmostApplication", "showCountdown", "hide"]
        )
    }

    func testTargetIsCapturedBeforeHideAndUIStopSavesTrailingOnlyRecording() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-AppStateTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let recorder = StubEventRecorder(
            capture: RecordingCapture(events: [], duration: 0.2)
        )
        let countdown = ImmediateCountdown()
        let application = StubRecordingApplication(
            targetBundleIdentifier: "com.example.target"
        )
        let state = AppState(
            store: ScriptStore(directory: directory),
            recorder: recorder,
            countdown: countdown,
            application: application
        )
        state.hasPermission = true

        state.toggleRecord(source: .ui)
        await Task.yield()

        XCTAssertEqual(application.calls, ["frontmostApplication", "hide"])
        XCTAssertEqual(state.phase, .recording)
        XCTAssertEqual(recorder.startShortcuts, [.defaultValue])

        state.toggleRecord(source: .ui)

        let script = try XCTUnwrap(state.scripts.first)
        XCTAssertTrue(script.blocks.isEmpty)
        XCTAssertEqual(script.trailingDelay, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(script.targetBundleIdentifier, "com.example.target")
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
            application: StubRecordingApplication(targetBundleIdentifier: nil)
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
            application: StubRecordingApplication(targetBundleIdentifier: nil)
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
        let application = StubRecordingApplication(targetBundleIdentifier: nil)
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
            application: StubRecordingApplication(targetBundleIdentifier: nil),
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
    var shortcut: RecordingStopShortcut

    init(shortcut: RecordingStopShortcut) {
        self.shortcut = shortcut
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
    private var onTicks: [(Int) -> Void] = []
    private var onFinishes: [() -> Void] = []

    func show(
        seconds _: Int,
        onTick: @escaping (Int) -> Void,
        onFinish: @escaping () -> Void
    ) {
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
private final class StubRecordingApplication: ApplicationControlling {
    private let targetBundleIdentifier: String?
    private let activationResult: Bool
    private let onCall: (String) -> Void
    private(set) var calls: [String] = []
    private(set) var activatedBundleIdentifiers: [String] = []

    init(
        targetBundleIdentifier: String?,
        activationResult: Bool = false,
        onCall: @escaping (String) -> Void = { _ in }
    ) {
        self.targetBundleIdentifier = targetBundleIdentifier
        self.activationResult = activationResult
        self.onCall = onCall
    }

    func frontmostApplicationBundleIdentifier() -> String? {
        calls.append("frontmostApplication")
        onCall("frontmostApplication")
        return targetBundleIdentifier
    }

    func activateExternalApplication(bundleIdentifier: String) -> Bool {
        activatedBundleIdentifiers.append(bundleIdentifier)
        return activationResult
    }

    func hideClicker() {
        calls.append("hide")
        onCall("hide")
    }

    func restoreClicker() {
        calls.append("restore")
        onCall("restore")
    }
}

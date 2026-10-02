import AppKit
import CoreGraphics
import XCTest
@testable import Clicker
import ClickerCore

@MainActor
final class AppStatePlaybackTests: XCTestCase {
    func testScriptShortcutStartsExactScriptWithoutHidingOrRestoringClicker() async {
        let first = playableScript(targetBundleIdentifier: "com.example.first")
        let second = Script(
            name: "second",
            blocks: [.wait(WaitBlock(duration: 1))],
            targetBundleIdentifier: "com.example.second"
        )
        let context = makeContext(script: first, recentTarget: "com.example.recent")
        defer { try? FileManager.default.removeItem(at: context.directory) }
        context.state.scripts = [first, second]
        context.state.selectedScriptID = first.id

        context.state.playScriptFromShortcut(id: second.id)

        XCTAssertEqual(context.playback.playedScripts, [second])
        XCTAssertTrue(context.application.activationAttempts.isEmpty)
        XCTAssertEqual(context.application.hideCallCount, 0)
        XCTAssertEqual(context.state.selectedScriptID, first.id)

        context.playback.finish(session: 0)
        await Task.yield()
        XCTAssertEqual(context.application.restoreCallCount, 0)
    }

    func testScriptShortcutIgnoresUnknownUnplayableAndBusyRequests() {
        let playable = playableScript()
        let empty = Script(name: "empty")
        let context = makeContext(script: playable)
        defer { try? FileManager.default.removeItem(at: context.directory) }
        context.state.scripts = [playable, empty]

        context.state.playScriptFromShortcut(id: UUID())
        context.state.playScriptFromShortcut(id: empty.id)
        XCTAssertTrue(context.playback.playedScripts.isEmpty)

        context.state.playScriptFromShortcut(id: playable.id)
        context.state.playScriptFromShortcut(id: playable.id)
        XCTAssertEqual(context.playback.playedScripts, [playable])
    }

    func testTrailingOnlyScriptCanStartPlayback() {
        let context = makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let script = Script(name: "trailing-only", trailingDelay: 0.5)
        context.state.scripts = [script]
        context.state.selectedScriptID = script.id

        context.state.togglePlay()

        XCTAssertEqual(context.playback.playedScripts, [script])
        XCTAssertEqual(context.state.phase, .playing(iteration: 1, currentBlockID: nil))
    }

    func testFreePlaybackIgnoresRecordedAndRecentApplications() {
        let script = playableScript(targetBundleIdentifier: "com.example.saved")
        let context = makeContext(script: script, recentTarget: "com.example.recent")
        defer { try? FileManager.default.removeItem(at: context.directory) }
        context.state.togglePlay()
        XCTAssertEqual(context.calls, ["hide", "play"])
        XCTAssertTrue(context.application.activationAttempts.isEmpty)
    }

    func testOptionalStartApplicationActivatesOnlyOnceBeforePlayback() {
        var script = playableScript(targetBundleIdentifier: "com.example.saved")
        script.startApplicationBeforePlayback = true
        let context = makeContext(script: script, recentTarget: "com.example.recent")
        defer { try? FileManager.default.removeItem(at: context.directory) }
        context.state.togglePlay()
        XCTAssertEqual(context.calls, ["hide", "activate:com.example.saved", "play"])
        XCTAssertEqual(context.application.activationAttempts, ["com.example.saved"])
        XCTAssertNil(context.state.pendingPlaybackStart)
    }

    func testFailedOptionalSwitchRequiresExplicitContinueAndNeverFallsBack() {
        var script = playableScript(targetBundleIdentifier: "com.example.saved")
        script.startApplicationBeforePlayback = true
        let context = makeContext(script: script, recentTarget: "com.example.recent",
                                  activationResults: ["com.example.saved": false])
        defer { try? FileManager.default.removeItem(at: context.directory) }
        context.state.togglePlay()
        XCTAssertTrue(context.playback.playedScripts.isEmpty)
        XCTAssertEqual(context.application.activationAttempts, ["com.example.saved"])
        XCTAssertEqual(context.state.pendingPlaybackStart?.appIdentifier, "com.example.saved")
        context.state.continuePendingPlayback()
        XCTAssertEqual(context.playback.playedScripts, [script])
        XCTAssertEqual(context.application.activationAttempts, ["com.example.saved"])
        XCTAssertNil(context.state.pendingPlaybackStart)
    }

    func testCancelFailedOptionalSwitchDoesNotSendInput() {
        var script = playableScript(targetBundleIdentifier: "com.example.saved")
        script.startApplicationBeforePlayback = true
        let context = makeContext(script: script, activationResults: ["com.example.saved": false])
        defer { try? FileManager.default.removeItem(at: context.directory) }
        context.state.togglePlay()
        context.state.cancelPendingPlayback()
        XCTAssertTrue(context.playback.playedScripts.isEmpty)
        XCTAssertNil(context.state.pendingPlaybackStart)
        XCTAssertEqual(context.state.phase, .idle)
    }

    func testMissingEmptyAndSelfOptionalTargetRequireChoice() {
        for target: String? in [nil, "", "local.rayscripts.clicker"] {
            var script = playableScript(targetBundleIdentifier: target)
            script.startApplicationBeforePlayback = true
            let context = makeContext(script: script, recentTarget: "com.example.recent")
            defer { try? FileManager.default.removeItem(at: context.directory) }
            context.state.togglePlay()
            XCTAssertTrue(context.application.activationAttempts.isEmpty)
            XCTAssertTrue(context.playback.playedScripts.isEmpty)
            XCTAssertNotNil(context.state.pendingPlaybackStart)
        }
    }

    func testFreePlaybackWithoutTargetHidesAndStartsEngine() {
        let script = playableScript()
        let context = makeContext(script: script)
        defer { try? FileManager.default.removeItem(at: context.directory) }
        context.state.togglePlay()
        XCTAssertTrue(context.application.activationAttempts.isEmpty)
        XCTAssertEqual(context.calls, ["hide", "play"])
        XCTAssertEqual(context.playback.playedScripts, [script])
    }

    func testOptionalStartWaitsForVerifiedForegroundAndCanCancel() {
        var script = playableScript(targetBundleIdentifier: "com.example.saved")
        script.startApplicationBeforePlayback = true
        let context = makeContext(script: script)
        defer { try? FileManager.default.removeItem(at: context.directory) }
        context.application.deferVerification = true
        context.state.togglePlay()
        XCTAssertTrue(context.state.isPreparingPlayback)
        XCTAssertFalse(context.state.canEditScripts)
        XCTAssertTrue(context.playback.playedScripts.isEmpty)
        context.state.togglePlay()
        context.application.finishVerification(true)
        XCTAssertTrue(context.playback.playedScripts.isEmpty)
        XCTAssertFalse(context.state.isPreparingPlayback)
    }

    func testOptionalForegroundVerificationFailureOffersFreePlayback() {
        var script = playableScript(targetBundleIdentifier: "com.example.saved")
        script.startApplicationBeforePlayback = true
        let context = makeContext(script: script)
        defer { try? FileManager.default.removeItem(at: context.directory) }
        context.application.deferVerification = true
        context.state.togglePlay()
        context.application.finishVerification(false)
        XCTAssertTrue(context.playback.playedScripts.isEmpty)
        XCTAssertNotNil(context.state.pendingPlaybackStart)
    }

    func testSelectedRangeTrialIgnoresInfiniteRepeatAndExcludesOtherActions() {
        let first = ActionBlock.wait(WaitBlock(duration: 1))
        let second = ActionBlock.wait(WaitBlock(duration: 2)).withStartOffset(1)
        let script = Script(name: "trial", blocks: [first, second], repeatForever: true)
        let context = makeContext(script: script)
        defer { try? FileManager.default.removeItem(at: context.directory) }
        context.state.trialActions(scriptID: script.id, blockIDs: [second.id])
        let played = context.playback.playedScripts.first
        XCTAssertEqual(played?.blocks.map(\.id), [second.id])
        XCTAssertEqual(played?.blocks.first?.startOffset, 0)
        XCTAssertEqual(played?.repeatCount, 1)
        XCTAssertEqual(played?.repeatForever, false)
        XCTAssertEqual(context.state.scripts, [script])
    }

    func testNaturalCompletionRestoresClickerExactlyOnce() async {
        let context = makeContext(script: playableScript())
        defer { try? FileManager.default.removeItem(at: context.directory) }
        context.state.togglePlay()

        context.playback.finish(session: 0)
        await Task.yield()
        context.playback.finish(session: 0)
        await Task.yield()

        XCTAssertEqual(context.application.restoreCallCount, 1)
        XCTAssertEqual(context.state.phase, .idle)
    }

    func testExplicitStopRestoresClickerExactlyOnce() {
        let context = makeContext(script: playableScript())
        defer { try? FileManager.default.removeItem(at: context.directory) }
        context.state.togglePlay()

        context.state.togglePlay()

        XCTAssertEqual(context.playback.stopCallCount, 1)
        XCTAssertEqual(context.application.restoreCallCount, 1)
        XCTAssertEqual(context.state.phase, .idle)
    }

    func testTerminationStopsActivePlaybackSynchronouslyOnlyOnce() {
        let context = makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let script = Script(
            name: "wait",
            blocks: [.wait(WaitBlock(duration: 1))]
        )
        context.state.scripts = [script]
        context.state.selectedScriptID = script.id
        context.state.setUp()
        context.state.togglePlay()

        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)

        XCTAssertEqual(context.playback.stopCallCount, 1)
        XCTAssertEqual(context.application.restoreCallCount, 1)
        XCTAssertEqual(context.state.phase, .idle)
    }

    func testLateFinishFromStoppedPlaybackDoesNotFinishReplacement() async {
        let context = makeContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let script = Script(
            name: "replaceable",
            blocks: [.wait(WaitBlock(duration: 1))]
        )
        context.state.scripts = [script]
        context.state.selectedScriptID = script.id

        context.state.togglePlay()
        context.state.togglePlay()
        context.state.togglePlay()
        context.playback.finish(session: 0)
        await Task.yield()

        XCTAssertEqual(context.playback.playedScripts, [script, script])
        XCTAssertEqual(context.playback.stopCallCount, 1)
        XCTAssertEqual(context.application.restoreCallCount, 1)
        XCTAssertEqual(context.state.phase, .playing(iteration: 1, currentBlockID: nil))
    }

    func testPlaybackRejectsLibraryMutationsAndKeepsItsStartingSnapshot() {
        let script = Script(
            name: "original",
            blocks: [.wait(WaitBlock(duration: 1))]
        )
        let store = PlaybackStubScriptStore(scripts: [script])
        let playback = StubPlaybackEngine()
        let state = AppState(
            store: store,
            recorder: NoopEventRecorder(),
            countdown: NoopCountdown(),
            application: NoopRecordingApplication(),
            playbackEngine: playback,
            playbackIndicator: SilentPlaybackIndicator()
        )
        state.hasPermission = true
        state.selectedScriptID = script.id

        state.togglePlay()
        var renamed = script
        renamed.name = "changed"
        XCTAssertFalse(state.update(renamed))
        XCTAssertFalse(state.create(Script(name: "new")))
        state.duplicateScript(id: script.id)
        state.deleteScript(id: script.id)

        XCTAssertFalse(state.canEditScripts)
        XCTAssertEqual(state.scripts, [script])
        XCTAssertTrue(store.savedScripts.isEmpty)
        XCTAssertTrue(store.deletedIDs.isEmpty)
        XCTAssertEqual(playback.playedScripts, [script])

        state.togglePlay()

        XCTAssertTrue(state.canEditScripts)
    }

    private func playableScript(targetBundleIdentifier: String? = nil) -> Script {
        Script(
            name: "playable",
            blocks: [.wait(WaitBlock(duration: 1))],
            targetBundleIdentifier: targetBundleIdentifier
        )
    }

    private func makeContext(
        script: Script? = nil,
        recentTarget: String? = nil,
        activationResults: [String: Bool] = [:]
    ) -> PlaybackTestContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-AppStatePlaybackTests-\(UUID().uuidString)")
        let calls = PlaybackCallLog()
        let playback = StubPlaybackEngine(calls: calls)
        let application = StubPlaybackApplication(
            calls: calls,
            activationResults: activationResults
        )
        let tracker = StubPlaybackExternalApplicationTracker(
            bundleIdentifier: recentTarget
        )
        let state = AppState(
            store: ScriptStore(directory: directory),
            recorder: NoopEventRecorder(),
            countdown: NoopCountdown(),
            application: application,
            externalApplicationTracker: tracker,
            playbackEngine: playback,
            playbackIndicator: SilentPlaybackIndicator()
        )
        state.hasPermission = true
        if let script {
            state.scripts = [script]
            state.selectedScriptID = script.id
        }
        return PlaybackTestContext(
            state: state,
            playback: playback,
            application: application,
            tracker: tracker,
            directory: directory,
            callLog: calls
        )
    }
}

@MainActor
private struct PlaybackTestContext {
    let state: AppState
    let playback: StubPlaybackEngine
    let application: StubPlaybackApplication
    let tracker: StubPlaybackExternalApplicationTracker
    let directory: URL
    let callLog: PlaybackCallLog

    var calls: [String] { callLog.calls }
}

private final class PlaybackCallLog {
    var calls: [String] = []
}

private final class PlaybackStubScriptStore: ScriptPersisting {
    private let scripts: [Script]
    private(set) var savedScripts: [Script] = []
    private(set) var deletedIDs: [UUID] = []

    init(scripts: [Script]) {
        self.scripts = scripts
    }

    func loadAll() -> ScriptStoreLoadResult {
        ScriptStoreLoadResult(scripts: scripts, issues: [])
    }

    func save(_ script: Script) throws {
        savedScripts.append(script)
    }

    func delete(id: UUID) throws {
        deletedIDs.append(id)
    }
}

@MainActor
private final class StubPlaybackEngine: PlaybackControlling {
    private(set) var playedScripts: [Script] = []
    private(set) var stopCallCount = 0
    private var finishes: [() -> Void] = []
    private let calls: PlaybackCallLog?

    init(calls: PlaybackCallLog? = nil) {
        self.calls = calls
    }

    func play(
        script: Script,
        onIteration _: @escaping (Int) -> Void,
        onBlock _: @escaping (UUID?) -> Void,
        onFinish: @escaping () -> Void
    ) {
        calls?.calls.append("play")
        playedScripts.append(script)
        finishes.append(onFinish)
    }

    func stop() {
        calls?.calls.append("stop")
        stopCallCount += 1
    }

    func finish(session index: Int) {
        finishes[index]()
    }
}

@MainActor
private final class StubPlaybackApplication: ApplicationControlling {
    private let calls: PlaybackCallLog
    private let activationResults: [String: Bool]
    private(set) var activationAttempts: [String] = []
    private(set) var hideCallCount = 0
    private(set) var restoreCallCount = 0
    var onHide: () -> Void = {}
    var deferVerification = false
    private var verification: ((Bool) -> Void)?
    func verifyExternalApplicationActivation(bundleIdentifier: String, completion: @escaping (Bool) -> Void) {
        if deferVerification { verification = completion } else { completion(true) }
    }
    func finishVerification(_ result: Bool) { verification?(result) }


    init(calls: PlaybackCallLog, activationResults: [String: Bool]) {
        self.calls = calls
        self.activationResults = activationResults
    }

    func activateExternalApplication(bundleIdentifier: String) -> Bool {
        activationAttempts.append(bundleIdentifier)
        calls.calls.append("activate:\(bundleIdentifier)")
        return activationResults[bundleIdentifier] ?? true
    }

    func hideClicker() {
        hideCallCount += 1
        calls.calls.append("hide")
        onHide()
    }

    func restoreClicker() {
        restoreCallCount += 1
        calls.calls.append("restore")
    }
}

private final class StubPlaybackExternalApplicationTracker: ExternalApplicationTracking {
    var bundleIdentifier: String?

    var mostRecentExternalBundleIdentifier: String? { bundleIdentifier }

    init(bundleIdentifier: String?) {
        self.bundleIdentifier = bundleIdentifier
    }

    func start() {}
}

private final class NoopEventRecorder: EventRecording {
    var onTapFailure: (() -> Void)?
    var onStopRequest: (() -> Void)?

    func start(stopShortcut _: RecordingStopShortcut) -> Bool { true }
    func stop() -> RecordingCapture { RecordingCapture(events: [], duration: 0) }
    func cutoff(at _: CGEventTimestamp) -> RecordingCutoff {
        RecordingCutoff(eventCount: 0, duration: 0)
    }
}

private final class NoopCountdown: CountdownPresenting {
    func show(
        seconds _: Int,
        onTick _: @escaping (Int) -> Void,
        onFinish _: @escaping () -> Void
    ) {}

    func close() {}
}

@MainActor
private final class NoopRecordingApplication: ApplicationControlling {
    var activationResult = false
    private(set) var activatedBundleIdentifiers: [String] = []

    func activateExternalApplication(bundleIdentifier: String) -> Bool {
        activatedBundleIdentifiers.append(bundleIdentifier)
        return activationResult
    }
    func hideClicker() {}
    func restoreClicker() {}
}

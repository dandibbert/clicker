import AppKit
import CoreGraphics
import XCTest
@testable import Clicker
import ClickerCore

@MainActor
final class RecordingRecoveryTests: XCTestCase {
    func testFailedSaveRetainsExactDraftAfterAlertDismissalAndRetry() async throws {
        let context = Context()
        context.store.fails = true
        await context.startRecording()
        context.state.toggleRecord(source: .ui)
        let draft = try XCTUnwrap(context.state.unsavedRecording)
        XCTAssertEqual(draft.targetBundleIdentifier, "com.example.target")
        XCTAssertEqual(BlockExpander.plan(for: draft).duration, 0.8, accuracy: 0.000_001)
        XCTAssertFalse(draft.blocks.isEmpty)
        XCTAssertTrue(context.state.scripts.isEmpty)
        XCTAssertNil(context.state.selectedScriptID)
        context.state.persistenceIssue = nil
        XCTAssertEqual(context.state.unsavedRecording, draft)

        context.store.fails = false
        XCTAssertTrue(context.state.retrySavingRecording())
        XCTAssertEqual(context.store.saved, [draft])
        XCTAssertEqual(context.state.scripts, [draft])
        XCTAssertEqual(context.state.selectedScriptID, draft.id)
        XCTAssertNil(context.state.unsavedRecording)
        XCTAssertFalse(context.state.retrySavingRecording())
        XCTAssertEqual(context.store.saved.count, 1)
    }

    func testPendingDraftBlocksNewRecordingWithoutOverwritingIt() async throws {
        let context = Context()
        context.store.fails = true
        await context.startRecording()
        context.state.toggleRecord(source: .ui)
        let draft = try XCTUnwrap(context.state.unsavedRecording)
        XCTAssertFalse(context.state.canStartRecording)
        context.state.toggleRecord(source: .ui)
        XCTAssertEqual(context.state.unsavedRecording, draft)
        XCTAssertEqual(context.recorder.starts, 1)
        XCTAssertEqual(context.state.phase, .idle)
        XCTAssertNotNil(context.state.recordingNotice)
    }

    func testSaveAsKeepsScriptIdentityAndAllCaptureMetadata() async throws {
        let context = Context()
        context.store.fails = true
        await context.startRecording()
        context.state.toggleRecord(source: .ui)
        let draft = try XCTUnwrap(context.state.unsavedRecording)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(context.state.exportUnsavedRecording(to: url))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let restored = try decoder.decode(Script.self, from: Data(contentsOf: url))
        XCTAssertEqual(restored.id, draft.id)
        XCTAssertEqual(restored.blocks, draft.blocks)
        XCTAssertEqual(restored.trailingDelay, draft.trailingDelay)
        XCTAssertEqual(restored.targetBundleIdentifier, draft.targetBundleIdentifier)
        XCTAssertNil(context.state.unsavedRecording)
        XCTAssertTrue(context.state.scripts.isEmpty)
    }

    func testFailedSaveAsAndFailedQuitKeepDraft() async throws {
        let context = Context()
        context.store.fails = true
        await context.startRecording()
        context.state.toggleRecord(source: .ui)
        let draft = try XCTUnwrap(context.state.unsavedRecording)
        let missingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertFalse(context.state.exportUnsavedRecording(to: missingDirectory.appendingPathComponent("capture.json")))
        XCTAssertFalse(context.state.prepareForTermination(.save))
        XCTAssertEqual(context.state.unsavedRecording, draft)
        XCTAssertNotNil(context.state.persistenceIssue)
    }

    func testQuitStopsAndStagesRecordingBeforeDecisionWithoutRecordingDialog() async throws {
        let context = Context()
        await context.startRecording()
        context.state.stageRecordingForTermination()
        let draft = try XCTUnwrap(context.state.unsavedRecording)
        XCTAssertEqual(context.state.phase, .idle)
        XCTAssertEqual(context.recorder.stops, 1)
        XCTAssertTrue(context.store.saved.isEmpty)
        XCTAssertFalse(context.state.prepareForTermination(.cancel))
        XCTAssertEqual(context.state.unsavedRecording, draft)
        XCTAssertEqual(context.recorder.stops, 1)
        XCTAssertTrue(context.state.prepareForTermination(.save))
        XCTAssertEqual(context.store.saved, [draft])
    }

    func testQuitUsesExplicitMenuCutoffBeforeStagingTheDraft() async throws {
        let context = Context()
        await context.startRecording()
        context.state.stageRecordingForTermination(cutoff: RecordingCutoff(eventCount: 2, duration: 0.7))
        let draft = try XCTUnwrap(context.state.unsavedRecording)
        XCTAssertEqual(BlockExpander.plan(for: draft).duration, 0.7, accuracy: 0.000_001)
        XCTAssertEqual(context.recorder.stops, 1)
        XCTAssertTrue(context.store.saved.isEmpty)
    }

    func testQuitSaveFailureCancelsExitAndCanBeRetried() async throws {
        let context = Context()
        context.store.fails = true
        await context.startRecording()
        XCTAssertFalse(context.state.prepareForTermination(.save))
        let draft = try XCTUnwrap(context.state.unsavedRecording)
        XCTAssertEqual(context.recorder.stops, 1)
        context.store.fails = false
        XCTAssertTrue(context.state.prepareForTermination(.save))
        XCTAssertEqual(context.store.saved, [draft])
        XCTAssertEqual(context.recorder.stops, 1)
    }

    func testExplicitQuitDiscardDropsDraftWithoutSaving() async {
        let context = Context()
        await context.startRecording()
        XCTAssertTrue(context.state.prepareForTermination(.discard))
        XCTAssertNil(context.state.unsavedRecording)
        XCTAssertTrue(context.store.saved.isEmpty)
        XCTAssertTrue(context.state.canStartRecording)
    }

    func testIdleAndCountdownTerminationAreSafeAndLateCallbackCannotStartRecorder() async {
        let context = Context()
        XCTAssertTrue(context.state.prepareForTermination())
        context.state.toggleRecord(source: .ui)
        XCTAssertEqual(context.state.phase, .countdown(3))
        XCTAssertTrue(context.state.prepareForTermination())
        context.countdown.finish?()
        await Task.yield()
        XCTAssertEqual(context.state.phase, .idle)
        XCTAssertEqual(context.recorder.starts, 0)
        XCTAssertEqual(context.countdown.closes, 1)
    }

    func testPlaybackTerminationReleasesOnceEvenWithPendingDraft() async {
        let context = Context()
        context.store.fails = true
        await context.startRecording()
        context.state.toggleRecord(source: .ui)
        let script = Script(name: "play", blocks: [.wait(WaitBlock(duration: 1))])
        context.state.scripts = [script]
        context.state.selectedScriptID = script.id
        context.state.togglePlay()
        XCTAssertNotNil(context.state.activePlaybackScript)
        XCTAssertTrue(context.state.prepareForTermination(.discard))
        XCTAssertEqual(context.playback.stops, 1)
        XCTAssertNil(context.state.activePlaybackScript)
        XCTAssertNil(context.state.unsavedRecording)
        XCTAssertTrue(context.state.prepareForTermination())
        XCTAssertEqual(context.playback.stops, 1)
    }

    func testTapFailureSavesExplicitPartialMetadataAndWarns() async throws {
        let context = Context()
        context.state.setUp()
        await context.startRecording()
        context.recorder.onTapFailure?()
        await Task.yield()
        let script = try XCTUnwrap(context.state.scripts.first)
        XCTAssertNotNil(script.recordingInterruption)
        XCTAssertNotNil(context.state.recordingNotice)
        XCTAssertEqual(context.state.phase, .idle)
        let data = try JSONEncoder().encode(script)
        let restored = try JSONDecoder().decode(Script.self, from: data)
        XCTAssertEqual(restored.recordingInterruption, script.recordingInterruption)
        context.recorder.onTapFailure?()
        await Task.yield()
        XCTAssertEqual(context.recorder.stops, 1)
    }

    func testTapFailurePlusSaveFailureRetainsMarkedPartialDraft() async throws {
        let context = Context()
        context.store.fails = true
        context.state.setUp()
        await context.startRecording()
        context.recorder.onTapFailure?()
        await Task.yield()
        let draft = try XCTUnwrap(context.state.unsavedRecording)
        XCTAssertNotNil(draft.recordingInterruption)
        XCTAssertNotNil(context.state.recordingNotice)
        XCTAssertNotNil(context.state.persistenceIssue)
        XCTAssertTrue(context.state.scripts.isEmpty)
    }

    func testStartupFailureProvidesActionableNoticeWithoutDraft() async {
        let context = Context()
        context.recorder.startResult = false
        await context.startRecording()
        XCTAssertEqual(context.state.phase, .idle)
        XCTAssertEqual(context.state.recordingNotice?.title, "无法开始录制")
        XCTAssertNil(context.state.unsavedRecording)
        XCTAssertTrue(context.store.saved.isEmpty)
    }

    func testSuccessfulRetryClearsAStaleStartupFailureNotice() async {
        let context = Context()
        context.recorder.startResult = false
        await context.startRecording()
        XCTAssertNotNil(context.state.recordingNotice)
        context.recorder.startResult = true
        context.state.hasPermission = true
        await context.startRecording()
        XCTAssertEqual(context.state.phase, .recording)
        XCTAssertNil(context.state.recordingNotice)
    }

    func testShortcutPlaybackSnapshotAndProgressStayIndependentOfSidebarSelection() async throws {
        let context = Context()
        let first = Script(name: "one", blocks: [.wait(WaitBlock(duration: 1))], repeatCount: 1)
        let second = Script(name: "ten", blocks: [.wait(WaitBlock(duration: 1))], repeatCount: 10)
        context.state.scripts = [first, second]
        context.state.selectedScriptID = first.id
        context.state.playScriptFromShortcut(id: second.id)
        XCTAssertEqual(context.state.selectedScriptID, first.id)
        XCTAssertEqual(context.state.activePlaybackScript, second)
        context.playback.iteration?(2)
        await Task.yield()
        let unrelated = CompactScriptHeaderPresentation(
            script: first, phase: context.state.phase, activePlaybackScript: context.state.activePlaybackScript
        )
        XCTAssertNil(unrelated.playbackProgressText)
        context.state.selectedScriptID = second.id
        let playing = CompactScriptHeaderPresentation(
            script: second, phase: context.state.phase, activePlaybackScript: context.state.activePlaybackScript
        )
        XCTAssertEqual(playing.playbackProgressText, "第 2/10 轮")
        context.state.selectedScriptID = first.id
        XCTAssertEqual(context.state.activePlaybackScript, second)
        context.playback.finish?()
        await Task.yield()
        XCTAssertNil(context.state.activePlaybackScript)
        XCTAssertEqual(context.state.phase, .idle)
    }
}

@MainActor
private final class Context {
    let store = RecoveryStore()
    let recorder = RecoveryRecorder()
    let countdown = RecoveryCountdown()
    let playback = RecoveryPlayback()
    let state: AppState
    init() {
        state = AppState(store: store, recorder: recorder, countdown: countdown,
                         application: RecoveryApplication(), externalApplicationTracker: RecoveryTracker(),
                         recordingIndicator: RecoveryIndicator(), playbackEngine: playback)
        state.hasPermission = true
    }
    func startRecording() async {
        state.toggleRecord(source: .ui)
        countdown.finish?()
        await Task.yield()
    }
}

private final class RecoveryStore: ScriptPersisting {
    var fails = false
    var saved: [Script] = []
    func loadAll() -> ScriptStoreLoadResult { .init(scripts: [], issues: []) }
    func save(_ script: Script) throws {
        if fails { throw ScriptStoreIssue(operation: .temporaryWrite, message: "simulated full disk") }
        saved.append(script)
    }
    func delete(id: UUID) throws {}
}

private final class RecoveryRecorder: EventRecording {
    var onTapFailure: (() -> Void)?
    var onStopRequest: (() -> Void)?
    var startResult = true
    var starts = 0
    var stops = 0
    func start(stopShortcut: RecordingStopShortcut) -> Bool { starts += 1; return startResult }
    func stop() -> RecordingCapture {
        stops += 1
        return .init(events: [RecordedEvent(t: 0.1, kind: .leftDown, x: 20, y: 30),
                              RecordedEvent(t: 0.2, kind: .leftUp, x: 20, y: 30)], duration: 0.8)
    }
    func cutoff(at timestamp: CGEventTimestamp) -> RecordingCutoff { .init(eventCount: 2, duration: 0.8) }
}

private final class RecoveryCountdown: CountdownPresenting {
    var finish: (() -> Void)?
    var closes = 0
    func show(seconds: Int, onTick: @escaping (Int) -> Void, onFinish: @escaping () -> Void) { finish = onFinish }
    func close() { closes += 1 }
}

private final class RecoveryTracker: ExternalApplicationTracking {
    var mostRecentExternalBundleIdentifier: String? = "com.example.target"
    func start() {}
}

@MainActor
private final class RecoveryApplication: ApplicationControlling {
    func activateExternalApplication(bundleIdentifier: String) -> Bool { true }
    func hideClicker() {}
    func restoreClicker() {}
}

@MainActor
private final class RecoveryIndicator: RecordingIndicatorPresenting {
    func show(shortcut: RecordingStopShortcut) {}
    func close() {}
}

@MainActor
private final class RecoveryPlayback: PlaybackControlling {
    var iteration: ((Int) -> Void)?
    var finish: (() -> Void)?
    var stops = 0
    func play(script: Script, onIteration: @escaping (Int) -> Void,
              onBlock: @escaping (UUID?) -> Void, onFinish: @escaping () -> Void) {
        iteration = onIteration
        finish = onFinish
    }
    func stop() { stops += 1 }
}

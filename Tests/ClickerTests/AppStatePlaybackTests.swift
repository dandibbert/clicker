import AppKit
import CoreGraphics
import XCTest
@testable import Clicker
import ClickerCore

@MainActor
final class AppStatePlaybackTests: XCTestCase {
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
            playbackEngine: playback
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

    private func makeContext() -> (
        state: AppState,
        playback: StubPlaybackEngine,
        directory: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Clicker-AppStatePlaybackTests-\(UUID().uuidString)")
        let playback = StubPlaybackEngine()
        let state = AppState(
            store: ScriptStore(directory: directory),
            recorder: NoopEventRecorder(),
            countdown: NoopCountdown(),
            application: NoopRecordingApplication(),
            playbackEngine: playback
        )
        state.hasPermission = true
        return (state, playback, directory)
    }
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

    func play(
        script: Script,
        onIteration _: @escaping (Int) -> Void,
        onBlock _: @escaping (UUID?) -> Void,
        onFinish: @escaping () -> Void
    ) {
        playedScripts.append(script)
        finishes.append(onFinish)
    }

    func stop() {
        stopCallCount += 1
    }

    func finish(session index: Int) {
        finishes[index]()
    }
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

    func frontmostApplicationBundleIdentifier() -> String? { nil }
    func activateExternalApplication(bundleIdentifier: String) -> Bool {
        activatedBundleIdentifiers.append(bundleIdentifier)
        return activationResult
    }
    func hideClicker() {}
    func restoreClicker() {}
}

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

    func start() -> Bool { true }
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

private final class NoopRecordingApplication: RecordingApplicationControlling {
    func frontmostApplicationBundleIdentifier() -> String? { nil }
    func hideClicker() {}
    func restoreClicker() {}
}

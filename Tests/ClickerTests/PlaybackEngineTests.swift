import XCTest
@testable import Clicker
import ClickerCore

@MainActor
final class PlaybackEngineTests: XCTestCase {
    func testWaitOnlyPlanCompletesOnlyAfterPlanDuration() async {
        let timing = TestPlaybackTiming()
        let poster = RecordingPlaybackPoster()
        let stopMonitor = NoopPlaybackStopMonitor()
        let engine = PlaybackEngine(
            timing: timing,
            poster: poster,
            stopMonitor: stopMonitor
        )
        let finished = expectation(description: "playback finished")
        let script = Script(
            name: "wait-only",
            blocks: [.wait(WaitBlock(duration: 2))]
        )

        engine.play(
            script: script,
            onIteration: { _ in },
            onBlock: { _ in },
            onFinish: { finished.fulfill() }
        )
        await fulfillment(of: [finished], timeout: 1)

        XCTAssertEqual(timing.deadlines, [2])
        XCTAssertTrue(poster.actions.isEmpty)
    }

    func testTrailingOnlyPlanCompletesOnlyAfterTrailingDelay() async {
        let timing = TestPlaybackTiming()
        let poster = RecordingPlaybackPoster()
        let engine = PlaybackEngine(
            timing: timing,
            poster: poster,
            stopMonitor: NoopPlaybackStopMonitor()
        )
        let finished = expectation(description: "playback finished")
        let script = Script(name: "trailing-only", trailingDelay: 1.25)

        engine.play(
            script: script,
            onIteration: { _ in },
            onBlock: { _ in },
            onFinish: { finished.fulfill() }
        )
        await fulfillment(of: [finished], timeout: 1)

        XCTAssertEqual(timing.deadlines, [1.25])
        XCTAssertTrue(poster.actions.isEmpty)
    }

    func testRepeatIntervalBeginsAfterFullPlanDuration() async {
        let timing = TestPlaybackTiming()
        let engine = PlaybackEngine(
            timing: timing,
            poster: RecordingPlaybackPoster(),
            stopMonitor: NoopPlaybackStopMonitor()
        )
        let finished = expectation(description: "playback finished")
        let script = Script(
            name: "repeated wait",
            blocks: [.wait(WaitBlock(duration: 1))],
            repeatCount: 2,
            repeatInterval: 0.5
        )

        engine.play(
            script: script,
            onIteration: { _ in },
            onBlock: { _ in },
            onFinish: { finished.fulfill() }
        )
        await fulfillment(of: [finished], timeout: 1)

        XCTAssertEqual(timing.deadlines, [1, 1.5, 2.5])
    }

    func testEqualTimeStepsYieldAfterEachPostWithoutChangingOrder() async {
        let timing = TestPlaybackTiming()
        let poster = RecordingPlaybackPoster()
        let engine = PlaybackEngine(
            timing: timing,
            poster: poster,
            stopMonitor: NoopPlaybackStopMonitor()
        )
        let finished = expectation(description: "playback finished")
        let script = Script(
            name: "dense steps",
            blocks: [
                .move(MoveBlock(
                    duration: 0,
                    points: [
                        TrackPoint(t: 0, x: 1, y: 2, ordinal: 0),
                        TrackPoint(t: 0, x: 3, y: 4, ordinal: 1),
                        TrackPoint(t: 0, x: 5, y: 6, ordinal: 2),
                    ]
                )),
            ]
        )

        engine.play(
            script: script,
            onIteration: { _ in },
            onBlock: { _ in },
            onFinish: { finished.fulfill() }
        )
        await fulfillment(of: [finished], timeout: 1)

        XCTAssertEqual(poster.actions, [
            .mouseMove(x: 1, y: 2, flags: 0),
            .mouseMove(x: 3, y: 4, flags: 0),
            .mouseMove(x: 5, y: 6, flags: 0),
        ])
        XCTAssertGreaterThanOrEqual(timing.yieldCount, 3)
    }

    func testStopAfterKeyDownPostsOneCompensatingKeyUp() async {
        let released = expectation(description: "held key released")
        var engine: PlaybackEngine!
        var didStop = false
        let poster = RecordingPlaybackPoster { action in
            switch action {
            case .keyDown where !didStop:
                didStop = true
                engine.stop()
            case .keyUp where didStop:
                released.fulfill()
            default:
                break
            }
        }
        engine = PlaybackEngine(
            timing: TestPlaybackTiming(),
            poster: poster,
            stopMonitor: NoopPlaybackStopMonitor()
        )
        let script = Script(
            name: "held key",
            blocks: [
                .shortcut(ShortcutBlock(
                    keyCode: 4,
                    flags: 11,
                    upFlags: 12,
                    duration: 1
                )),
            ],
            repeatForever: true
        )

        engine.play(
            script: script,
            onIteration: { _ in },
            onBlock: { _ in },
            onFinish: {}
        )
        await fulfillment(of: [released], timeout: 1)

        XCTAssertEqual(poster.actions, [
            .keyDown(keyCode: 4, flags: 11, chars: ""),
            .keyUp(keyCode: 4, flags: 11),
        ])
    }

    func testStopAfterMouseDownPostsOneCompensatingMouseUp() async {
        let released = expectation(description: "held mouse button released")
        var engine: PlaybackEngine!
        var didStop = false
        let poster = RecordingPlaybackPoster { action in
            switch action {
            case .mouseDown where !didStop:
                didStop = true
                engine.stop()
            case .mouseUp where didStop:
                released.fulfill()
            default:
                break
            }
        }
        engine = PlaybackEngine(
            timing: TestPlaybackTiming(),
            poster: poster,
            stopMonitor: NoopPlaybackStopMonitor()
        )
        let script = Script(
            name: "held mouse",
            blocks: [
                .click(ClickBlock(
                    x: 10,
                    y: 20,
                    button: .left,
                    clickCount: 2,
                    duration: 1,
                    upX: 30,
                    upY: 40,
                    downFlags: 21,
                    upFlags: 22
                )),
            ]
        )

        engine.play(
            script: script,
            onIteration: { _ in },
            onBlock: { _ in },
            onFinish: {}
        )
        await fulfillment(of: [released], timeout: 1)

        XCTAssertEqual(poster.actions, [
            .mouseDown(x: 10, y: 20, button: .left, clickCount: 2, flags: 21),
            .mouseUp(x: 10, y: 20, button: .left, clickCount: 2, flags: 21),
        ])
    }

    func testReplacementReleasesOldSessionBeforePostingNewInputOnce() async {
        let replacementFinished = expectation(description: "replacement finished")
        var engine: PlaybackEngine!
        var didReplace = false
        let replacement = Script(
            name: "replacement",
            blocks: [
                .shortcut(ShortcutBlock(
                    keyCode: 5,
                    flags: 21,
                    upFlags: 22,
                    duration: 0
                )),
            ]
        )
        let poster = RecordingPlaybackPoster { action in
            guard case .keyDown(keyCode: 4, _, _) = action, !didReplace else { return }
            didReplace = true
            engine.play(
                script: replacement,
                onIteration: { _ in },
                onBlock: { _ in },
                onFinish: { replacementFinished.fulfill() }
            )
        }
        engine = PlaybackEngine(
            timing: TestPlaybackTiming(),
            poster: poster,
            stopMonitor: NoopPlaybackStopMonitor()
        )
        let original = Script(
            name: "original",
            blocks: [
                .shortcut(ShortcutBlock(
                    keyCode: 4,
                    flags: 11,
                    upFlags: 12,
                    duration: 1
                )),
            ]
        )

        engine.play(
            script: original,
            onIteration: { _ in },
            onBlock: { _ in },
            onFinish: {}
        )
        await fulfillment(of: [replacementFinished], timeout: 1)
        await Task.yield()

        XCTAssertEqual(poster.actions, [
            .keyDown(keyCode: 4, flags: 11, chars: ""),
            .keyUp(keyCode: 4, flags: 11),
            .keyDown(keyCode: 5, flags: 21, chars: ""),
            .keyUp(keyCode: 5, flags: 22),
        ])
    }

    func testStopMonitorCallbackCleansUpAndFinishesOnce() async {
        let stopMonitor = RecordingPlaybackStopMonitor()
        let engine = PlaybackEngine(
            timing: TestPlaybackTiming(),
            poster: RecordingPlaybackPoster(),
            stopMonitor: stopMonitor
        )
        var finishCount = 0
        engine.play(
            script: Script(
                name: "monitored wait",
                blocks: [.wait(WaitBlock(duration: 1))]
            ),
            onIteration: { _ in },
            onBlock: { _ in },
            onFinish: { finishCount += 1 }
        )
        let stopCountBeforeTrigger = stopMonitor.stopCount

        stopMonitor.triggerStop()
        stopMonitor.triggerStop()
        await Task.yield()

        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(stopMonitor.stopCount, stopCountBeforeTrigger + 1)
        XCTAssertFalse(stopMonitor.isStarted)
        XCTAssertFalse(engine.isPlaying)
    }
}

@MainActor
private final class TestPlaybackTiming: PlaybackTiming {
    private(set) var now: TimeInterval = 0
    private(set) var deadlines: [TimeInterval] = []
    private(set) var yieldCount = 0

    func sleep(until deadline: TimeInterval) async throws {
        try Task.checkCancellation()
        deadlines.append(deadline)
        now = max(now, deadline)
    }

    func cooperativeYield() async {
        yieldCount += 1
        await Task.yield()
    }
}

@MainActor
private final class RecordingPlaybackPoster: PlaybackEventPosting {
    private(set) var actions: [StepAction] = []
    private let onPost: (StepAction) -> Void

    init(onPost: @escaping (StepAction) -> Void = { _ in }) {
        self.onPost = onPost
    }

    func post(_ action: StepAction) {
        actions.append(action)
        onPost(action)
    }
}

@MainActor
private final class NoopPlaybackStopMonitor: PlaybackStopMonitoring {
    func start(onStop _: @escaping () -> Void) {}
    func stop() {}
}

@MainActor
private final class RecordingPlaybackStopMonitor: PlaybackStopMonitoring {
    private var onStop: (() -> Void)?
    private(set) var stopCount = 0

    var isStarted: Bool { onStop != nil }

    func start(onStop: @escaping () -> Void) {
        self.onStop = onStop
    }

    func stop() {
        stopCount += 1
        onStop = nil
    }

    func triggerStop() {
        onStop?()
    }
}

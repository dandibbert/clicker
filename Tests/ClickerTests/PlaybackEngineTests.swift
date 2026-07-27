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

    func post(_ action: StepAction) {
        actions.append(action)
    }
}

@MainActor
private final class NoopPlaybackStopMonitor: PlaybackStopMonitoring {
    func start(onStop _: @escaping () -> Void) {}
    func stop() {}
}

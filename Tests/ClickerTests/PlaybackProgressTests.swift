import XCTest
import ClickerCore
@testable import Clicker

@MainActor
final class PlaybackProgressTests: XCTestCase {
    func testWaitBlocksReportStepProgressAndRoundsWithoutPostingInput() async {
        let poster = ProgressPoster()
        let engine = PlaybackEngine(timing: ProgressTiming(), poster: poster, stopMonitor: ProgressStopMonitor())
        let script = Script(
            name: "等待测试",
            blocks: [
                .wait(WaitBlock(duration: 1)),
                ActionBlock.wait(WaitBlock(duration: 2)).withStartOffset(1),
            ],
            repeatCount: 2
        )
        var progress: [PlaybackProgress] = []
        var blocks: [UUID?] = []
        engine.onProgress = { progress.append($0) }
        let finished = expectation(description: "finished")

        engine.play(script: script, onIteration: { _ in }, onBlock: { blocks.append($0) }, onFinish: { finished.fulfill() })
        await fulfillment(of: [finished], timeout: 1)

        XCTAssertEqual(progress.map(\.currentStep), [0, 1, 2, 0, 1, 2])
        XCTAssertEqual(progress.map(\.iteration), [1, 1, 1, 2, 2, 2])
        XCTAssertTrue(progress.allSatisfy { $0.totalSteps == 2 && $0.totalIterations == 2 && $0.scriptName == script.name })
        XCTAssertEqual(blocks, [script.blocks[0].id, script.blocks[1].id, script.blocks[0].id, script.blocks[1].id])
        XCTAssertTrue(poster.actions.isEmpty)
        XCTAssertEqual(engine.completionReason, .completed)
        XCTAssertFalse(engine.isPlaying)
    }

    func testInputProgressCountsBlocksRatherThanLowLevelEvents() async {
        let poster = ProgressPoster()
        let engine = PlaybackEngine(timing: ProgressTiming(), poster: poster, stopMonitor: ProgressStopMonitor())
        let script = Script(name: "点击", blocks: [.click(ClickBlock(x: 10, y: 20, button: .left, clickCount: 1))])
        var progress: [PlaybackProgress] = []
        engine.onProgress = { progress.append($0) }
        let finished = expectation(description: "finished")

        engine.play(script: script, onIteration: { _ in }, onBlock: { _ in }, onFinish: { finished.fulfill() })
        await fulfillment(of: [finished], timeout: 1)

        XCTAssertEqual(progress.map(\.currentStep), [0, 1])
        XCTAssertEqual(progress.map(\.totalSteps), [1, 1])
        XCTAssertEqual(poster.actions.count, 2)
    }

    func testProgressStopPreventsPostingCurrentAndLaterInputs() async {
        let poster = ProgressPoster()
        let engine = PlaybackEngine(timing: ProgressTiming(), poster: poster, stopMonitor: ProgressStopMonitor())
        let stopped = expectation(description: "stopped")
        engine.onProgress = { progress in
            guard progress.currentStep == 1 else { return }
            engine.stop()
            stopped.fulfill()
        }
        var finishCount = 0
        engine.play(
            script: Script(name: "stop before input", blocks: [.shortcut(ShortcutBlock(keyCode: 4, flags: 0))]),
            onIteration: { _ in }, onBlock: { _ in }, onFinish: { finishCount += 1 }
        )
        await fulfillment(of: [stopped], timeout: 1)
        await Task.yield()

        XCTAssertTrue(poster.actions.isEmpty)
        XCTAssertEqual(finishCount, 0)
        XCTAssertEqual(engine.completionReason, .userStopped)
    }

    func testReplacedProgressObserverCannotReceiveOldSessionUpdates() async {
        let poster = ProgressPoster()
        let engine = PlaybackEngine(timing: ProgressTiming(), poster: poster, stopMonitor: ProgressStopMonitor())
        var originalProgress: [PlaybackProgress] = []
        var replacementProgress: [PlaybackProgress] = []
        let replacement = Script(name: "new", blocks: [.shortcut(ShortcutBlock(keyCode: 5, flags: 0))])
        let finished = expectation(description: "replacement finished")
        var oldFinishCount = 0
        engine.onProgress = { progress in
            originalProgress.append(progress)
            guard progress.currentStep == 1 else { return }
            engine.onProgress = { replacementProgress.append($0) }
            engine.play(script: replacement, onIteration: { _ in }, onBlock: { _ in }, onFinish: { finished.fulfill() })
        }
        engine.play(
            script: Script(name: "old", blocks: [.shortcut(ShortcutBlock(keyCode: 4, flags: 0))]),
            onIteration: { _ in }, onBlock: { _ in }, onFinish: { oldFinishCount += 1 }
        )
        await fulfillment(of: [finished], timeout: 1)

        XCTAssertEqual(originalProgress.map(\.scriptName), ["old", "old"])
        XCTAssertEqual(replacementProgress.map(\.scriptName), ["new", "new"])
        XCTAssertEqual(oldFinishCount, 0)
        XCTAssertEqual(poster.actions, [.keyDown(keyCode: 5, flags: 0, chars: ""), .keyUp(keyCode: 5, flags: 0)])
        XCTAssertEqual(engine.completionReason, .completed)
    }

    func testEscReportsUserStoppedAndCannotFinishTwice() {
        let monitor = ProgressStopMonitor()
        let engine = PlaybackEngine(timing: ProgressTiming(), poster: ProgressPoster(), stopMonitor: monitor)
        var reasons: [PlaybackCompletionReason?] = []
        engine.play(
            script: Script(name: "wait", blocks: [.wait(WaitBlock(duration: 10))]),
            onIteration: { _ in }, onBlock: { _ in }, onFinish: { reasons.append(engine.completionReason) }
        )
        let stop = monitor.callbacks[0]
        stop()
        stop()
        engine.stop()

        XCTAssertEqual(reasons, [.userStopped])
        XCTAssertEqual(engine.completionReason, .userStopped)
        XCTAssertFalse(engine.isPlaying)
    }

    func testTimingFailureReleasesHeldKeyAndReportsInterruption() async {
        let poster = ProgressPoster()
        let engine = PlaybackEngine(timing: ProgressTiming(throwsOnSleep: true), poster: poster, stopMonitor: ProgressStopMonitor())
        let finished = expectation(description: "interrupted")
        engine.play(
            script: Script(name: "key", blocks: [.shortcut(ShortcutBlock(keyCode: 4, flags: 11, duration: 1))]),
            onIteration: { _ in }, onBlock: { _ in }, onFinish: { finished.fulfill() }
        )
        await fulfillment(of: [finished], timeout: 1)

        guard case .interrupted = engine.completionReason else {
            return XCTFail("A failed timer must not be described as completed")
        }
        XCTAssertEqual(poster.actions, [.keyDown(keyCode: 4, flags: 11, chars: ""), .keyUp(keyCode: 4, flags: 11)])
        XCTAssertFalse(engine.isPlaying)
    }

    func testPreparationFailureRejectsWholePlanBeforeAnyInputOrMonitorStarts() {
        let poster = ProgressPoster()
        let monitor = ProgressStopMonitor()
        let engine = PlaybackEngine(
            timing: ProgressTiming(), poster: poster, stopMonitor: monitor,
            coordinateValidator: PlaybackCoordinateValidator(displayBounds: { [CGRect(x: 0, y: 0, width: 100, height: 100)] })
        )
        var finishCount = 0
        engine.play(
            script: Script(name: "out of bounds", blocks: [
                .shortcut(ShortcutBlock(keyCode: 4, flags: 0)),
                .click(ClickBlock(x: 200, y: 200, button: .left, clickCount: 1)),
            ]),
            onIteration: { _ in }, onBlock: { _ in }, onFinish: { finishCount += 1 }
        )

        guard case .preparationFailed = engine.completionReason else {
            return XCTFail("Expected preparation failure")
        }
        XCTAssertEqual(finishCount, 1)
        XCTAssertTrue(poster.actions.isEmpty)
        XCTAssertTrue(monitor.callbacks.isEmpty)
        XCTAssertFalse(engine.isPlaying)
    }

    func testEmptyPlanCompletesWithoutStartingMonitor() {
        let monitor = ProgressStopMonitor()
        let engine = PlaybackEngine(timing: ProgressTiming(), poster: ProgressPoster(), stopMonitor: monitor)
        var finishCount = 0
        engine.play(script: Script(name: "empty"), onIteration: { _ in }, onBlock: { _ in }, onFinish: { finishCount += 1 })
        XCTAssertEqual(finishCount, 1)
        XCTAssertEqual(engine.completionReason, .completed)
        XCTAssertTrue(monitor.callbacks.isEmpty)
    }

    func testInfiniteRepeatProgressHasNoInventedTotalRoundCount() {
        let progress = PlaybackProgress(script: Script(name: "loop", repeatForever: true), iteration: 7)
        XCTAssertNil(progress.totalIterations)
        XCTAssertEqual(progress.iterationDescription, "第 7 轮 · 持续重复")
    }

    func testSelectedTrialPostsOnlySelectedBlockOnceDespiteOverlappingSource() async throws {
        let unwanted = ActionBlock.shortcut(ShortcutBlock(keyCode: 4, flags: 0, startOffset: 5, duration: 2))
        let selected = ActionBlock.shortcut(ShortcutBlock(keyCode: 5, flags: 0, startOffset: 6, duration: 0.5))
        let source = Script(
            name: "trial",
            blocks: [unwanted, selected],
            repeatCount: 8,
            repeatForever: true,
            repeatInterval: 10,
            trailingDelay: 20
        )
        let trial = try XCTUnwrap(ScriptReuse.trial(source, selectedBlockIDs: [selected.id]))
        let poster = ProgressPoster()
        let engine = PlaybackEngine(timing: ProgressTiming(), poster: poster, stopMonitor: ProgressStopMonitor())
        let finished = expectation(description: "trial finished")
        var rounds: [Int] = []
        var blocks: [UUID?] = []
        engine.play(script: trial, onIteration: { rounds.append($0) }, onBlock: { blocks.append($0) }, onFinish: { finished.fulfill() })
        await fulfillment(of: [finished], timeout: 1)

        XCTAssertEqual(rounds, [1])
        XCTAssertEqual(blocks, [selected.id])
        XCTAssertEqual(poster.actions, [.keyDown(keyCode: 5, flags: 0, chars: ""), .keyUp(keyCode: 5, flags: 0)])
        XCTAssertEqual(source.blocks, [unwanted, selected])
        XCTAssertTrue(source.repeatForever)
    }
}

@MainActor
private final class ProgressTiming: PlaybackTiming {
    enum Failure: Error { case unavailable }
    var now: TimeInterval = 0
    let throwsOnSleep: Bool
    init(throwsOnSleep: Bool = false) { self.throwsOnSleep = throwsOnSleep }
    func sleep(until deadline: TimeInterval) async throws {
        try Task.checkCancellation()
        if throwsOnSleep { throw Failure.unavailable }
        now = max(now, deadline)
    }
    func cooperativeYield() async { await Task.yield() }
}

@MainActor
private final class ProgressPoster: PlaybackEventPosting {
    var actions: [StepAction] = []
    func post(_ action: StepAction) { actions.append(action) }
}

@MainActor
private final class ProgressStopMonitor: PlaybackStopMonitoring {
    var callbacks: [() -> Void] = []
    func start(onStop: @escaping () -> Void) { callbacks.append(onStop) }
    func stop() {}
}

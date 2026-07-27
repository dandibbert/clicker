import Foundation
import AppKit
import ClickerCore

/// 按时间轴投递回放步骤，支持重复与中断。
@MainActor
final class PlaybackEngine {
    private var task: Task<Void, Never>?
    private var generation = 0
    private var activeGeneration: Int?
    private var pressedInputs = PressedInputTracker()
    private var applicationSession: PlaybackApplicationSession?
    private let timing: PlaybackTiming
    private let poster: PlaybackEventPosting
    private let stopMonitor: PlaybackStopMonitoring
    private let applicationController: PlaybackApplicationControlling

    var isPlaying: Bool { task != nil }

    init() {
        self.timing = SystemPlaybackTiming()
        self.poster = SystemPlaybackEventPoster()
        self.stopMonitor = SystemPlaybackStopMonitor()
        self.applicationController = SystemPlaybackApplicationController()
    }

    init(
        timing: PlaybackTiming,
        poster: PlaybackEventPosting,
        stopMonitor: PlaybackStopMonitoring
    ) {
        self.timing = timing
        self.poster = poster
        self.stopMonitor = stopMonitor
        self.applicationController = SystemPlaybackApplicationController()
    }

    init(
        timing: PlaybackTiming,
        poster: PlaybackEventPosting,
        stopMonitor: PlaybackStopMonitoring,
        applicationController: PlaybackApplicationControlling
    ) {
        self.timing = timing
        self.poster = poster
        self.stopMonitor = stopMonitor
        self.applicationController = applicationController
    }

    /// onIteration(第几轮，从 1 计)、onBlock(当前块 ID)、onFinish 均在主线程回调。
    func play(script: Script,
              onIteration: @escaping (Int) -> Void,
              onBlock: @escaping (UUID?) -> Void,
              onFinish: @escaping () -> Void) {
        stop()
        generation += 1
        let gen = generation
        let plan = BlockExpander.plan(for: script)
        guard !plan.steps.isEmpty || plan.duration > 0 else { onFinish(); return }
        activeGeneration = gen
        pressedInputs = PressedInputTracker()
        applicationSession = applicationController.captureAndActivate(
            target: script.targetBundleIdentifier
        )

        stopMonitor.start { [weak self] in
            guard let self, self.isPlaying else { return }
            self.stop()
            onFinish()
        }

        let repeatCount = script.repeatForever ? Int.max : max(1, script.repeatCount)
        let interval = max(0, script.repeatInterval)

        task = Task { [weak self] in
            guard let self else { return }
            for iteration in 1...repeatCount {
                await timing.cooperativeYield()
                if Task.isCancelled { break }
                onIteration(iteration)
                let start = timing.now
                var lastBlockID: UUID?
                for step in plan.steps {
                    if Task.isCancelled { break }
                    let target = start + step.t
                    if target > timing.now {
                        do {
                            try await timing.sleep(until: target)
                        } catch {
                            break
                        }
                    }
                    if Task.isCancelled { break }
                    if step.blockID != lastBlockID {
                        lastBlockID = step.blockID
                        onBlock(step.blockID)
                    }
                    pressedInputs.observe(step.action)
                    poster.post(step.action)
                    await timing.cooperativeYield()
                }
                if Task.isCancelled { break }
                let planEnd = start + plan.duration
                if planEnd > timing.now {
                    do {
                        try await timing.sleep(until: planEnd)
                    } catch {
                        break
                    }
                }
                if Task.isCancelled { break }
                if iteration < repeatCount && interval > 0 {
                    onBlock(nil)
                    do {
                        try await timing.sleep(until: timing.now + interval)
                    } catch {
                        break
                    }
                }
            }
            let wasCancelled = Task.isCancelled
            guard gen == generation else { return }
            cleanUpSession(expectedGeneration: gen)
            if !wasCancelled { onFinish() }
        }
    }

    func stop() {
        generation += 1  // 使旧会话的收尾逻辑失效
        task?.cancel()
        cleanUpSession()
    }

    private func cleanUpSession(expectedGeneration: Int? = nil) {
        if let expectedGeneration, activeGeneration != expectedGeneration { return }

        task = nil
        stopMonitor.stop()
        guard activeGeneration != nil else { return }
        activeGeneration = nil
        let releaseActions = pressedInputs.releaseActions()
        let session = applicationSession
        applicationSession = nil
        for action in releaseActions {
            poster.post(action)
        }
        session?.restore()
    }
}

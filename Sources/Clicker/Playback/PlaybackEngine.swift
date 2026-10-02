import Foundation
import ClickerCore

/// 按时间轴投递回放步骤，支持重复与中断。
@MainActor
final class PlaybackEngine: PlaybackControlling {
    private struct TimelineEntry {
        let time: TimeInterval
        let blockID: UUID
        let step: PlaybackStep?
    }

    private var task: Task<Void, Never>?
    private var generation = 0
    private var activeGeneration: Int?
    private var pressedInputs = PressedInputTracker()
    private let timing: PlaybackTiming
    private let poster: PlaybackEventPosting
    private let stopMonitor: PlaybackStopMonitoring
    private let coordinateValidator: PlaybackCoordinateValidating

    private(set) var completionReason: PlaybackCompletionReason?
    var onProgress: ((PlaybackProgress) -> Void)?
    var isPlaying: Bool { task != nil }

    init() {
        timing = SystemPlaybackTiming()
        poster = SystemPlaybackEventPoster()
        stopMonitor = SystemPlaybackStopMonitor()
        coordinateValidator = PlaybackCoordinateValidator.system()
    }

    init(
        timing: PlaybackTiming,
        poster: PlaybackEventPosting,
        stopMonitor: PlaybackStopMonitoring,
        coordinateValidator: PlaybackCoordinateValidating? = nil
    ) {
        self.timing = timing
        self.poster = poster
        self.stopMonitor = stopMonitor
        self.coordinateValidator = coordinateValidator ?? PlaybackCoordinateValidator()
    }

    /// All callbacks run on the main actor. Explicit stop preserves the legacy
    /// contract: its caller handles dismissal; Esc invokes onFinish once.
    func play(script: Script,
              onIteration: @escaping (Int) -> Void,
              onBlock: @escaping (UUID?) -> Void,
              onFinish: @escaping () -> Void) {
        stop()
        completionReason = nil
        generation += 1
        let gen = generation
        let plan = BlockExpander.plan(for: script)
        if let message = coordinateValidator.failureMessage(for: plan) {
            completionReason = .preparationFailed(message)
            onFinish()
            return
        }
        guard !plan.steps.isEmpty || plan.duration > 0 else {
            completionReason = .completed
            onFinish()
            return
        }
        activeGeneration = gen
        pressedInputs = PressedInputTracker()

        // Capture the observer for this session. A replacement must never receive
        // progress from a cancelled session, even if its observer has changed.
        let reportProgress = onProgress
        let timeline = Self.timeline(script: script, plan: plan)
        var blockNumbers: [UUID: Int] = [:]
        for (index, block) in script.blocks.enumerated() {
            blockNumbers[block.id] = index + 1
        }

        stopMonitor.start { [weak self] in
            // Removing the monitor cannot cancel a callback already queued on
            // the main actor. A previous session must not stop its replacement.
            guard let self, self.isPlaying, self.isCurrent(gen) else { return }
            self.stop()
            guard self.generation == gen + 1 else { return }
            onFinish()
        }

        let repeatCount = script.repeatForever ? Int.max : max(1, script.repeatCount)
        let interval = Self.sanitizedTime(script.repeatInterval)

        task = Task { [weak self] in
            guard let self else { return }
            var result = PlaybackCompletionReason.completed
            do {
                for iteration in 1...repeatCount {
                    await timing.cooperativeYield()
                    guard isCurrent(gen), !Task.isCancelled else { return }
                    onIteration(iteration)
                    guard isCurrent(gen), !Task.isCancelled else { return }
                    reportProgress?(PlaybackProgress(script: script, iteration: iteration))
                    guard isCurrent(gen), !Task.isCancelled else { return }
                    let start = timing.now
                    var lastBlockID: UUID?
                    for entry in timeline {
                        guard isCurrent(gen), !Task.isCancelled else { return }
                        let target = start + entry.time
                        if target > timing.now {
                            try await timing.sleep(until: target)
                        }
                        guard isCurrent(gen), !Task.isCancelled else { return }
                        if entry.blockID != lastBlockID {
                            lastBlockID = entry.blockID
                            onBlock(entry.blockID)
                            guard isCurrent(gen), !Task.isCancelled else { return }
                            reportProgress?(PlaybackProgress(
                                script: script,
                                currentStep: blockNumbers[entry.blockID] ?? 0,
                                iteration: iteration
                            ))
                            guard isCurrent(gen), !Task.isCancelled else { return }
                        }
                        if let step = entry.step {
                            pressedInputs.observe(step.action)
                            poster.post(step.action)
                        }
                        await timing.cooperativeYield()
                    }
                    guard isCurrent(gen), !Task.isCancelled else { return }
                    let planEnd = start + plan.duration
                    if planEnd > timing.now {
                        try await timing.sleep(until: planEnd)
                    }
                    guard isCurrent(gen), !Task.isCancelled else { return }
                    if iteration < repeatCount && interval > 0 {
                        onBlock(nil)
                        guard isCurrent(gen), !Task.isCancelled else { return }
                        try await timing.sleep(until: timing.now + interval)
                    }
                }
            } catch {
                guard isCurrent(gen), !Task.isCancelled else { return }
                result = .interrupted("回放计时中断：\(error.localizedDescription)")
            }
            guard isCurrent(gen), !Task.isCancelled else { return }
            completionReason = result
            cleanUpSession(expectedGeneration: gen)
            guard gen == generation else { return }
            onFinish()
        }
    }

    func stop() {
        generation += 1  // 使旧会话的收尾逻辑失效
        if activeGeneration != nil { completionReason = .userStopped }
        task?.cancel()
        cleanUpSession()
    }

    private func isCurrent(_ expectedGeneration: Int) -> Bool {
        generation == expectedGeneration && activeGeneration == expectedGeneration
    }

    /// Markers report wait/empty blocks without manufacturing any input events.
    /// Real steps retain BlockExpander's time/ordinal ordering, including ties.
    private static func timeline(script: Script, plan: PlaybackPlan) -> [TimelineEntry] {
        let inputBlockIDs = Set(plan.steps.map(\.blockID))
        let markers = script.blocks.filter { !inputBlockIDs.contains($0.id) }.map { block in
            TimelineEntry(time: sanitizedTime(block.startOffset), blockID: block.id, step: nil)
        }
        let steps = plan.steps.map { TimelineEntry(time: $0.t, blockID: $0.blockID, step: $0) }
        return (markers + steps).enumerated().sorted { lhs, rhs in
            if lhs.element.time != rhs.element.time {
                return lhs.element.time < rhs.element.time
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func sanitizedTime(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite, value > 0 else { return 0 }
        return min(value, Double(Int64.max) / 1_000_000_000 - 1)
    }

    private func cleanUpSession(expectedGeneration: Int? = nil) {
        if let expectedGeneration, activeGeneration != expectedGeneration { return }

        task = nil
        stopMonitor.stop()
        guard activeGeneration != nil else { return }
        activeGeneration = nil
        let releaseActions = pressedInputs.releaseActions()
        for action in releaseActions {
            poster.post(action)
        }
    }
}

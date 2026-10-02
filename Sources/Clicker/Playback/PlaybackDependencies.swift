import AppKit
import ClickerCore

@MainActor
protocol PlaybackTiming: AnyObject {
    var now: TimeInterval { get }
    func sleep(until deadline: TimeInterval) async throws
    func cooperativeYield() async
}

@MainActor
protocol PlaybackEventPosting: AnyObject {
    func post(_ action: StepAction)
}

@MainActor
protocol PlaybackStopMonitoring: AnyObject {
    func start(onStop: @escaping () -> Void)
    func stop()
}

@MainActor
protocol PlaybackControlling: AnyObject {
    var completionReason: PlaybackCompletionReason? { get }
    var onProgress: ((PlaybackProgress) -> Void)? { get set }

    func play(
        script: Script,
        onIteration: @escaping (Int) -> Void,
        onBlock: @escaping (UUID?) -> Void,
        onFinish: @escaping () -> Void
    )
    func stop()
}

extension PlaybackControlling {
    // Keep older controllers and focused test doubles source compatible.
    var completionReason: PlaybackCompletionReason? { nil }
    var onProgress: ((PlaybackProgress) -> Void)? {
        get { nil }
        set {}
    }
}

/// Describes input delivery only; completion does not verify a target app's result.
enum PlaybackCompletionReason: Equatable {
    case completed
    case userStopped
    case preparationFailed(String)
    case interrupted(String)
}

struct PlaybackProgress: Equatable {
    let scriptName: String
    let currentStep: Int
    let totalSteps: Int
    let iteration: Int
    let totalIterations: Int?

    init(
        scriptName: String,
        currentStep: Int,
        totalSteps: Int,
        iteration: Int,
        totalIterations: Int?
    ) {
        self.scriptName = scriptName
        self.totalSteps = max(0, totalSteps)
        self.currentStep = min(max(0, currentStep), max(0, totalSteps))
        self.iteration = max(1, iteration)
        self.totalIterations = totalIterations.map { max(1, $0) }
    }

    init(script: Script, currentStep: Int = 0, iteration: Int = 1) {
        self.init(
            scriptName: script.name,
            currentStep: currentStep,
            totalSteps: script.blocks.count,
            iteration: iteration,
            totalIterations: script.repeatForever ? nil : script.repeatCount
        )
    }

    var stepDescription: String { "步骤 \(currentStep) / \(totalSteps)" }
    var iterationDescription: String {
        if let totalIterations { return "第 \(iteration) / \(totalIterations) 轮" }
        return "第 \(iteration) 轮 · 持续重复"
    }
}

@MainActor
protocol PlaybackIndicatorPresenting: AnyObject {
    func show(progress: PlaybackProgress, onStop: @escaping () -> Void)
    func update(progress: PlaybackProgress)
    func close()
}

@MainActor
protocol PlaybackCoordinateValidating: AnyObject {
    func failureMessage(for plan: PlaybackPlan) -> String?
}

@MainActor
final class SystemPlaybackTiming: PlaybackTiming {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func sleep(until deadline: TimeInterval) async throws {
        let delay = max(0, deadline - now)
        if delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }
    }

    func cooperativeYield() async {
        await Task.yield()
    }
}

@MainActor
final class SystemPlaybackEventPoster: PlaybackEventPosting {
    func post(_ action: StepAction) {
        EventPoster.post(action)
    }
}

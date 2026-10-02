import Foundation

/// 回放原子动作。坐标为 CG 坐标。
public enum StepAction: Equatable, Sendable {
    case mouseMove(x: Double, y: Double, flags: UInt64)
    case mouseDown(x: Double, y: Double, button: MouseButton, clickCount: Int, flags: UInt64)
    case mouseUp(x: Double, y: Double, button: MouseButton, clickCount: Int, flags: UInt64)
    case mouseDrag(x: Double, y: Double, button: MouseButton, flags: UInt64)
    case keyDown(keyCode: UInt16, flags: UInt64, chars: String, isRepeat: Bool = false)
    case keyUp(keyCode: UInt16, flags: UInt64)
    case scroll(x: Double, y: Double, dx: Double, dy: Double, flags: UInt64)
}

/// 带绝对时间戳（相对回放起点）的步骤。blockID 用于回放时高亮当前块。
public struct PlaybackStep: Equatable, Sendable {
    public var t: TimeInterval
    public var action: StepAction
    public var blockID: UUID
    public var ordinal: Int

    public init(
        t: TimeInterval,
        action: StepAction,
        blockID: UUID,
        ordinal: Int = 0
    ) {
        self.t = t
        self.action = action
        self.blockID = blockID
        self.ordinal = max(0, ordinal)
    }
}

/// 完整回放时间轴。duration 可在没有任何投递步骤时保留等待时长。
public struct PlaybackPlan: Equatable, Sendable {
    public var steps: [PlaybackStep]
    public var duration: TimeInterval

    public init(steps: [PlaybackStep], duration: TimeInterval) {
        self.steps = steps
        self.duration = duration
    }
}

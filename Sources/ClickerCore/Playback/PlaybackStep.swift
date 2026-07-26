import Foundation

/// 回放原子动作。坐标为 CG 坐标。
public enum StepAction: Equatable, Sendable {
    case mouseMove(x: Double, y: Double)
    case mouseDown(x: Double, y: Double, button: MouseButton, clickCount: Int)
    case mouseUp(x: Double, y: Double, button: MouseButton)
    case mouseDrag(x: Double, y: Double, button: MouseButton)
    case keyDown(keyCode: UInt16, flags: UInt64, chars: String)
    case keyUp(keyCode: UInt16, flags: UInt64)
    case scroll(dx: Double, dy: Double)
}

/// 带绝对时间戳（相对回放起点）的步骤。blockID 用于回放时高亮当前块。
public struct PlaybackStep: Equatable, Sendable {
    public var t: TimeInterval
    public var action: StepAction
    public var blockID: UUID

    public init(t: TimeInterval, action: StepAction, blockID: UUID) {
        self.t = t; self.action = action; self.blockID = blockID
    }
}

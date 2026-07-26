import Foundation

/// 原始输入事件类型。坐标系为 CG 坐标（屏幕左上角为原点）。
public enum EventKind: String, Codable, Equatable, Sendable {
    case mouseMove
    case leftDown, leftUp, leftDrag
    case rightDown, rightUp, rightDrag
    case scroll
    case keyDown, keyUp
    case flagsChanged
}

/// 录制到的单个事件，t 为相对录制起点的秒数。
public struct RecordedEvent: Codable, Equatable, Sendable {
    public var t: TimeInterval
    public var kind: EventKind
    public var x: Double
    public var y: Double
    public var keyCode: UInt16
    public var flags: UInt64
    public var chars: String
    public var clickCount: Int
    public var scrollDX: Double
    public var scrollDY: Double

    public init(t: TimeInterval, kind: EventKind, x: Double = 0, y: Double = 0,
                keyCode: UInt16 = 0, flags: UInt64 = 0, chars: String = "",
                clickCount: Int = 0, scrollDX: Double = 0, scrollDY: Double = 0) {
        self.t = t; self.kind = kind; self.x = x; self.y = y
        self.keyCode = keyCode; self.flags = flags; self.chars = chars
        self.clickCount = clickCount; self.scrollDX = scrollDX; self.scrollDY = scrollDY
    }
}

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
    public var isRepeat: Bool

    public init(t: TimeInterval, kind: EventKind, x: Double = 0, y: Double = 0,
                keyCode: UInt16 = 0, flags: UInt64 = 0, chars: String = "",
                clickCount: Int = 0, scrollDX: Double = 0, scrollDY: Double = 0,
                isRepeat: Bool = false) {
        self.t = t; self.kind = kind; self.x = x; self.y = y
        self.keyCode = keyCode; self.flags = flags; self.chars = chars
        self.clickCount = clickCount; self.scrollDX = scrollDX; self.scrollDY = scrollDY
        self.isRepeat = isRepeat
    }

    private enum CodingKeys: String, CodingKey {
        case t, kind, x, y, keyCode, flags, chars, clickCount, scrollDX, scrollDY
        case isRepeat
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        t = try container.decode(TimeInterval.self, forKey: .t)
        kind = try container.decode(EventKind.self, forKey: .kind)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        flags = try container.decode(UInt64.self, forKey: .flags)
        chars = try container.decode(String.self, forKey: .chars)
        clickCount = try container.decode(Int.self, forKey: .clickCount)
        scrollDX = try container.decode(Double.self, forKey: .scrollDX)
        scrollDY = try container.decode(Double.self, forKey: .scrollDY)
        isRepeat = try container.decodeIfPresent(Bool.self, forKey: .isRepeat) ?? false
    }
}

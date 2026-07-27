import Foundation

public enum MouseButton: String, Codable, Equatable, Sendable {
    case left, right
}

/// 轨迹点，t 为相对块起点的秒数，ordinal 为原始捕获顺序。
public struct TrackPoint: Codable, Equatable, Sendable {
    public var t: TimeInterval
    public var x: Double
    public var y: Double
    public var flags: UInt64
    public var ordinal: Int

    public init(
        t: TimeInterval,
        x: Double,
        y: Double,
        flags: UInt64 = 0,
        ordinal: Int = 0
    ) {
        self.t = t
        self.x = x
        self.y = y
        self.flags = flags
        self.ordinal = TimelineValue.ordinal(ordinal)
    }

    private enum CodingKeys: String, CodingKey {
        case t, x, y, flags, ordinal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        t = try container.decode(TimeInterval.self, forKey: .t)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        flags = try container.decodeIfPresent(UInt64.self, forKey: .flags) ?? 0
        ordinal = TimelineValue.ordinal(
            try container.decodeIfPresent(Int.self, forKey: .ordinal) ?? 0
        )
    }
}

public struct ScrollStep: Codable, Equatable, Sendable {
    public var t: TimeInterval
    public var x: Double?
    public var y: Double?
    public var dx: Double
    public var dy: Double
    public var flags: UInt64
    public var ordinal: Int

    public init(
        t: TimeInterval,
        dx: Double,
        dy: Double,
        flags: UInt64 = 0,
        ordinal: Int = 0
    ) {
        self.t = t
        x = nil
        y = nil
        self.dx = dx
        self.dy = dy
        self.flags = flags
        self.ordinal = TimelineValue.ordinal(ordinal)
    }

    public init(
        t: TimeInterval,
        x: Double,
        y: Double,
        dx: Double,
        dy: Double,
        flags: UInt64 = 0,
        ordinal: Int = 0
    ) {
        self.t = t
        self.x = x
        self.y = y
        self.dx = dx
        self.dy = dy
        self.flags = flags
        self.ordinal = TimelineValue.ordinal(ordinal)
    }

    private enum CodingKeys: String, CodingKey {
        case t, x, y, dx, dy, flags, ordinal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        t = try container.decode(TimeInterval.self, forKey: .t)
        x = try container.decodeIfPresent(Double.self, forKey: .x)
        y = try container.decodeIfPresent(Double.self, forKey: .y)
        dx = try container.decode(Double.self, forKey: .dx)
        dy = try container.decode(Double.self, forKey: .dy)
        flags = try container.decodeIfPresent(UInt64.self, forKey: .flags) ?? 0
        ordinal = TimelineValue.ordinal(
            try container.decodeIfPresent(Int.self, forKey: .ordinal) ?? 0
        )
    }
}

/// 打字块内的一次 keyDown；自动重复项共享同一次物理 keyUp 的时间与顺序。
public struct Keystroke: Codable, Equatable, Sendable {
    public var t: TimeInterval
    public var keyCode: UInt16
    public var chars: String
    public var upT: TimeInterval
    public var downFlags: UInt64
    public var upFlags: UInt64
    public var isRepeat: Bool
    public var downOrdinal: Int
    public var upOrdinal: Int

    public init(
        t: TimeInterval,
        keyCode: UInt16,
        chars: String,
        upT: TimeInterval? = nil,
        downFlags: UInt64 = 0,
        upFlags: UInt64 = 0,
        isRepeat: Bool = false,
        downOrdinal: Int = 0,
        upOrdinal: Int = 1
    ) {
        self.t = t
        self.keyCode = keyCode
        self.chars = chars
        self.upT = upT ?? t + 0.02
        self.downFlags = downFlags
        self.upFlags = upFlags
        self.isRepeat = isRepeat
        self.downOrdinal = TimelineValue.ordinal(downOrdinal)
        self.upOrdinal = TimelineValue.ordinal(upOrdinal)
    }

    private enum CodingKeys: String, CodingKey {
        case t, keyCode, chars, upT, downFlags, upFlags, isRepeat
        case downOrdinal, upOrdinal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        t = try container.decode(TimeInterval.self, forKey: .t)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        chars = try container.decode(String.self, forKey: .chars)
        upT = try container.decodeIfPresent(TimeInterval.self, forKey: .upT) ?? t + 0.02
        downFlags = try container.decodeIfPresent(UInt64.self, forKey: .downFlags) ?? 0
        upFlags = try container.decodeIfPresent(UInt64.self, forKey: .upFlags) ?? 0
        isRepeat = try container.decodeIfPresent(Bool.self, forKey: .isRepeat) ?? false
        downOrdinal = TimelineValue.ordinal(
            try container.decodeIfPresent(Int.self, forKey: .downOrdinal) ?? 0
        )
        upOrdinal = TimelineValue.ordinal(
            try container.decodeIfPresent(Int.self, forKey: .upOrdinal) ?? 1
        )
    }
}

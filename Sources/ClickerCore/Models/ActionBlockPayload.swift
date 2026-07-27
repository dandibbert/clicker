import Foundation

public struct MoveBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var duration: TimeInterval
    public var points: [TrackPoint]
    public var startOffset: TimeInterval
    public var delayBefore: TimeInterval
    public var overlapBefore: TimeInterval

    public init(
        id: UUID = UUID(),
        duration: TimeInterval,
        points: [TrackPoint],
        delayBefore: TimeInterval = 0,
        startOffset: TimeInterval = 0
    ) {
        self.id = id
        self.duration = duration
        self.points = points
        self.startOffset = TimelineValue.time(startOffset)
        self.delayBefore = delayBefore
        overlapBefore = 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, duration, points, startOffset, delayBefore, overlapBefore
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        points = try container.decode([TrackPoint].self, forKey: .points)
        startOffset = TimelineValue.time(
            try container.decodeIfPresent(TimeInterval.self, forKey: .startOffset) ?? 0
        )
        delayBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .delayBefore) ?? 0
        overlapBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .overlapBefore) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(duration, forKey: .duration)
        try container.encode(points, forKey: .points)
        try container.encode(TimelineValue.time(startOffset), forKey: .startOffset)
    }
}

public struct ClickBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var x: Double
    public var y: Double
    public var button: MouseButton
    public var clickCount: Int
    public var upClickCount: Int
    public var startOffset: TimeInterval
    public var delayBefore: TimeInterval
    public var overlapBefore: TimeInterval
    public var duration: TimeInterval
    public var upX: Double
    public var upY: Double
    public var downFlags: UInt64
    public var upFlags: UInt64
    public var downOrdinal: Int
    public var upOrdinal: Int

    public init(
        id: UUID = UUID(),
        x: Double,
        y: Double,
        button: MouseButton,
        clickCount: Int,
        delayBefore: TimeInterval = 0,
        startOffset: TimeInterval = 0,
        duration: TimeInterval = 0.03,
        upX: Double? = nil,
        upY: Double? = nil,
        upClickCount: Int? = nil,
        downFlags: UInt64 = 0,
        upFlags: UInt64 = 0,
        downOrdinal: Int = 0,
        upOrdinal: Int = 1
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.button = button
        self.clickCount = clickCount
        self.upClickCount = upClickCount ?? clickCount
        self.startOffset = TimelineValue.time(startOffset)
        self.delayBefore = delayBefore
        overlapBefore = 0
        self.duration = duration
        self.upX = upX ?? x
        self.upY = upY ?? y
        self.downFlags = downFlags
        self.upFlags = upFlags
        self.downOrdinal = TimelineValue.ordinal(downOrdinal)
        self.upOrdinal = TimelineValue.ordinal(upOrdinal)
    }

    private enum CodingKeys: String, CodingKey {
        case id, x, y, button, clickCount, upClickCount, startOffset
        case delayBefore, overlapBefore, duration, upX, upY, downFlags, upFlags
        case downOrdinal, upOrdinal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        button = try container.decode(MouseButton.self, forKey: .button)
        clickCount = try container.decode(Int.self, forKey: .clickCount)
        upClickCount = try container.decodeIfPresent(Int.self, forKey: .upClickCount) ?? clickCount
        startOffset = TimelineValue.time(
            try container.decodeIfPresent(TimeInterval.self, forKey: .startOffset) ?? 0
        )
        delayBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .delayBefore) ?? 0
        overlapBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .overlapBefore) ?? 0
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0.03
        upX = try container.decodeIfPresent(Double.self, forKey: .upX) ?? x
        upY = try container.decodeIfPresent(Double.self, forKey: .upY) ?? y
        downFlags = try container.decodeIfPresent(UInt64.self, forKey: .downFlags) ?? 0
        upFlags = try container.decodeIfPresent(UInt64.self, forKey: .upFlags) ?? 0
        downOrdinal = TimelineValue.ordinal(
            try container.decodeIfPresent(Int.self, forKey: .downOrdinal) ?? 0
        )
        upOrdinal = TimelineValue.ordinal(
            try container.decodeIfPresent(Int.self, forKey: .upOrdinal) ?? 1
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(button, forKey: .button)
        try container.encode(clickCount, forKey: .clickCount)
        try container.encode(upClickCount, forKey: .upClickCount)
        try container.encode(TimelineValue.time(startOffset), forKey: .startOffset)
        try container.encode(duration, forKey: .duration)
        try container.encode(upX, forKey: .upX)
        try container.encode(upY, forKey: .upY)
        try container.encode(downFlags, forKey: .downFlags)
        try container.encode(upFlags, forKey: .upFlags)
        try container.encode(TimelineValue.ordinal(downOrdinal), forKey: .downOrdinal)
        try container.encode(TimelineValue.ordinal(upOrdinal), forKey: .upOrdinal)
    }
}

public struct DragBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var button: MouseButton
    public var duration: TimeInterval
    public var points: [TrackPoint]
    public var startOffset: TimeInterval
    public var delayBefore: TimeInterval
    public var overlapBefore: TimeInterval
    public var hasRecordedMouseUp: Bool
    public var upOrdinal: Int

    public init(
        id: UUID = UUID(),
        button: MouseButton,
        duration: TimeInterval,
        points: [TrackPoint],
        delayBefore: TimeInterval = 0,
        startOffset: TimeInterval = 0
    ) {
        self.id = id
        self.button = button
        self.duration = duration
        self.points = points
        self.startOffset = TimelineValue.time(startOffset)
        self.delayBefore = delayBefore
        overlapBefore = 0
        hasRecordedMouseUp = true
        upOrdinal = points.last?.ordinal ?? 0
    }

    public init(
        id: UUID,
        button: MouseButton,
        duration: TimeInterval,
        points: [TrackPoint],
        delayBefore: TimeInterval
    ) {
        self.init(
            id: id,
            button: button,
            duration: duration,
            points: points,
            delayBefore: delayBefore,
            startOffset: 0
        )
    }

    public init(
        id: UUID = UUID(),
        button: MouseButton,
        duration: TimeInterval,
        points: [TrackPoint],
        delayBefore: TimeInterval = 0,
        startOffset: TimeInterval = 0,
        hasRecordedMouseUp: Bool,
        upOrdinal: Int? = nil
    ) {
        self.init(
            id: id,
            button: button,
            duration: duration,
            points: points,
            delayBefore: delayBefore,
            startOffset: startOffset
        )
        self.hasRecordedMouseUp = hasRecordedMouseUp
        let defaultUpOrdinal = points.last.map { point in
            hasRecordedMouseUp
                ? point.ordinal
                : TimelineValue.nextOrdinal(after: point.ordinal)
        } ?? 0
        self.upOrdinal = TimelineValue.ordinal(upOrdinal ?? defaultUpOrdinal)
    }

    private enum CodingKeys: String, CodingKey {
        case id, button, duration, points, startOffset, delayBefore, overlapBefore
        case hasRecordedMouseUp, upOrdinal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        button = try container.decode(MouseButton.self, forKey: .button)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        points = try container.decode([TrackPoint].self, forKey: .points)
        startOffset = TimelineValue.time(
            try container.decodeIfPresent(TimeInterval.self, forKey: .startOffset) ?? 0
        )
        delayBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .delayBefore) ?? 0
        overlapBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .overlapBefore) ?? 0
        let decodedHasRecordedMouseUp = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasRecordedMouseUp
        ) ?? true
        hasRecordedMouseUp = decodedHasRecordedMouseUp
        let lastPointOrdinal = points.last?.ordinal ?? 0
        let defaultUpOrdinal = decodedHasRecordedMouseUp
            ? lastPointOrdinal
            : TimelineValue.nextOrdinal(after: lastPointOrdinal)
        upOrdinal = TimelineValue.ordinal(
            try container.decodeIfPresent(Int.self, forKey: .upOrdinal) ?? defaultUpOrdinal
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(button, forKey: .button)
        try container.encode(duration, forKey: .duration)
        try container.encode(points, forKey: .points)
        try container.encode(TimelineValue.time(startOffset), forKey: .startOffset)
        try container.encode(hasRecordedMouseUp, forKey: .hasRecordedMouseUp)
        try container.encode(TimelineValue.ordinal(upOrdinal), forKey: .upOrdinal)
    }
}

public struct ScrollBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var x: Double
    public var y: Double
    public var duration: TimeInterval
    public var steps: [ScrollStep]
    public var startOffset: TimeInterval
    public var delayBefore: TimeInterval
    public var overlapBefore: TimeInterval

    public init(
        id: UUID = UUID(),
        x: Double,
        y: Double,
        duration: TimeInterval,
        steps: [ScrollStep],
        delayBefore: TimeInterval = 0,
        startOffset: TimeInterval = 0
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.duration = duration
        self.steps = Self.normalized(steps, fallbackX: x, fallbackY: y)
        self.startOffset = TimelineValue.time(startOffset)
        self.delayBefore = delayBefore
        overlapBefore = 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, x, y, duration, steps, startOffset, delayBefore, overlapBefore
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        let decodedSteps = try container.decode([ScrollStep].self, forKey: .steps)
        steps = Self.normalized(decodedSteps, fallbackX: x, fallbackY: y)
        startOffset = TimelineValue.time(
            try container.decodeIfPresent(TimeInterval.self, forKey: .startOffset) ?? 0
        )
        delayBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .delayBefore) ?? 0
        overlapBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .overlapBefore) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(duration, forKey: .duration)
        try container.encode(Self.normalized(steps, fallbackX: x, fallbackY: y), forKey: .steps)
        try container.encode(TimelineValue.time(startOffset), forKey: .startOffset)
    }

    private static func normalized(
        _ steps: [ScrollStep],
        fallbackX: Double,
        fallbackY: Double
    ) -> [ScrollStep] {
        steps.map { step in
            guard step.x != nil, step.y != nil else {
                return ScrollStep(
                    t: step.t,
                    x: fallbackX,
                    y: fallbackY,
                    dx: step.dx,
                    dy: step.dy,
                    flags: step.flags,
                    ordinal: step.ordinal
                )
            }
            return step
        }
    }
}

public struct TypeTextBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var keystrokes: [Keystroke]
    public var startOffset: TimeInterval
    public var delayBefore: TimeInterval
    public var overlapBefore: TimeInterval
    public var duration: TimeInterval

    public init(
        id: UUID = UUID(),
        text: String,
        keystrokes: [Keystroke],
        delayBefore: TimeInterval = 0,
        startOffset: TimeInterval = 0,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.text = text
        self.keystrokes = keystrokes
        self.startOffset = TimelineValue.time(startOffset)
        self.delayBefore = delayBefore
        overlapBefore = 0
        self.duration = duration ?? Self.derivedDuration(text: text, keystrokes: keystrokes)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, keystrokes, startOffset, delayBefore, overlapBefore, duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        keystrokes = try container.decode([Keystroke].self, forKey: .keystrokes)
        startOffset = TimelineValue.time(
            try container.decodeIfPresent(TimeInterval.self, forKey: .startOffset) ?? 0
        )
        delayBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .delayBefore) ?? 0
        overlapBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .overlapBefore) ?? 0
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
            ?? Self.derivedDuration(text: text, keystrokes: keystrokes)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(keystrokes, forKey: .keystrokes)
        try container.encode(TimelineValue.time(startOffset), forKey: .startOffset)
        try container.encode(duration, forKey: .duration)
    }

    private static func derivedDuration(text: String, keystrokes: [Keystroke]) -> TimeInterval {
        if let lastTime = keystrokes.map({ max($0.t, $0.upT) }).max() {
            return lastTime
        }
        guard !text.isEmpty else { return 0 }
        return Double(text.count - 1) * 0.06 + 0.02
    }
}

public struct ShortcutBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var keyCode: UInt16
    public var flags: UInt64
    public var startOffset: TimeInterval
    public var delayBefore: TimeInterval
    public var overlapBefore: TimeInterval
    public var upFlags: UInt64
    public var duration: TimeInterval
    public var isRepeat: Bool
    public var downOrdinal: Int
    public var upOrdinal: Int

    public init(
        id: UUID = UUID(),
        keyCode: UInt16,
        flags: UInt64,
        delayBefore: TimeInterval = 0,
        startOffset: TimeInterval = 0,
        upFlags: UInt64? = nil,
        duration: TimeInterval = 0.02,
        isRepeat: Bool = false,
        downOrdinal: Int = 0,
        upOrdinal: Int = 1
    ) {
        self.id = id
        self.keyCode = keyCode
        self.flags = flags
        self.startOffset = TimelineValue.time(startOffset)
        self.delayBefore = delayBefore
        overlapBefore = 0
        self.upFlags = upFlags ?? flags
        self.duration = duration
        self.isRepeat = isRepeat
        self.downOrdinal = TimelineValue.ordinal(downOrdinal)
        self.upOrdinal = TimelineValue.ordinal(upOrdinal)
    }

    private enum CodingKeys: String, CodingKey {
        case id, keyCode, flags, startOffset, delayBefore, overlapBefore
        case upFlags, duration, isRepeat, downOrdinal, upOrdinal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        flags = try container.decode(UInt64.self, forKey: .flags)
        startOffset = TimelineValue.time(
            try container.decodeIfPresent(TimeInterval.self, forKey: .startOffset) ?? 0
        )
        delayBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .delayBefore) ?? 0
        overlapBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .overlapBefore) ?? 0
        upFlags = try container.decodeIfPresent(UInt64.self, forKey: .upFlags) ?? flags
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0.02
        isRepeat = try container.decodeIfPresent(Bool.self, forKey: .isRepeat) ?? false
        downOrdinal = TimelineValue.ordinal(
            try container.decodeIfPresent(Int.self, forKey: .downOrdinal) ?? 0
        )
        upOrdinal = TimelineValue.ordinal(
            try container.decodeIfPresent(Int.self, forKey: .upOrdinal) ?? 1
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(flags, forKey: .flags)
        try container.encode(TimelineValue.time(startOffset), forKey: .startOffset)
        try container.encode(upFlags, forKey: .upFlags)
        try container.encode(duration, forKey: .duration)
        try container.encode(isRepeat, forKey: .isRepeat)
        try container.encode(TimelineValue.ordinal(downOrdinal), forKey: .downOrdinal)
        try container.encode(TimelineValue.ordinal(upOrdinal), forKey: .upOrdinal)
    }
}

public struct WaitBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var duration: TimeInterval
    public var startOffset: TimeInterval

    public init(
        id: UUID = UUID(),
        duration: TimeInterval,
        startOffset: TimeInterval = 0
    ) {
        self.id = id
        self.duration = duration
        self.startOffset = TimelineValue.time(startOffset)
    }

    private enum CodingKeys: String, CodingKey {
        case id, duration, startOffset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        startOffset = TimelineValue.time(
            try container.decodeIfPresent(TimeInterval.self, forKey: .startOffset) ?? 0
        )
    }
}

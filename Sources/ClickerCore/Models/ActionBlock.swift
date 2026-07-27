import Foundation

public enum MouseButton: String, Codable, Equatable, Sendable {
    case left, right
}

/// 轨迹点，t 为相对块起点的秒数。
public struct TrackPoint: Codable, Equatable, Sendable {
    public var t: TimeInterval
    public var x: Double
    public var y: Double
    public var flags: UInt64

    public init(t: TimeInterval, x: Double, y: Double, flags: UInt64 = 0) {
        self.t = t
        self.x = x
        self.y = y
        self.flags = flags
    }

    private enum CodingKeys: String, CodingKey {
        case t, x, y, flags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        t = try container.decode(TimeInterval.self, forKey: .t)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        flags = try container.decodeIfPresent(UInt64.self, forKey: .flags) ?? 0
    }
}

public struct ScrollStep: Codable, Equatable, Sendable {
    public var t: TimeInterval
    public var dx: Double
    public var dy: Double
    public var flags: UInt64

    public init(t: TimeInterval, dx: Double, dy: Double, flags: UInt64 = 0) {
        self.t = t
        self.dx = dx
        self.dy = dy
        self.flags = flags
    }

    private enum CodingKeys: String, CodingKey {
        case t, dx, dy, flags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        t = try container.decode(TimeInterval.self, forKey: .t)
        dx = try container.decode(Double.self, forKey: .dx)
        dy = try container.decode(Double.self, forKey: .dy)
        flags = try container.decodeIfPresent(UInt64.self, forKey: .flags) ?? 0
    }
}

/// 打字块内的单次按键，t/upT 分别为 keyDown/keyUp 相对块起点的时刻。
public struct Keystroke: Codable, Equatable, Sendable {
    public var t: TimeInterval
    public var keyCode: UInt16
    public var chars: String
    public var upT: TimeInterval
    public var downFlags: UInt64
    public var upFlags: UInt64

    public init(t: TimeInterval, keyCode: UInt16, chars: String,
                upT: TimeInterval? = nil, downFlags: UInt64 = 0, upFlags: UInt64 = 0) {
        self.t = t
        self.keyCode = keyCode
        self.chars = chars
        self.upT = upT ?? t + 0.02
        self.downFlags = downFlags
        self.upFlags = upFlags
    }

    private enum CodingKeys: String, CodingKey {
        case t, keyCode, chars, upT, downFlags, upFlags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        t = try container.decode(TimeInterval.self, forKey: .t)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        chars = try container.decode(String.self, forKey: .chars)
        upT = try container.decodeIfPresent(TimeInterval.self, forKey: .upT) ?? t + 0.02
        downFlags = try container.decodeIfPresent(UInt64.self, forKey: .downFlags) ?? 0
        upFlags = try container.decodeIfPresent(UInt64.self, forKey: .upFlags) ?? 0
    }
}

public struct MoveBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var duration: TimeInterval
    public var points: [TrackPoint]
    public var delayBefore: TimeInterval

    public init(id: UUID = UUID(), duration: TimeInterval, points: [TrackPoint],
                delayBefore: TimeInterval = 0) {
        self.id = id
        self.duration = duration
        self.points = points
        self.delayBefore = delayBefore
    }

    private enum CodingKeys: String, CodingKey {
        case id, duration, points, delayBefore
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        points = try container.decode([TrackPoint].self, forKey: .points)
        delayBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .delayBefore) ?? 0
    }
}

public struct ClickBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var x: Double
    public var y: Double
    public var button: MouseButton
    public var clickCount: Int
    public var delayBefore: TimeInterval
    public var duration: TimeInterval
    public var upX: Double
    public var upY: Double
    public var downFlags: UInt64
    public var upFlags: UInt64

    public init(id: UUID = UUID(), x: Double, y: Double, button: MouseButton, clickCount: Int,
                delayBefore: TimeInterval = 0, duration: TimeInterval = 0.03,
                upX: Double? = nil, upY: Double? = nil,
                downFlags: UInt64 = 0, upFlags: UInt64 = 0) {
        self.id = id
        self.x = x
        self.y = y
        self.button = button
        self.clickCount = clickCount
        self.delayBefore = delayBefore
        self.duration = duration
        self.upX = upX ?? x
        self.upY = upY ?? y
        self.downFlags = downFlags
        self.upFlags = upFlags
    }

    private enum CodingKeys: String, CodingKey {
        case id, x, y, button, clickCount, delayBefore, duration
        case upX, upY, downFlags, upFlags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        button = try container.decode(MouseButton.self, forKey: .button)
        clickCount = try container.decode(Int.self, forKey: .clickCount)
        delayBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .delayBefore) ?? 0
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0.03
        upX = try container.decodeIfPresent(Double.self, forKey: .upX) ?? x
        upY = try container.decodeIfPresent(Double.self, forKey: .upY) ?? y
        downFlags = try container.decodeIfPresent(UInt64.self, forKey: .downFlags) ?? 0
        upFlags = try container.decodeIfPresent(UInt64.self, forKey: .upFlags) ?? 0
    }
}

public struct DragBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var button: MouseButton
    public var duration: TimeInterval
    public var points: [TrackPoint]
    public var delayBefore: TimeInterval

    public init(id: UUID = UUID(), button: MouseButton, duration: TimeInterval,
                points: [TrackPoint], delayBefore: TimeInterval = 0) {
        self.id = id
        self.button = button
        self.duration = duration
        self.points = points
        self.delayBefore = delayBefore
    }

    private enum CodingKeys: String, CodingKey {
        case id, button, duration, points, delayBefore
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        button = try container.decode(MouseButton.self, forKey: .button)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        points = try container.decode([TrackPoint].self, forKey: .points)
        delayBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .delayBefore) ?? 0
    }
}

public struct ScrollBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var x: Double
    public var y: Double
    public var duration: TimeInterval
    public var steps: [ScrollStep]
    public var delayBefore: TimeInterval

    public init(id: UUID = UUID(), x: Double, y: Double, duration: TimeInterval,
                steps: [ScrollStep], delayBefore: TimeInterval = 0) {
        self.id = id
        self.x = x
        self.y = y
        self.duration = duration
        self.steps = steps
        self.delayBefore = delayBefore
    }

    private enum CodingKeys: String, CodingKey {
        case id, x, y, duration, steps, delayBefore
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        steps = try container.decode([ScrollStep].self, forKey: .steps)
        delayBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .delayBefore) ?? 0
    }
}

public struct TypeTextBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var keystrokes: [Keystroke]
    public var delayBefore: TimeInterval
    public var duration: TimeInterval

    public init(id: UUID = UUID(), text: String, keystrokes: [Keystroke],
                delayBefore: TimeInterval = 0, duration: TimeInterval? = nil) {
        self.id = id
        self.text = text
        self.keystrokes = keystrokes
        self.delayBefore = delayBefore
        self.duration = duration ?? Self.derivedDuration(text: text, keystrokes: keystrokes)
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, keystrokes, delayBefore, duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        keystrokes = try container.decode([Keystroke].self, forKey: .keystrokes)
        delayBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .delayBefore) ?? 0
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
            ?? Self.derivedDuration(text: text, keystrokes: keystrokes)
    }

    private static func derivedDuration(text: String, keystrokes: [Keystroke]) -> TimeInterval {
        if let lastUpT = keystrokes.map(\.upT).max() {
            return lastUpT
        }
        guard !text.isEmpty else { return 0 }
        return Double(text.count - 1) * 0.06 + 0.02
    }
}

public struct ShortcutBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var keyCode: UInt16
    /// keyDown 时的修饰键标志。
    public var flags: UInt64
    public var delayBefore: TimeInterval
    public var upFlags: UInt64
    public var duration: TimeInterval

    public init(id: UUID = UUID(), keyCode: UInt16, flags: UInt64,
                delayBefore: TimeInterval = 0, upFlags: UInt64? = nil,
                duration: TimeInterval = 0.02) {
        self.id = id
        self.keyCode = keyCode
        self.flags = flags
        self.delayBefore = delayBefore
        self.upFlags = upFlags ?? flags
        self.duration = duration
    }

    private enum CodingKeys: String, CodingKey {
        case id, keyCode, flags, delayBefore, upFlags, duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        flags = try container.decode(UInt64.self, forKey: .flags)
        delayBefore = try container.decodeIfPresent(TimeInterval.self, forKey: .delayBefore) ?? 0
        upFlags = try container.decodeIfPresent(UInt64.self, forKey: .upFlags) ?? flags
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0.02
    }
}

public struct WaitBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var duration: TimeInterval

    public init(id: UUID = UUID(), duration: TimeInterval) {
        self.id = id
        self.duration = duration
    }
}

/// 语义化动作块。case 名即 JSON 判别字段。
public enum ActionBlock: Codable, Equatable, Sendable, Identifiable {
    case move(MoveBlock)
    case click(ClickBlock)
    case drag(DragBlock)
    case scroll(ScrollBlock)
    case typeText(TypeTextBlock)
    case shortcut(ShortcutBlock)
    case wait(WaitBlock)

    public var id: UUID {
        switch self {
        case .move(let block): return block.id
        case .click(let block): return block.id
        case .drag(let block): return block.id
        case .scroll(let block): return block.id
        case .typeText(let block): return block.id
        case .shortcut(let block): return block.id
        case .wait(let block): return block.id
        }
    }

    public var delayBefore: TimeInterval {
        switch self {
        case .move(let block): return block.delayBefore
        case .click(let block): return block.delayBefore
        case .drag(let block): return block.delayBefore
        case .scroll(let block): return block.delayBefore
        case .typeText(let block): return block.delayBefore
        case .shortcut(let block): return block.delayBefore
        case .wait: return 0
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .move(let block): return block.duration
        case .click(let block): return block.duration
        case .drag(let block): return block.duration
        case .scroll(let block): return block.duration
        case .typeText(let block): return block.duration
        case .shortcut(let block): return block.duration
        case .wait(let block): return block.duration
        }
    }

    public func withDelayBefore(_ delayBefore: TimeInterval) -> ActionBlock {
        switch self {
        case .move(var block):
            block.delayBefore = delayBefore
            return .move(block)
        case .click(var block):
            block.delayBefore = delayBefore
            return .click(block)
        case .drag(var block):
            block.delayBefore = delayBefore
            return .drag(block)
        case .scroll(var block):
            block.delayBefore = delayBefore
            return .scroll(block)
        case .typeText(var block):
            block.delayBefore = delayBefore
            return .typeText(block)
        case .shortcut(var block):
            block.delayBefore = delayBefore
            return .shortcut(block)
        case .wait:
            return self
        }
    }
}

/// 一个脚本 = 名称 + 动作块 + 回放设置。
public struct Script: Codable, Equatable, Sendable, Identifiable {
    public static let currentSchemaVersion = 2

    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var blocks: [ActionBlock]
    public var repeatCount: Int
    public var repeatForever: Bool
    public var repeatInterval: TimeInterval
    public var schemaVersion: Int
    public var trailingDelay: TimeInterval
    public var targetBundleIdentifier: String?

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(),
                modifiedAt: Date = Date(), blocks: [ActionBlock] = [],
                repeatCount: Int = 1, repeatForever: Bool = false,
                repeatInterval: TimeInterval = 0,
                schemaVersion: Int = Script.currentSchemaVersion,
                trailingDelay: TimeInterval = 0,
                targetBundleIdentifier: String? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.blocks = blocks
        self.repeatCount = repeatCount
        self.repeatForever = repeatForever
        self.repeatInterval = repeatInterval
        self.schemaVersion = schemaVersion
        self.trailingDelay = trailingDelay
        self.targetBundleIdentifier = targetBundleIdentifier
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, modifiedAt, blocks
        case repeatCount, repeatForever, repeatInterval
        case schemaVersion, trailingDelay, targetBundleIdentifier
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        blocks = try container.decode([ActionBlock].self, forKey: .blocks)
        repeatCount = try container.decode(Int.self, forKey: .repeatCount)
        repeatForever = try container.decode(Bool.self, forKey: .repeatForever)
        repeatInterval = try container.decode(TimeInterval.self, forKey: .repeatInterval)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        trailingDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .trailingDelay) ?? 0
        targetBundleIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .targetBundleIdentifier
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(blocks, forKey: .blocks)
        try container.encode(repeatCount, forKey: .repeatCount)
        try container.encode(repeatForever, forKey: .repeatForever)
        try container.encode(repeatInterval, forKey: .repeatInterval)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(trailingDelay, forKey: .trailingDelay)
        try container.encodeIfPresent(targetBundleIdentifier, forKey: .targetBundleIdentifier)
    }
}

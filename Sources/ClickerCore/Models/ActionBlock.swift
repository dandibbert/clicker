import Foundation

public enum MouseButton: String, Codable, Equatable, Sendable {
    case left, right
}

/// 轨迹点，t 为相对块起点的秒数。
public struct TrackPoint: Codable, Equatable, Sendable {
    public var t: TimeInterval
    public var x: Double
    public var y: Double
    public init(t: TimeInterval, x: Double, y: Double) {
        self.t = t; self.x = x; self.y = y
    }
}

public struct ScrollStep: Codable, Equatable, Sendable {
    public var t: TimeInterval
    public var dx: Double
    public var dy: Double
    public init(t: TimeInterval, dx: Double, dy: Double) {
        self.t = t; self.dx = dx; self.dy = dy
    }
}

/// 打字块内的单次按键（keyDown 时刻）。
public struct Keystroke: Codable, Equatable, Sendable {
    public var t: TimeInterval
    public var keyCode: UInt16
    public var chars: String
    public init(t: TimeInterval, keyCode: UInt16, chars: String) {
        self.t = t; self.keyCode = keyCode; self.chars = chars
    }
}

public struct MoveBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var duration: TimeInterval
    public var points: [TrackPoint]
    public init(id: UUID = UUID(), duration: TimeInterval, points: [TrackPoint]) {
        self.id = id; self.duration = duration; self.points = points
    }
}

public struct ClickBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var x: Double
    public var y: Double
    public var button: MouseButton
    public var clickCount: Int
    public init(id: UUID = UUID(), x: Double, y: Double, button: MouseButton, clickCount: Int) {
        self.id = id; self.x = x; self.y = y; self.button = button; self.clickCount = clickCount
    }
}

public struct DragBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var button: MouseButton
    public var duration: TimeInterval
    public var points: [TrackPoint]
    public init(id: UUID = UUID(), button: MouseButton, duration: TimeInterval, points: [TrackPoint]) {
        self.id = id; self.button = button; self.duration = duration; self.points = points
    }
}

public struct ScrollBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var x: Double
    public var y: Double
    public var duration: TimeInterval
    public var steps: [ScrollStep]
    public init(id: UUID = UUID(), x: Double, y: Double, duration: TimeInterval, steps: [ScrollStep]) {
        self.id = id; self.x = x; self.y = y; self.duration = duration; self.steps = steps
    }
}

public struct TypeTextBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var text: String
    public var keystrokes: [Keystroke]
    public init(id: UUID = UUID(), text: String, keystrokes: [Keystroke]) {
        self.id = id; self.text = text; self.keystrokes = keystrokes
    }
}

public struct ShortcutBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var keyCode: UInt16
    public var flags: UInt64
    public init(id: UUID = UUID(), keyCode: UInt16, flags: UInt64) {
        self.id = id; self.keyCode = keyCode; self.flags = flags
    }
}

public struct WaitBlock: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var duration: TimeInterval
    public init(id: UUID = UUID(), duration: TimeInterval) {
        self.id = id; self.duration = duration
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
        case .move(let b): return b.id
        case .click(let b): return b.id
        case .drag(let b): return b.id
        case .scroll(let b): return b.id
        case .typeText(let b): return b.id
        case .shortcut(let b): return b.id
        case .wait(let b): return b.id
        }
    }
}

/// 一个脚本 = 名称 + 动作块 + 回放设置。
public struct Script: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var modifiedAt: Date
    public var blocks: [ActionBlock]
    public var repeatCount: Int
    public var repeatForever: Bool
    public var repeatInterval: TimeInterval

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(),
                modifiedAt: Date = Date(), blocks: [ActionBlock] = [],
                repeatCount: Int = 1, repeatForever: Bool = false,
                repeatInterval: TimeInterval = 0) {
        self.id = id; self.name = name; self.createdAt = createdAt
        self.modifiedAt = modifiedAt; self.blocks = blocks
        self.repeatCount = repeatCount; self.repeatForever = repeatForever
        self.repeatInterval = repeatInterval
    }
}

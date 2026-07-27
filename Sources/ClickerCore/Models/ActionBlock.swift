import Foundation

/// 语义化动作块。startOffset 是唯一 canonical 块起点。
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
        case .move(let block): block.id
        case .click(let block): block.id
        case .drag(let block): block.id
        case .scroll(let block): block.id
        case .typeText(let block): block.id
        case .shortcut(let block): block.id
        case .wait(let block): block.id
        }
    }

    public var startOffset: TimeInterval {
        switch self {
        case .move(let block): block.startOffset
        case .click(let block): block.startOffset
        case .drag(let block): block.startOffset
        case .scroll(let block): block.startOffset
        case .typeText(let block): block.startOffset
        case .shortcut(let block): block.startOffset
        case .wait(let block): block.startOffset
        }
    }

    /// 仅用于 v1-v3 解码迁移；v4 编码与回放均不读取该值。
    public var delayBefore: TimeInterval {
        switch self {
        case .move(let block): block.delayBefore
        case .click(let block): block.delayBefore
        case .drag(let block): block.delayBefore
        case .scroll(let block): block.delayBefore
        case .typeText(let block): block.delayBefore
        case .shortcut(let block): block.delayBefore
        case .wait: 0
        }
    }

    /// 仅用于 v3 解码迁移；v4 编码与回放均不读取该值。
    public var overlapBefore: TimeInterval {
        switch self {
        case .move(let block): block.overlapBefore
        case .click(let block): block.overlapBefore
        case .drag(let block): block.overlapBefore
        case .scroll(let block): block.overlapBefore
        case .typeText(let block): block.overlapBefore
        case .shortcut(let block): block.overlapBefore
        case .wait: 0
        }
    }

    public var duration: TimeInterval {
        switch self {
        case .move(let block): block.duration
        case .click(let block): block.duration
        case .drag(let block): block.duration
        case .scroll(let block): block.duration
        case .typeText(let block): block.duration
        case .shortcut(let block): block.duration
        case .wait(let block): block.duration
        }
    }

    public var effectiveDuration: TimeInterval {
        let declared = TimelineValue.time(duration)
        let latestAtom: TimeInterval
        switch self {
        case .move(let block):
            latestAtom = block.points.map { TimelineValue.time($0.t) }.max() ?? 0
        case .click:
            latestAtom = declared
        case .drag(let block):
            latestAtom = block.points.map { TimelineValue.time($0.t) }.max() ?? 0
        case .scroll(let block):
            latestAtom = block.steps.map { TimelineValue.time($0.t) }.max() ?? 0
        case .typeText(let block):
            latestAtom = block.keystrokes.map {
                max(TimelineValue.time($0.t), TimelineValue.time($0.upT))
            }.max() ?? 0
        case .shortcut, .wait:
            latestAtom = declared
        }
        return max(declared, latestAtom)
    }

    public var timelineEndOffset: TimeInterval {
        TimelineValue.adding(startOffset, effectiveDuration)
    }

    public func withStartOffset(_ startOffset: TimeInterval) -> ActionBlock {
        switch self {
        case .move(var block):
            block.startOffset = TimelineValue.time(startOffset)
            return .move(block)
        case .click(var block):
            block.startOffset = TimelineValue.time(startOffset)
            return .click(block)
        case .drag(var block):
            block.startOffset = TimelineValue.time(startOffset)
            return .drag(block)
        case .scroll(var block):
            block.startOffset = TimelineValue.time(startOffset)
            return .scroll(block)
        case .typeText(var block):
            block.startOffset = TimelineValue.time(startOffset)
            return .typeText(block)
        case .shortcut(var block):
            block.startOffset = TimelineValue.time(startOffset)
            return .shortcut(block)
        case .wait(var block):
            block.startOffset = TimelineValue.time(startOffset)
            return .wait(block)
        }
    }

    public func withDelayBefore(_ delayBefore: TimeInterval) -> ActionBlock {
        mapAction { $0.delay = delayBefore }
    }

    public func withOverlapBefore(_ overlapBefore: TimeInterval) -> ActionBlock {
        mapAction { $0.overlap = overlapBefore }
    }

    public func duplicated() -> ActionBlock {
        switch self {
        case .move(var block): block.id = UUID(); return .move(block)
        case .click(var block): block.id = UUID(); return .click(block)
        case .drag(var block): block.id = UUID(); return .drag(block)
        case .scroll(var block): block.id = UUID(); return .scroll(block)
        case .typeText(var block): block.id = UUID(); return .typeText(block)
        case .shortcut(var block): block.id = UUID(); return .shortcut(block)
        case .wait(var block): block.id = UUID(); return .wait(block)
        }
    }

    var atomOrdinals: [Int] {
        switch self {
        case .move(let block):
            block.points.map(\.ordinal)
        case .click(let block):
            [block.downOrdinal, block.upOrdinal]
        case .drag(let block):
            block.points.map(\.ordinal) + [block.upOrdinal]
        case .scroll(let block):
            block.steps.map(\.ordinal)
        case .typeText(let block):
            block.keystrokes.flatMap { [$0.downOrdinal, $0.upOrdinal] }
        case .shortcut(let block):
            [block.downOrdinal, block.upOrdinal]
        case .wait:
            []
        }
    }

    func rebasingAtomOrdinals(_ replacements: [Int: Int]) -> ActionBlock {
        func replacement(for ordinal: Int) -> Int {
            replacements[ordinal] ?? ordinal
        }

        switch self {
        case .move(var block):
            for index in block.points.indices {
                block.points[index].ordinal = replacement(for: block.points[index].ordinal)
            }
            return .move(block)
        case .click(var block):
            block.downOrdinal = replacement(for: block.downOrdinal)
            block.upOrdinal = replacement(for: block.upOrdinal)
            return .click(block)
        case .drag(var block):
            for index in block.points.indices {
                block.points[index].ordinal = replacement(for: block.points[index].ordinal)
            }
            block.upOrdinal = replacement(for: block.upOrdinal)
            return .drag(block)
        case .scroll(var block):
            for index in block.steps.indices {
                block.steps[index].ordinal = replacement(for: block.steps[index].ordinal)
            }
            return .scroll(block)
        case .typeText(var block):
            for index in block.keystrokes.indices {
                block.keystrokes[index].downOrdinal = replacement(
                    for: block.keystrokes[index].downOrdinal
                )
                block.keystrokes[index].upOrdinal = replacement(
                    for: block.keystrokes[index].upOrdinal
                )
            }
            return .typeText(block)
        case .shortcut(var block):
            block.downOrdinal = replacement(for: block.downOrdinal)
            block.upOrdinal = replacement(for: block.upOrdinal)
            return .shortcut(block)
        case .wait:
            return self
        }
    }

    func clearingLegacyTiming() -> ActionBlock {
        mapAction {
            $0.delay = 0
            $0.overlap = 0
        }
    }

    func assigningLegacyOrdinals(next: inout Int) -> ActionBlock {
        switch self {
        case .move(var block):
            for index in block.points.indices {
                block.points[index].ordinal = next
                next += 1
            }
            return .move(block)
        case .click(var block):
            block.downOrdinal = next
            next += 1
            block.upOrdinal = next
            next += 1
            return .click(block)
        case .drag(var block):
            for index in block.points.indices {
                block.points[index].ordinal = next
                next += 1
            }
            if block.hasRecordedMouseUp, let last = block.points.last {
                block.upOrdinal = last.ordinal
            } else if !block.points.isEmpty {
                block.upOrdinal = next
                next += 1
            }
            return .drag(block)
        case .scroll(var block):
            for index in block.steps.indices {
                block.steps[index].ordinal = next
                next += 1
            }
            return .scroll(block)
        case .typeText(var block):
            for index in block.keystrokes.indices {
                block.keystrokes[index].downOrdinal = next
                next += 1
                block.keystrokes[index].upOrdinal = next
                next += 1
            }
            return .typeText(block)
        case .shortcut(var block):
            block.downOrdinal = next
            next += 1
            block.upOrdinal = next
            next += 1
            return .shortcut(block)
        case .wait:
            return self
        }
    }

    private func mapAction(_ update: (inout LegacyTiming) -> Void) -> ActionBlock {
        switch self {
        case .move(var block):
            var timing = LegacyTiming(block.delayBefore, block.overlapBefore)
            update(&timing)
            block.delayBefore = timing.delay
            block.overlapBefore = timing.overlap
            return .move(block)
        case .click(var block):
            var timing = LegacyTiming(block.delayBefore, block.overlapBefore)
            update(&timing)
            block.delayBefore = timing.delay
            block.overlapBefore = timing.overlap
            return .click(block)
        case .drag(var block):
            var timing = LegacyTiming(block.delayBefore, block.overlapBefore)
            update(&timing)
            block.delayBefore = timing.delay
            block.overlapBefore = timing.overlap
            return .drag(block)
        case .scroll(var block):
            var timing = LegacyTiming(block.delayBefore, block.overlapBefore)
            update(&timing)
            block.delayBefore = timing.delay
            block.overlapBefore = timing.overlap
            return .scroll(block)
        case .typeText(var block):
            var timing = LegacyTiming(block.delayBefore, block.overlapBefore)
            update(&timing)
            block.delayBefore = timing.delay
            block.overlapBefore = timing.overlap
            return .typeText(block)
        case .shortcut(var block):
            var timing = LegacyTiming(block.delayBefore, block.overlapBefore)
            update(&timing)
            block.delayBefore = timing.delay
            block.overlapBefore = timing.overlap
            return .shortcut(block)
        case .wait:
            return self
        }
    }

    private struct LegacyTiming {
        var delay: TimeInterval
        var overlap: TimeInterval

        init(_ delay: TimeInterval, _ overlap: TimeInterval) {
            self.delay = delay
            self.overlap = overlap
        }
    }
}

import Foundation

/// UI 时间轴结构编辑的纯函数。只平移拼接点后的后缀，不改块内相对时间。
public enum TimelineMutation {
    public static func inserting(
        _ block: ActionBlock,
        at requestedIndex: Int,
        in blocks: [ActionBlock]
    ) -> [ActionBlock] {
        splicing(block, at: requestedIndex, in: blocks)
    }

    public static func deleting(
        at requestedIndex: Int,
        in blocks: [ActionBlock]
    ) -> [ActionBlock] {
        guard blocks.indices.contains(requestedIndex) else { return blocks }
        let prefix = Array(blocks[..<requestedIndex])
        let suffixStartIndex = blocks.index(after: requestedIndex)
        let suffix = Array(blocks[suffixStartIndex...])
        guard let suffixAnchor = suffix.first?.startOffset else { return prefix }

        let prefixEnd = prefix.map(\.timelineEndOffset).max() ?? 0
        let translatedSuffix = translated(suffix, by: prefixEnd - suffixAnchor)
        return prefix + rebasedGroup(translatedSuffix, avoiding: prefix)
    }

    public static func duplicating(
        at index: Int,
        in blocks: [ActionBlock]
    ) -> [ActionBlock] {
        guard blocks.indices.contains(index) else { return blocks }
        return inserting(blocks[index].duplicated(), at: index + 1, in: blocks)
    }

    /// destination 是删除源块后的最终数组下标。
    public static func moving(
        from source: Int,
        to destination: Int,
        in blocks: [ActionBlock]
    ) -> [ActionBlock] {
        guard blocks.indices.contains(source) else { return blocks }
        let moved = blocks[source]
        let withoutSource = deleting(at: source, in: blocks)
        let target = min(max(0, destination), withoutSource.count)
        return splicing(moved, at: target, in: withoutSource)
    }

    public static func deleting(
        atOffsets offsets: IndexSet,
        in blocks: [ActionBlock]
    ) -> [ActionBlock] {
        offsets.sorted(by: >).reduce(blocks) { current, index in
            deleting(at: index, in: current)
        }
    }

    /// 与 SwiftUI onMove 的 toOffset 语义一致。
    public static func moving(
        fromOffsets offsets: IndexSet,
        toOffset destination: Int,
        in blocks: [ActionBlock]
    ) -> [ActionBlock] {
        let sources = offsets.sorted()
        guard !sources.isEmpty,
              sources.allSatisfy(blocks.indices.contains) else {
            return blocks
        }

        let movingBlocks = sources.map { blocks[$0] }
        var result = deleting(atOffsets: offsets, in: blocks)
        let removedBeforeDestination = sources.filter { $0 < destination }.count
        var target = min(max(0, destination - removedBeforeDestination), result.count)
        for block in movingBlocks {
            result = splicing(block, at: target, in: result)
            target += 1
        }
        return result
    }

    private static func splicing(
        _ block: ActionBlock,
        at requestedIndex: Int,
        in blocks: [ActionBlock]
    ) -> [ActionBlock] {
        let index = min(max(0, requestedIndex), blocks.count)
        let prefix = Array(blocks[..<index])
        let suffix = Array(blocks[index...])
        let prefixEnd = prefix.map(\.timelineEndOffset).max() ?? 0
        let prepared = rebasedGroup([block], avoiding: prefix).first ?? block
        let inserted = prepared.withStartOffset(prefixEnd)

        guard let suffixAnchor = suffix.first?.startOffset else {
            return prefix + [inserted]
        }
        let shift = inserted.timelineEndOffset - suffixAnchor
        let translatedSuffix = translated(suffix, by: shift)
        let rebasedSuffix = rebasedGroup(
            translatedSuffix,
            avoiding: prefix + [inserted]
        )
        return prefix + [inserted] + rebasedSuffix
    }

    private static func rebasedGroup(
        _ source: [ActionBlock],
        avoiding blocks: [ActionBlock]
    ) -> [ActionBlock] {
        let sourceOrdinals = Array(Set(source.flatMap(\.atomOrdinals))).sorted()
        guard !sourceOrdinals.isEmpty else { return source }

        var used = Set(blocks.flatMap(\.atomOrdinals))
        var candidate = used.max().flatMap { maximum in
            maximum < Int.max ? maximum + 1 : nil
        } ?? 0
        var replacements: [Int: Int] = [:]

        for ordinal in sourceOrdinals {
            candidate = nextUnusedOrdinal(startingAt: candidate, used: used)
            replacements[ordinal] = candidate
            used.insert(candidate)
            candidate = TimelineValue.nextOrdinal(after: candidate)
        }
        return source.map { $0.rebasingAtomOrdinals(replacements) }
    }

    private static func nextUnusedOrdinal(
        startingAt start: Int,
        used: Set<Int>
    ) -> Int {
        var candidate = max(0, start)
        let initial = candidate
        while used.contains(candidate) {
            candidate = candidate == Int.max ? 0 : candidate + 1
            if candidate == initial { return candidate }
        }
        return candidate
    }

    private static func translated(
        _ blocks: [ActionBlock],
        by delta: TimeInterval
    ) -> [ActionBlock] {
        guard delta.isFinite, delta != 0 else { return blocks }
        return blocks.map { block in
            let translatedStart: TimeInterval
            if delta > 0 {
                translatedStart = TimelineValue.adding(block.startOffset, delta)
            } else {
                translatedStart = max(0, block.startOffset - TimelineValue.time(-delta))
            }
            return block.withStartOffset(translatedStart)
        }
    }
}

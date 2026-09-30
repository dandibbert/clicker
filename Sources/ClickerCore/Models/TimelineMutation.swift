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

    /// Replace an edited value without moving its start. The original overlap
    /// cohort (including holds from earlier blocks) keeps its absolute starts.
    /// Only the following non-overlapping suffix follows the change in that
    /// cohort's end; its gaps and internal overlaps remain intact.
    public static func replacing(
        at index: Int,
        with replacement: ActionBlock,
        in blocks: [ActionBlock]
    ) -> [ActionBlock] {
        guard blocks.indices.contains(index) else { return blocks }
        let original = blocks[index]
        let updated = replacement.withStartOffset(original.startOffset)
        guard updated != original else { return blocks }

        var result = blocks
        result[index] = updated
        var suffixIndex = index + 1
        var oldCohortEnd = blocks[...index].map(\.timelineEndOffset).max() ?? 0
        // Equality is a sequential boundary, not an overlap. In particular a
        // zero-duration wait can grow and push a following action at its start.
        while suffixIndex < blocks.count,
              blocks[suffixIndex].startOffset < oldCohortEnd {
            oldCohortEnd = max(oldCohortEnd, blocks[suffixIndex].timelineEndOffset)
            suffixIndex += 1
        }
        let newCohortEnd = result[..<suffixIndex].map(\.timelineEndOffset).max() ?? 0
        let suffix = translated(
            Array(result[suffixIndex...]),
            from: oldCohortEnd,
            to: newCohortEnd
        )
        result.replaceSubrange(suffixIndex..., with: suffix)

        let replacedText: Bool
        if case .typeText(let oldText) = original,
           case .typeText(let newText) = updated {
            replacedText = oldText.text != newText.text
        } else {
            replacedText = false
        }
        // Duration-only changes retain captured equal-time ordering. New text
        // atoms need fresh ordinals on both sides of the edit's splice boundary.
        if replacedText || original.atomOrdinals != updated.atomOrdinals {
            result = rebasedReplacement(at: index, original: original, in: result)
        }
        return result
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
        let translatedSuffix = translated(suffix, from: suffixAnchor, to: prefixEnd)
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
        let translatedSuffix = translated(
            suffix,
            from: suffixAnchor,
            to: inserted.timelineEndOffset
        )
        let rebasedSuffix = rebasedGroup(
            translatedSuffix,
            avoiding: prefix + [inserted]
        )
        return prefix + [inserted] + rebasedSuffix
    }

    /// Retained events must share one mapping across both sides of an edit.
    /// A held key's initial press and later autorepeat can live in different
    /// blocks but still refer to the same captured keyUp ordinal.
    private static func rebasedReplacement(
        at index: Int,
        original: ActionBlock,
        in blocks: [ActionBlock]
    ) -> [ActionBlock] {
        let retained = blocks.enumerated().filter { $0.offset != index }.map(\.element)
        let retainedOrdinals = Array(Set(retained.flatMap(\.atomOrdinals))).sorted()
        let newOrdinals = Array(Set(blocks[index].atomOrdinals)).sorted()
        let insertionAnchor = original.atomOrdinals.min()
            ?? blocks[(index + 1)...].flatMap(\.atomOrdinals).min()
        let insertionIndex = insertionAnchor.flatMap { anchor in
            retainedOrdinals.firstIndex { $0 >= anchor }
        } ?? retainedOrdinals.count
        var retainedMapping: [Int: Int] = [:]
        var replacementMapping: [Int: Int] = [:]
        var nextOrdinal = 0

        for ordinal in retainedOrdinals[..<insertionIndex] {
            retainedMapping[ordinal] = nextOrdinal
            nextOrdinal = TimelineValue.nextOrdinal(after: nextOrdinal)
        }
        for ordinal in newOrdinals {
            replacementMapping[ordinal] = nextOrdinal
            nextOrdinal = TimelineValue.nextOrdinal(after: nextOrdinal)
        }
        for ordinal in retainedOrdinals[insertionIndex...] {
            retainedMapping[ordinal] = nextOrdinal
            nextOrdinal = TimelineValue.nextOrdinal(after: nextOrdinal)
        }
        return blocks.enumerated().map { blockIndex, block in
            block.rebasingAtomOrdinals(blockIndex == index ? replacementMapping : retainedMapping)
        }
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
        from oldAnchor: TimeInterval,
        to newAnchor: TimeInterval
    ) -> [ActionBlock] {
        guard oldAnchor != newAnchor else { return blocks }
        var translatedEnds: [TimeInterval: TimeInterval] = [oldAnchor: newAnchor]
        return blocks.map { block in
            let relativeStart = block.startOffset - oldAnchor
            let translatedStart: TimeInterval
            if let joinedEnd = translatedEnds[block.startOffset] {
                translatedStart = joinedEnd
            } else if relativeStart >= 0 {
                // Anchoring the boundary directly avoids a rounded
                // oldStart + (newEnd - oldEnd) ordering a new press before release.
                translatedStart = TimelineValue.adding(newAnchor, relativeStart)
            } else {
                translatedStart = max(0, newAnchor - TimelineValue.time(-relativeStart))
            }
            let translatedBlock = block.withStartOffset(translatedStart)
            // Preserve joins inside the suffix too, even after repeated moves.
            // Overlapping blocks with the same old end can round to different
            // new ends. A following press must wait for the latest release.
            translatedEnds[block.timelineEndOffset] = max(
                translatedEnds[block.timelineEndOffset] ?? 0,
                translatedBlock.timelineEndOffset
            )
            return translatedBlock
        }
    }
}

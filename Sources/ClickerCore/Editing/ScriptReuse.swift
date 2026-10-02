import Foundation

/// An in-app clipboard snapshot. Its times are relative to the earliest copied
/// block, so a discontiguous selection keeps its original gaps and overlaps.
public struct ActionClipboard: Equatable, Sendable {
    public let blocks: [ActionBlock]

    public init(blocks: [ActionBlock]) {
        let anchor = blocks.map(\.startOffset).min() ?? 0
        self.blocks = TimelineMutation.translated(blocks, from: anchor, to: 0)
    }

    public var isEmpty: Bool { blocks.isEmpty }
    public var count: Int { blocks.count }
}

/// Pure reuse operations shared by menu commands, buttons and keyboard actions.
public enum ScriptReuse {
    /// Copies are inert until explicitly run. Never inherit global shortcuts or
    /// an opt-in that can switch another application's focus.
    public static func duplicate(
        _ script: Script,
        name: String? = nil,
        now: Date = Date()
    ) -> Script {
        var copy = script
        copy.id = UUID()
        copy.name = name ?? script.name
        copy.createdAt = now
        copy.modifiedAt = now
        copy.blocks = script.blocks.map { $0.duplicated() }
        copy.schemaVersion = Script.currentSchemaVersion
        copy.playbackShortcut = nil
        copy.startApplicationBeforePlayback = false
        return copy
    }

    public static func copyActions(
        from script: Script,
        selectedBlockIDs: Set<UUID>
    ) -> ActionClipboard? {
        let selected = script.blocks.filter { selectedBlockIDs.contains($0.id) }
        guard !selected.isEmpty else { return nil }
        return ActionClipboard(blocks: selected)
    }

    /// Every paste gets new identities, including repeated pastes of one snapshot.
    /// The source group is inserted as one unit, never as sequential single blocks.
    public static func pasteActions(
        _ clipboard: ActionClipboard,
        at index: Int,
        in blocks: [ActionBlock]
    ) -> [ActionBlock] {
        TimelineMutation.inserting(
            clipboard.blocks.map { $0.duplicated() },
            at: index,
            in: blocks
        )
    }

    /// Builds a one-run snapshot from exactly the selected blocks. Expansion is
    /// subsequently performed on these blocks alone, preventing overlapping but
    /// unselected input from entering a trial. IDs stay intact for row highlights.
    public static func trial(
        _ script: Script,
        selectedBlockIDs: Set<UUID>
    ) -> Script? {
        guard let copied = copyActions(from: script, selectedBlockIDs: selectedBlockIDs) else {
            return nil
        }
        var trial = script
        trial.blocks = copied.blocks
        trial.repeatCount = 1
        trial.repeatForever = false
        trial.repeatInterval = 0
        trial.trailingDelay = 0
        trial.playbackShortcut = nil
        return trial
    }
}

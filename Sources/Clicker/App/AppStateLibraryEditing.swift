import Foundation
import ClickerCore

struct PlaybackStartRequest: Identifiable {
    let id = UUID()
    let script: Script
    let appIdentifier: String
    let restoresClicker: Bool
}

struct ScriptLibraryEdit {
    let before: Script?
    let after: Script?
}

@MainActor
extension AppState {
    var canUndo: Bool { canEditScripts && !undoEntries.isEmpty }
    var canRedo: Bool { canEditScripts && !redoEntries.isEmpty }
    var hasCopiedActions: Bool { actionClipboard != nil }

    func recordEdit(before: Script?, after: Script?) {
        guard !isApplyingHistory, before != after else { return }
        undoEntries.append(ScriptLibraryEdit(before: before, after: after))
        if undoEntries.count > 100 { undoEntries.removeFirst(undoEntries.count - 100) }
        redoEntries.removeAll()
    }

    @discardableResult
    func createBlankScript() -> Bool {
        let script = Script(name: "新建脚本")
        guard create(script) else { return false }
        selectedScriptID = script.id
        return true
    }

    func copyActions(scriptID: UUID, blockIDs: Set<UUID>) {
        guard let script = scripts.first(where: { $0.id == scriptID }),
              let copied = ScriptReuse.copyActions(from: script, selectedBlockIDs: blockIDs) else { return }
        actionClipboard = copied
    }

    @discardableResult
    func pasteActions(into scriptID: UUID, at index: Int) -> Bool {
        guard canEditScripts, let clipboard = actionClipboard,
              var script = scripts.first(where: { $0.id == scriptID }) else { return false }
        script.blocks = ScriptReuse.pasteActions(clipboard, at: index, in: script.blocks)
        return update(script)
    }

    @discardableResult
    func importScript(_ script: Script, replaceExisting: Bool = false) -> Bool {
        guard canEditScripts else { return false }
        // Files never automatically acquire this machine's global shortcuts or start-app behavior.
        var imported = ScriptReuse.duplicate(script, name: script.name)
        if replaceExisting, let existing = scripts.first(where: { $0.id == script.id }) {
            imported.id = existing.id
            imported.createdAt = existing.createdAt
            guard update(imported) else { return false }
        } else {
            if scripts.contains(where: { $0.id == script.id || $0.name == script.name }) {
                imported.name += " 导入副本"
            }
            guard create(imported) else { return false }
        }
        selectedScriptID = imported.id
        return true
    }

    @discardableResult
    func exportScript(id: UUID, to url: URL) -> Bool {
        guard let script = scripts.first(where: { $0.id == id }) else { return false }
        do {
            try ScriptJSONCodec.encode(script).write(to: url, options: .atomic)
            persistenceIssue = nil
            return true
        } catch {
            persistenceIssue = makePersistenceIssue(from: error, fallback: .temporaryWrite)
            return false
        }
    }

    func refreshRecentlyDeleted() {
        recentlyDeletedScripts = (store as? ScriptRecovering)?.loadRecentlyDeleted().scripts ?? []
    }

    @discardableResult
    func restoreDeletedScript(id: UUID) -> Bool {
        guard canEditScripts, let recovery = store as? ScriptRecovering else { return false }
        do {
            let restored = try recovery.restoreRecentlyDeleted(id: id)
            scripts.append(restored)
            selectedScriptID = restored.id
            recordEdit(before: nil, after: restored)
            refreshRecentlyDeleted()
            persistenceIssue = nil
            return true
        } catch {
            persistenceIssue = makePersistenceIssue(from: error, fallback: .replace)
            return false
        }
    }

    func undo() {
        guard canUndo, let edit = undoEntries.last else { return }
        guard applyHistory(target: edit.before, replacing: edit.after) else { return }
        undoEntries.removeLast()
        redoEntries.append(edit)
    }

    func redo() {
        guard canRedo, let edit = redoEntries.last else { return }
        guard applyHistory(target: edit.after, replacing: edit.before) else { return }
        redoEntries.removeLast()
        undoEntries.append(edit)
    }

    private func applyHistory(target: Script?, replacing current: Script?) -> Bool {
        isApplyingHistory = true
        defer { isApplyingHistory = false }
        do {
            if let target {
                // Undo deletion uses the recovery API so a later redo can archive safely again.
                if current == nil, let recovery = store as? ScriptRecovering,
                   recovery.loadRecentlyDeleted().scripts.contains(where: { $0.id == target.id }) {
                    _ = try recovery.restoreRecentlyDeleted(id: target.id)
                } else {
                    try store.save(target)
                }
                if let index = scripts.firstIndex(where: { $0.id == target.id }) {
                    scripts[index] = target
                } else {
                    scripts.append(target)
                }
                selectedScriptID = target.id
            } else if let current {
                try store.delete(id: current.id)
                scripts.removeAll { $0.id == current.id }
                if selectedScriptID == current.id { selectedScriptID = scripts.first?.id }
            }
            persistenceIssue = nil
            refreshRecentlyDeleted()
            return true
        } catch {
            persistenceIssue = makePersistenceIssue(from: error, fallback: target == nil ? .delete : .replace)
            return false
        }
    }
}

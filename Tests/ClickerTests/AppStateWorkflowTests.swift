import XCTest
import ClickerCore
@testable import Clicker

@MainActor
final class AppStateWorkflowTests: XCTestCase {
    func testEditingRemainsAvailableWithoutInputPermissions() {
        let store = WorkflowStore()
        let state = AppState(store: store)
        state.hasPermission = false
        XCTAssertTrue(state.canEditScripts)
        XCTAssertTrue(state.createBlankScript())
        XCTAssertEqual(state.scripts.count, 1)
        XCTAssertEqual(state.selectedScriptID, state.scripts.first?.id)
    }

    func testUndoRedoParameterDeleteMoveAndDuplicatePersistExactSnapshots() {
        let first = ActionBlock.wait(WaitBlock(duration: 1))
        let second = ActionBlock.wait(WaitBlock(duration: 2)).withStartOffset(1)
        let original = Script(name: "edit", blocks: [first, second])
        let store = WorkflowStore(scripts: [original])
        let state = AppState(store: store)
        var changed = original
        changed.blocks = [second.withStartOffset(0), first.withStartOffset(2)]
        XCTAssertTrue(state.update(changed))
        let saved = state.scripts[0]
        state.undo()
        XCTAssertEqual(state.scripts, [original])
        XCTAssertEqual(store.scripts, [original])
        state.redo()
        XCTAssertEqual(state.scripts, [saved])
        XCTAssertEqual(store.scripts, [saved])
        changed = saved
        changed.blocks.removeFirst()
        XCTAssertTrue(state.update(changed))
        state.undo()
        XCTAssertEqual(state.scripts, [saved])
        state.duplicateScript(id: original.id)
        XCTAssertEqual(state.scripts.count, 2)
        state.undo()
        XCTAssertEqual(state.scripts, [saved])
        state.redo()
        XCTAssertEqual(state.scripts.count, 2)
    }

    func testFailedSaveAndUndoKeepHistoryAndCurrentDraftRecoverable() {
        let original = Script(name: "before")
        let store = WorkflowStore(scripts: [original])
        let state = AppState(store: store)
        var changed = original
        changed.name = "after"
        store.failsSave = true
        XCTAssertFalse(state.update(changed))
        XCTAssertFalse(state.canUndo)
        XCTAssertEqual(state.scripts, [original])
        store.failsSave = false
        XCTAssertTrue(state.update(changed))
        let saved = state.scripts[0]
        store.failsSave = true
        state.undo()
        XCTAssertTrue(state.canUndo)
        XCTAssertFalse(state.canRedo)
        XCTAssertEqual(state.scripts, [saved])
        store.failsSave = false
        state.undo()
        XCTAssertEqual(state.scripts, [original])
    }

    func testNewEditAfterUndoClearsRedo() {
        let original = Script(name: "before")
        let state = AppState(store: WorkflowStore(scripts: [original]))
        var changed = original
        changed.name = "first edit"
        XCTAssertTrue(state.update(changed))
        state.undo()
        XCTAssertTrue(state.canRedo)
        changed.name = "different edit"
        XCTAssertTrue(state.update(changed))
        XCTAssertFalse(state.canRedo)
    }

    func testCopyPasteAcrossScriptsUsesIndependentIDsAndSupportsUndo() {
        let source = Script(name: "source", blocks: [
            .wait(WaitBlock(duration: 1)),
            ActionBlock.wait(WaitBlock(duration: 2)).withStartOffset(3)
        ])
        let destination = Script(name: "destination")
        let state = AppState(store: WorkflowStore(scripts: [source, destination]))
        state.copyActions(scriptID: source.id, blockIDs: Set(source.blocks.map(\.id)))
        XCTAssertTrue(state.hasCopiedActions)
        XCTAssertFalse(state.canUndo)
        XCTAssertTrue(state.pasteActions(into: destination.id, at: 0))
        let result = state.scripts.first { $0.id == destination.id }!
        XCTAssertEqual(result.blocks.map(\.startOffset), [0, 3])
        XCTAssertTrue(Set(result.blocks.map(\.id)).isDisjoint(with: source.blocks.map(\.id)))
        state.undo()
        XCTAssertEqual(state.scripts.first { $0.id == destination.id }?.blocks, [])
    }

    func testImportConflictDefaultsToPreserveBothAndNeverEnablesShortcut() throws {
        var incoming = Script(name: "same", blocks: [.wait(WaitBlock(duration: 1))],
                              targetBundleIdentifier: "com.example.app",
                              playbackShortcut: ScriptShortcut(keyCode: 18, modifierFlags: KeyCodeMap.maskControl))
        incoming.startApplicationBeforePlayback = true
        let state = AppState(store: WorkflowStore(scripts: [incoming]))
        XCTAssertTrue(state.importScript(incoming))
        XCTAssertEqual(state.scripts.count, 2)
        let copy = state.scripts.last!
        XCTAssertNotEqual(copy.id, incoming.id)
        XCTAssertNotEqual(copy.blocks.first?.id, incoming.blocks.first?.id)
        XCTAssertNil(copy.playbackShortcut)
        XCTAssertFalse(copy.startApplicationBeforePlayback)
        XCTAssertEqual(state.scripts.first, incoming)
        XCTAssertNil(state.activePlaybackScript)
    }

    func testExplicitImportReplacementIsUndoableAndShortcutFree() {
        let original = Script(name: "original")
        var imported = original
        imported.name = "replacement"
        imported.playbackShortcut = ScriptShortcut(keyCode: 18, modifierFlags: KeyCodeMap.maskControl)
        let state = AppState(store: WorkflowStore(scripts: [original]))
        XCTAssertTrue(state.importScript(imported, replaceExisting: true))
        XCTAssertEqual(state.scripts.count, 1)
        XCTAssertEqual(state.scripts[0].id, original.id)
        XCTAssertNil(state.scripts[0].playbackShortcut)
        state.undo()
        XCTAssertEqual(state.scripts, [original])
    }

    func testDeletedScriptSurvivesRelaunchAndRestores() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScriptStore(directory: directory)
        let script = Script(name: "recover")
        try store.save(script)
        let state = AppState(store: store)
        state.deleteScript(id: script.id)
        XCTAssertTrue(state.scripts.isEmpty)
        let reopened = AppState(store: ScriptStore(directory: directory))
        XCTAssertEqual(reopened.recentlyDeletedScripts, [script])
        XCTAssertTrue(reopened.restoreDeletedScript(id: script.id))
        XCTAssertEqual(reopened.scripts, [script])
        XCTAssertTrue(reopened.recentlyDeletedScripts.isEmpty)
    }

    func testDeleteUndoRedoCanRepeatWithoutArchiveCollision() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ScriptStore(directory: directory)
        let script = Script(name: "recover")
        try store.save(script)
        let state = AppState(store: store)
        state.deleteScript(id: script.id)
        for _ in 0..<3 {
            state.undo()
            XCTAssertEqual(state.scripts, [script])
            XCTAssertTrue(state.recentlyDeletedScripts.isEmpty)
            state.redo()
            XCTAssertTrue(state.scripts.isEmpty)
            XCTAssertEqual(state.recentlyDeletedScripts, [script])
            XCTAssertNil(state.persistenceIssue)
        }
    }

    func testExportRoundTripCanReimportAsIndependentScript() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = Script(name: "export", blocks: [.wait(WaitBlock(duration: 2))])
        let state = AppState(store: WorkflowStore(scripts: [script]))
        let url = directory.appendingPathComponent("saved.json")
        XCTAssertTrue(state.exportScript(id: script.id, to: url))
        let preview = try ScriptTransfer.decode(data: Data(contentsOf: url))
        XCTAssertTrue(state.importScript(preview))
        XCTAssertEqual(state.scripts.count, 2)
        XCTAssertEqual(state.scripts.last?.blocks.first?.effectiveDuration, 2)
    }
}

private final class WorkflowStore: ScriptPersisting {
    var scripts: [Script]
    var failsSave = false
    init(scripts: [Script] = []) { self.scripts = scripts }
    func loadAll() -> ScriptStoreLoadResult { ScriptStoreLoadResult(scripts: scripts, issues: []) }
    func save(_ script: Script) throws {
        if failsSave { throw ScriptStoreIssue(operation: .replace, message: "injected failure") }
        if let index = scripts.firstIndex(where: { $0.id == script.id }) { scripts[index] = script }
        else { scripts.append(script) }
    }
    func delete(id: UUID) throws { scripts.removeAll { $0.id == id } }
}

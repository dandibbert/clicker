import XCTest
import ClickerCore
@testable import Clicker

@MainActor
final class AppStateHistoryRecoveryTests: XCTestCase {
    private func script(named name: String) -> Script {
        Script(name: name, createdAt: Date(timeIntervalSince1970: 100),
               modifiedAt: Date(timeIntervalSince1970: 100))
    }

    func testArchiveReadFailureDuringUndoDeletionPreservesLibraryAndHistory() {
        let script = self.script(named: "Keep recoverable")
        let store = HistoryRecoveryStore(scripts: [script])
        let state = AppState(store: store)
        state.deleteScript(id: script.id)
        let issue = ScriptStoreIssue(operation: .list, message: "Archive unavailable")
        store.recoveryIssue = issue

        state.undo()

        XCTAssertTrue(state.scripts.isEmpty)
        XCTAssertTrue(store.scripts.isEmpty)
        XCTAssertEqual(store.deleted, [script])
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertEqual(store.restoreCount, 0)
        XCTAssertEqual(state.undoEntries.count, 1)
        XCTAssertTrue(state.redoEntries.isEmpty)
        XCTAssertEqual(state.persistenceIssue, issue)

        store.recoveryIssue = nil
        state.undo()
        XCTAssertEqual(state.scripts, [script])
        XCTAssertEqual(store.scripts, [script])
        XCTAssertTrue(store.deleted.isEmpty)
        XCTAssertTrue(state.undoEntries.isEmpty)
        XCTAssertEqual(state.redoEntries.count, 1)
        XCTAssertNil(state.persistenceIssue)
        state.redo()
        XCTAssertTrue(state.scripts.isEmpty)
        XCTAssertEqual(store.deleted, [script])
    }

    func testArchiveDecodeFailureDuringRedoCreationDoesNotFallBackToSaving() {
        let script = self.script(named: "Created")
        let store = HistoryRecoveryStore()
        let state = AppState(store: store)
        XCTAssertTrue(state.create(script))
        state.undo()
        let issue = ScriptStoreIssue(operation: .decode, fileName: "damaged.json", message: "Damaged")
        store.recoveryIssue = issue

        state.redo()

        XCTAssertTrue(state.scripts.isEmpty)
        XCTAssertTrue(store.scripts.isEmpty)
        XCTAssertEqual(store.deleted, [script])
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.restoreCount, 0)
        XCTAssertTrue(state.undoEntries.isEmpty)
        XCTAssertEqual(state.redoEntries.count, 1)
        XCTAssertEqual(state.persistenceIssue, issue)
    }

    func testRecoveryRefreshSurfacesIssueWithoutReplacingPrimaryPersistenceFailure() {
        let store = HistoryRecoveryStore()
        let state = AppState(store: store)
        let archiveIssue = ScriptStoreIssue(operation: .read, fileName: "archive.json", message: "Unreadable")
        let primaryIssue = ScriptStoreIssue(operation: .temporaryWrite, message: "Cannot save current edit")
        store.recoveryIssue = archiveIssue
        state.persistenceIssue = primaryIssue

        state.refreshRecentlyDeleted()
        XCTAssertEqual(state.persistenceIssue, primaryIssue)

        state.persistenceIssue = nil
        state.refreshRecentlyDeleted()
        XCTAssertEqual(state.persistenceIssue, archiveIssue)
    }

    func testSuccessfulRestoreDoesNotDiscardSubsequentRecoveryRefreshIssue() {
        let script = self.script(named: "Archived")
        let store = HistoryRecoveryStore(deleted: [script])
        let state = AppState(store: store)
        let issue = ScriptStoreIssue(operation: .list, message: "Refresh unavailable")
        store.issueAfterRestore = issue

        XCTAssertTrue(state.restoreDeletedScript(id: script.id))

        XCTAssertEqual(state.scripts, [script])
        XCTAssertEqual(store.scripts, [script])
        XCTAssertEqual(state.undoEntries.count, 1)
        XCTAssertEqual(state.persistenceIssue, issue)
    }

    func testChangedArchivedSnapshotRejectsHistoryWithoutMovingOrSavingEitherVersion() {
        let script = self.script(named: "Original")
        let store = HistoryRecoveryStore(scripts: [script])
        let state = AppState(store: store)
        state.deleteScript(id: script.id)
        store.deleted[0].name = "Changed outside this undo history"

        state.undo()

        XCTAssertTrue(state.scripts.isEmpty)
        XCTAssertTrue(store.scripts.isEmpty)
        XCTAssertEqual(store.deleted.map(\.name), ["Changed outside this undo history"])
        XCTAssertEqual(store.restoreCount, 0)
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertEqual(state.undoEntries.count, 1)
        XCTAssertTrue(state.redoEntries.isEmpty)
        XCTAssertEqual(state.persistenceIssue?.operation, .replace)

        store.deleted = [script]
        state.undo()
        XCTAssertEqual(state.scripts, [script])
        XCTAssertTrue(state.undoEntries.isEmpty)
        XCTAssertEqual(state.redoEntries.count, 1)
    }

    func testUndoDeletionNormalizesExpectedDatesAndUsesActualRestoredSnapshot() throws {
        let script = Script(name: "Fractional date", createdAt: Date(timeIntervalSince1970: 1234.1234567),
                            modifiedAt: Date(timeIntervalSince1970: 2345.2345678))
        let persisted = try ScriptJSONCodec.decode(ScriptJSONCodec.encode(script))
        let store = HistoryRecoveryStore(scripts: [script])
        let state = AppState(store: store)
        state.deleteScript(id: script.id)
        store.deleted = [persisted]

        state.undo()

        XCTAssertEqual(state.scripts, [persisted])
        XCTAssertEqual(store.scripts, [persisted])
        XCTAssertEqual(store.restoreCount, 1)
        XCTAssertTrue(state.undoEntries.isEmpty)
        XCTAssertEqual(state.redoEntries.count, 1)
        XCTAssertNil(state.persistenceIssue)
    }
}

private final class HistoryRecoveryStore: ScriptPersisting, ScriptRecovering {
    var scripts: [Script]
    var deleted: [Script]
    var recoveryIssue: ScriptStoreIssue?
    var issueAfterRestore: ScriptStoreIssue?
    private(set) var saveCount = 0
    private(set) var restoreCount = 0

    init(scripts: [Script] = [], deleted: [Script] = []) {
        self.scripts = scripts
        self.deleted = deleted
    }

    func loadAll() -> ScriptStoreLoadResult { .init(scripts: scripts, issues: []) }

    func save(_ script: Script) throws {
        saveCount += 1
        scripts.removeAll { $0.id == script.id }
        scripts.append(script)
    }

    func delete(id: UUID) throws {
        guard !deleted.contains(where: { $0.id == id }) else {
            throw ScriptStoreIssue(operation: .delete, message: "Archive collision")
        }
        if let index = scripts.firstIndex(where: { $0.id == id }) {
            deleted.append(scripts.remove(at: index))
        }
    }

    func loadRecentlyDeleted() -> ScriptStoreLoadResult {
        if let recoveryIssue { return .init(scripts: [], issues: [recoveryIssue]) }
        return .init(scripts: deleted, issues: [])
    }

    func restoreRecentlyDeleted(id: UUID) throws -> Script {
        guard !scripts.contains(where: { $0.id == id }),
              let index = deleted.firstIndex(where: { $0.id == id }) else {
            throw ScriptStoreIssue(operation: .replace, message: "Cannot restore")
        }
        restoreCount += 1
        let script = deleted.remove(at: index)
        scripts.append(script)
        recoveryIssue = issueAfterRestore
        return script
    }
}

import CoreGraphics
import XCTest
@testable import Clicker
import ClickerCore

@MainActor
final class AppStatePersistenceTests: XCTestCase {
    func testFailedCreateDoesNotMutateLibraryOrSelection() {
        let store = StubScriptStore()
        store.saveError = ScriptStoreIssue(operation: .replace, message: "replace failed")
        let state = makeState(store: store)
        let script = Script(name: "new")

        state.create(script)

        XCTAssertTrue(state.scripts.isEmpty)
        XCTAssertNil(state.selectedScriptID)
        XCTAssertEqual(state.persistenceIssue?.operation, .replace)
    }

    func testFailedUpdatePreservesPriorInMemoryScript() {
        let original = Script(name: "original")
        let store = StubScriptStore(scripts: [original])
        let state = makeState(store: store)
        store.saveError = ScriptStoreIssue(operation: .temporaryWrite, message: "write failed")
        var updated = original
        updated.name = "updated"

        state.update(updated)

        XCTAssertEqual(state.scripts.map(\.name), ["original"])
        XCTAssertEqual(state.persistenceIssue?.operation, .temporaryWrite)
    }

    func testLateUpdateAfterSuccessfulDeleteCannotSaveOrResurrectScript() {
        let script = Script(name: "delete me")
        let store = StubScriptStore(scripts: [script])
        let state = makeState(store: store)

        state.deleteScript(id: script.id)
        state.update(script)

        XCTAssertTrue(state.scripts.isEmpty)
        XCTAssertTrue(store.savedScripts.isEmpty)
        XCTAssertEqual(store.deletedIDs, [script.id])
    }

    func testFailedDeletePreservesScriptAndSelectionAndPublishesIssue() {
        let script = Script(name: "keep me")
        let store = StubScriptStore(scripts: [script])
        store.deleteError = ScriptStoreIssue(operation: .delete, message: "delete failed")
        let state = makeState(store: store)

        state.deleteScript(id: script.id)

        XCTAssertEqual(state.scripts, [script])
        XCTAssertEqual(state.selectedScriptID, script.id)
        XCTAssertEqual(state.persistenceIssue?.operation, .delete)
    }

    func testReloadKeepsGoodScriptsAndPublishesStructuredLoadIssue() {
        let script = Script(name: "good")
        let issue = ScriptStoreIssue(
            operation: .decode,
            fileName: "bad.json",
            message: "invalid JSON"
        )
        let store = StubScriptStore(scripts: [script], issues: [issue])

        let state = makeState(store: store)

        XCTAssertEqual(state.scripts, [script])
        XCTAssertEqual(state.persistenceIssue, issue)
        XCTAssertEqual(state.corruptFileNames, ["bad.json"])
    }

    private func makeState(store: StubScriptStore) -> AppState {
        let state = AppState(
            store: store,
            recorder: PersistenceNoopRecorder(),
            countdown: PersistenceNoopCountdown(),
            application: PersistenceNoopApplication()
        )
        state.hasPermission = true
        return state
    }
}

private final class StubScriptStore: ScriptPersisting {
    private let loadResult: ScriptStoreLoadResult
    var saveError: Error?
    var deleteError: Error?
    private(set) var savedScripts: [Script] = []
    private(set) var deletedIDs: [UUID] = []

    init(scripts: [Script] = [], issues: [ScriptStoreIssue] = []) {
        loadResult = ScriptStoreLoadResult(scripts: scripts, issues: issues)
    }

    func loadAll() -> ScriptStoreLoadResult { loadResult }

    func save(_ script: Script) throws {
        if let saveError { throw saveError }
        savedScripts.append(script)
    }

    func delete(id: UUID) throws {
        if let deleteError { throw deleteError }
        deletedIDs.append(id)
    }
}

private final class PersistenceNoopRecorder: EventRecording {
    var onTapFailure: (() -> Void)?
    var onStopRequest: (() -> Void)?
    func start(stopShortcut _: RecordingStopShortcut) -> Bool { true }
    func stop() -> RecordingCapture { RecordingCapture(events: [], duration: 0) }
    func cutoff(at _: CGEventTimestamp) -> RecordingCutoff {
        RecordingCutoff(eventCount: 0, duration: 0)
    }
}

private final class PersistenceNoopCountdown: CountdownPresenting {
    func show(
        seconds _: Int,
        onTick _: @escaping (Int) -> Void,
        onFinish _: @escaping () -> Void
    ) {}
    func close() {}
}

@MainActor
private final class PersistenceNoopApplication: ApplicationControlling {
    var activationResult = false
    private(set) var activatedBundleIdentifiers: [String] = []

    func activateExternalApplication(bundleIdentifier: String) -> Bool {
        activatedBundleIdentifiers.append(bundleIdentifier)
        return activationResult
    }
    func hideClicker() {}
    func restoreClicker() {}
}

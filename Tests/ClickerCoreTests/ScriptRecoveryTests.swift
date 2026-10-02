import Foundation
import XCTest
@testable import ClickerCore

final class ScriptRecoveryTests: XCTestCase {
    private var directory: URL!
    private var store: ScriptStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClickerRecovery-\(UUID().uuidString)")
        store = ScriptStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDeleteIsRecoverableAndDoesNotShowInActiveLibrary() throws {
        let script = Script(name: "Recoverable", createdAt: Date(timeIntervalSince1970: 100),
                            modifiedAt: Date(timeIntervalSince1970: 100),
                            blocks: [.wait(WaitBlock(duration: 1))])
        try store.save(script)
        let originalURL = directory.appendingPathComponent("\(script.id.uuidString).json")
        let originalBytes = try Data(contentsOf: originalURL)

        try store.delete(id: script.id)

        XCTAssertTrue(store.loadAll().scripts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        let recovery: ScriptRecovering = store
        XCTAssertEqual(recovery.loadRecentlyDeleted().scripts, [script])
        XCTAssertTrue(recovery.loadRecentlyDeleted().issues.isEmpty)
        let restored = try recovery.restoreRecentlyDeleted(id: script.id)
        XCTAssertEqual(restored, script)
        XCTAssertEqual(store.loadAll().scripts, [script])
        XCTAssertTrue(recovery.loadRecentlyDeleted().scripts.isEmpty)
        XCTAssertEqual(try Data(contentsOf: originalURL), originalBytes)
    }

    func testRestoreNeverOverwritesAnActiveScript() throws {
        var script = Script(name: "Archived")
        try store.save(script)
        try store.delete(id: script.id)
        script.name = "Active edit"
        try store.save(script)

        XCTAssertThrowsError(try store.restoreRecentlyDeleted(id: script.id)) { error in
            XCTAssertEqual((error as? ScriptStoreIssue)?.operation, .replace)
        }

        XCTAssertEqual(store.loadAll().scripts.map(\.name), ["Active edit"])
        XCTAssertEqual(store.loadRecentlyDeleted().scripts.map(\.name), ["Archived"])
    }

    func testDeleteNeverOverwritesAnEarlierRecoverableCopy() throws {
        var script = Script(name: "Earlier archive")
        try store.save(script)
        try store.delete(id: script.id)
        script.name = "Active copy"
        try store.save(script)

        XCTAssertThrowsError(try store.delete(id: script.id)) { error in
            XCTAssertEqual((error as? ScriptStoreIssue)?.operation, .delete)
        }

        XCTAssertEqual(store.loadAll().scripts.map(\.name), ["Active copy"])
        XCTAssertEqual(store.loadRecentlyDeleted().scripts.map(\.name), ["Earlier archive"])
    }

    func testDeleteMoveFailureLeavesActiveBytesUntouched() throws {
        let fs = RecoveryFileSystem()
        let store = ScriptStore(directory: directory, fileSystem: fs)
        let script = Script(name: "Original")
        try store.save(script)
        let active = directory.appendingPathComponent("\(script.id.uuidString).json")
        let bytes = try XCTUnwrap(fs.files[active])
        fs.failMoves = true

        XCTAssertThrowsError(try store.delete(id: script.id)) { error in
            XCTAssertEqual((error as? ScriptStoreIssue)?.operation, .delete)
        }
        XCTAssertEqual(fs.files[active], bytes)
        XCTAssertEqual(store.loadAll().scripts.map(\.id), [script.id])
        XCTAssertTrue(store.loadRecentlyDeleted().scripts.isEmpty)
    }

    func testRestoreMoveFailureLeavesArchiveBytesUntouched() throws {
        let fs = RecoveryFileSystem()
        let store = ScriptStore(directory: directory, fileSystem: fs)
        let script = Script(name: "Archived")
        try store.save(script)
        let archived = try store.moveToRecentlyDeleted(id: script.id)
        let bytes = try XCTUnwrap(fs.files[archived])
        fs.failMoves = true

        XCTAssertThrowsError(try store.restoreRecentlyDeleted(id: script.id)) { error in
            XCTAssertEqual((error as? ScriptStoreIssue)?.operation, .replace)
        }
        XCTAssertEqual(fs.files[archived], bytes)
        XCTAssertTrue(store.loadAll().scripts.isEmpty)
        XCTAssertEqual(store.loadRecentlyDeleted().scripts.map(\.id), [script.id])
    }

    func testCorruptArchiveCannotBeRestoredOrDisappear() throws {
        let id = UUID()
        try FileManager.default.createDirectory(at: store.recentlyDeletedDirectory,
                                                 withIntermediateDirectories: true)
        let archived = store.recentlyDeletedDirectory.appendingPathComponent("\(id.uuidString).json")
        let bytes = Data("broken JSON".utf8)
        try bytes.write(to: archived)

        XCTAssertThrowsError(try store.restoreRecentlyDeleted(id: id)) { error in
            XCTAssertEqual((error as? ScriptStoreIssue)?.operation, .decode)
        }
        XCTAssertEqual(try Data(contentsOf: archived), bytes)
        XCTAssertEqual(store.loadRecentlyDeleted().issues.first?.operation, .decode)
        XCTAssertTrue(store.loadAll().scripts.isEmpty)
    }

    func testArchiveWithDifferentIdentityIsRejected() throws {
        let requestedID = UUID()
        let script = Script(name: "Different ID")
        try FileManager.default.createDirectory(at: store.recentlyDeletedDirectory,
                                                 withIntermediateDirectories: true)
        let archived = store.recentlyDeletedDirectory
            .appendingPathComponent("\(requestedID.uuidString).json")
        try ScriptTransfer.encode(script).write(to: archived)
        XCTAssertThrowsError(try store.restoreRecentlyDeleted(id: requestedID)) { error in
            XCTAssertEqual((error as? ScriptStoreIssue)?.operation, .decode)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: archived.path))
    }

    func testMissingArchiveReportsReadFailureWithoutCreatingScript() {
        XCTAssertThrowsError(try store.restoreRecentlyDeleted(id: UUID())) { error in
            XCTAssertEqual((error as? ScriptStoreIssue)?.operation, .read)
        }
        XCTAssertTrue(store.loadAll().scripts.isEmpty)
    }
}

private final class RecoveryFileSystem: ScriptStoreFileSystem {
    enum Failure: Error { case requested }
    var files: [URL: Data] = [:]
    var directories: Set<URL> = []
    var failMoves = false

    func createDirectory(at url: URL) throws { _ = directories.insert(url) }
    func fileExists(at url: URL) -> Bool { files[url] != nil || directories.contains(url) }
    func contentsOfDirectory(at url: URL) throws -> [URL] {
        files.keys.filter { $0.deletingLastPathComponent().path == url.path }
    }
    func read(at url: URL) throws -> Data { try XCTUnwrap(files[url]) }
    func write(_ data: Data, to url: URL) throws { files[url] = data }
    func replaceItem(at destination: URL, with temporary: URL) throws {
        files[destination] = try XCTUnwrap(files.removeValue(forKey: temporary))
    }
    func moveItem(at source: URL, to destination: URL) throws {
        if failMoves { throw Failure.requested }
        files[destination] = try XCTUnwrap(files.removeValue(forKey: source))
    }
    func removeItem(at url: URL) throws { _ = files.removeValue(forKey: url) }
}

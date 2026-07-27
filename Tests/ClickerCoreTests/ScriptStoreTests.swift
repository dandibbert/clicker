import XCTest
@testable import ClickerCore

final class ScriptStoreTests: XCTestCase {
    var tmpDir: URL!
    var store: ScriptStore!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClickerTests-\(UUID().uuidString)")
        store = ScriptStore(directory: tmpDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testSaveAndLoad() throws {
        // 使用整秒时间戳：JSON 的 millisecondsSince1970 日期策略会舍入
        // Date 的亚毫秒精度，导致完整结构体相等断言失败。
        var s = Script(name: "测试脚本", createdAt: Date(timeIntervalSince1970: 1000),
                       modifiedAt: Date(timeIntervalSince1970: 1000))
        s.blocks = [.wait(WaitBlock(duration: 1.5))]
        try store.save(s)
        let loaded = store.loadAll().scripts
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first, s)
    }

    func testSaveOverwrites() throws {
        var s = Script(name: "v1")
        try store.save(s)
        s.name = "v2"
        try store.save(s)
        let loaded = store.loadAll().scripts
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "v2")
    }

    func testDelete() throws {
        let s = Script(name: "待删除")
        try store.save(s)
        try store.delete(id: s.id)
        XCTAssertTrue(store.loadAll().scripts.isEmpty)
    }

    func testCorruptFileReturnsGoodScriptsAndStructuredDecodeIssue() throws {
        let good = Script(name: "正常")
        try store.save(good)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: tmpDir.appendingPathComponent("bad.json"))
        let result = store.loadAll()

        XCTAssertEqual(result.scripts, [good])
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues.first?.operation, .decode)
        XCTAssertEqual(result.issues.first?.fileName, "bad.json")
    }

    func testUnlistableDirectoryReturnsStructuredListIssue() throws {
        try Data("not a directory".utf8).write(to: tmpDir)

        let result = store.loadAll()

        XCTAssertTrue(result.scripts.isEmpty)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues.first?.operation, .list)
        XCTAssertNil(result.issues.first?.fileName)
    }

    func testLoadAllSortedByCreation() throws {
        let a = Script(name: "A", createdAt: Date(timeIntervalSince1970: 100))
        let b = Script(name: "B", createdAt: Date(timeIntervalSince1970: 200))
        try store.save(b)
        try store.save(a)
        XCTAssertEqual(store.loadAll().scripts.map(\.name), ["A", "B"])
    }

    func testV1FixtureLoadsAndNextSaveWritesSchemaVersion4() throws {
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try legacyV1ScriptData.write(to: tmpDir.appendingPathComponent("legacy.json"))

        let result = store.loadAll()
        let loaded = result.scripts

        XCTAssertEqual(loaded.count, 1)
        XCTAssertTrue(result.issues.isEmpty)
        let script = try XCTUnwrap(loaded.first)
        XCTAssertEqual(script.schemaVersion, 4)
        XCTAssertEqual(script.trailingDelay, 0)
        XCTAssertNil(script.targetBundleIdentifier)

        try store.save(script)
        let savedURL = tmpDir.appendingPathComponent("\(script.id.uuidString).json")
        let savedData = try Data(contentsOf: savedURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: savedData) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 4)
    }
}

import AppKit
import ClickerCore
import SwiftUI
import XCTest
@testable import Clicker

/// Keep one real MainView mounted across the empty/populated boundary. No global
/// recorder, playback service, file panel, or synthetic application is started.
final class LibraryLayoutTransitionTests: XCTestCase {
    @MainActor
    func testFirstBlankLastDeletionAndFirstRestoreSwitchTheMountedLayout() throws {
        for dark in [false, true] {
            let fixture = try HostedLibraryHierarchyFixture(dark: dark, hasPermission: false)
            defer { fixture.tearDown() }
            let blank = try fixture.action(named: "新建空白脚本")
            XCTAssertTrue(blank.isAccessibilityEnabled())
            XCTAssertTrue(blank.accessibilityPerformPress(), "Activate the actual welcome Button")
            fixture.settle(until: { fixture.state.scripts.count == 1 })
            let script = try XCTUnwrap(fixture.state.selectedScript)
            XCTAssertTrue(script.blocks.isEmpty)
            XCTAssertEqual(fixture.state.phase, .idle)
            XCTAssertNil(fixture.state.activePlaybackScript)
            try fixture.assertPopulatedLibrary(expectedRows: 1)
            let blankBitmap = try fixture.snapshot(named: "first-blank-no-permission")
            let blankText = try fixture.recognizedText(in: blankBitmap)
            XCTAssertFalse(blankText.contains { $0.text.contains("创建第一个脚本") })
            XCTAssertTrue(blankText.contains { $0.text.contains("这个脚本还没有动作") },
                          "An empty script is still a selected native library row")

            fixture.state.deleteScript(id: script.id)
            fixture.settle(until: { !fixture.descendants(of: fixture.host).contains { $0 is NSSplitView } })
            XCTAssertNil(fixture.state.selectedScriptID)
            XCTAssertEqual(fixture.state.recentlyDeletedScripts.map(\.id), [script.id])
            let deletedBitmap = try fixture.snapshot(named: "last-deleted")
            try fixture.assertEmptyWelcome(text: fixture.recognizedText(in: deletedBitmap), canRecord: false)
            let restoreMenu = try fixture.action(named: "最近删除")
            XCTAssertTrue(restoreMenu.isAccessibilityEnabled())
            XCTAssertTrue(fixture.host.bounds.contains(fixture.frame(of: restoreMenu)),
                          "Restore must remain discoverable after deleting the last row")

            // The production recovery command reloads from the real temporary
            // archive. Its only available destination is now the empty welcome.
            XCTAssertTrue(fixture.state.restoreDeletedScript(id: script.id))
            fixture.settle(until: { fixture.state.selectedScriptID == script.id })
            XCTAssertTrue(fixture.state.recentlyDeletedScripts.isEmpty)
            XCTAssertEqual(fixture.state.scripts.map(\.id), [script.id])
            XCTAssertEqual(fixture.state.store.loadAll().scripts.map(\.id), [script.id])
            try fixture.assertPopulatedLibrary(expectedRows: 1)
            let restored = try fixture.snapshot(named: "first-restored")
            XCTAssertFalse(try fixture.recognizedText(in: restored).contains { $0.text.contains("创建第一个脚本") })
            XCTAssertEqual(fixture.state.phase, .idle)
            XCTAssertNil(fixture.state.activePlaybackScript)
        }
    }

    @MainActor
    func testImportPreviewCancelThenApplySurvivesFirstScriptTransition() throws {
        for dark in [false, true] {
            var pickerCalls = 0
            var incoming = Script(name: "导入验证", blocks: [.wait(WaitBlock(duration: 1))],
                                  targetBundleIdentifier: "com.example.imported",
                                  playbackShortcut: ScriptShortcut(keyCode: 18, modifierFlags: KeyCodeMap.maskControl))
            incoming.startApplicationBeforePlayback = true
            let fixture = try HostedLibraryHierarchyFixture(dark: dark, hasPermission: false, importPicker: {
                pickerCalls += 1
                return ScriptImportCandidate(script: incoming, sourceName: "first-script.json")
            })
            defer { fixture.tearDown() }

            try presentImportPreview(in: fixture)
            XCTAssertEqual(pickerCalls, 1)
            XCTAssertTrue(fixture.state.scripts.isEmpty, "Previewing an import must not mutate the library")
            try fixture.snapshotSheet(named: "first-import-preview")
            let firstSheet = try XCTUnwrap(fixture.window.attachedSheet)
            let cancel = try fixture.action(named: "取消", in: XCTUnwrap(firstSheet.contentView))
            XCTAssertTrue(cancel.accessibilityPerformPress())
            fixture.settle(until: { fixture.window.attachedSheet == nil })
            XCTAssertNil(fixture.window.attachedSheet)
            XCTAssertTrue(fixture.state.store.loadAll().scripts.isEmpty)
            let cancelled = try fixture.snapshot(named: "import-cancelled")
            try fixture.assertEmptyWelcome(text: fixture.recognizedText(in: cancelled), canRecord: false)

            try presentImportPreview(in: fixture)
            XCTAssertEqual(pickerCalls, 2, "The import action must remain usable after cancellation")
            let secondSheet = try XCTUnwrap(fixture.window.attachedSheet)
            let apply = try fixture.action(named: "导入", in: XCTUnwrap(secondSheet.contentView))
            XCTAssertTrue(apply.isAccessibilityEnabled())
            XCTAssertTrue(apply.accessibilityPerformPress())
            fixture.settle(until: { fixture.state.scripts.count == 1 && fixture.window.attachedSheet == nil })
            XCTAssertNil(fixture.window.attachedSheet,
                         "Import sheet ownership must survive the welcome-to-split transition and dismiss")
            let imported = try XCTUnwrap(fixture.state.selectedScript)
            XCTAssertEqual(fixture.state.scripts.count, 1)
            XCTAssertNotEqual(imported.id, incoming.id)
            XCTAssertEqual(imported.name, incoming.name)
            XCTAssertEqual(imported.blocks.map(\.effectiveDuration), incoming.blocks.map(\.effectiveDuration))
            XCTAssertNil(imported.playbackShortcut)
            XCTAssertFalse(imported.startApplicationBeforePlayback)
            XCTAssertEqual(fixture.state.store.loadAll().scripts.map(\.id), [imported.id])
            XCTAssertEqual(fixture.state.phase, .idle)
            XCTAssertNil(fixture.state.activePlaybackScript)
            XCTAssertNil(fixture.state.pendingPlaybackStart)
            try fixture.assertPopulatedLibrary(expectedRows: 1)
            try fixture.snapshot(named: "first-imported")
        }
    }

    @MainActor
    func testCancellingImportPickerLeavesTheSingleWelcomeMounted() throws {
        var pickerCalls = 0
        let fixture = try HostedLibraryHierarchyFixture(importPicker: {
            pickerCalls += 1
            return nil
        })
        defer { fixture.tearDown() }
        XCTAssertTrue(try fixture.action(named: "导入脚本").accessibilityPerformPress())
        fixture.settle()
        XCTAssertEqual(pickerCalls, 1)
        XCTAssertNil(fixture.window.attachedSheet)
        XCTAssertTrue(fixture.state.scripts.isEmpty)
        XCTAssertTrue(fixture.state.store.loadAll().scripts.isEmpty)
        let bitmap = try fixture.snapshot(named: "import-picker-cancelled")
        try fixture.assertEmptyWelcome(text: fixture.recognizedText(in: bitmap))
    }

    @MainActor
    func testSearchNoResultsRetainsSplitAndClearingSearchRestoresNativeRows() throws {
        for dark in [false, true] {
            let script = Script(name: "网页整理", blocks: [.wait(WaitBlock(duration: 1))])
            let fixture = try HostedLibraryHierarchyFixture(scripts: [script, Script(name: "文件归档")], dark: dark)
            defer { fixture.tearDown() }
            let originalIDs = fixture.state.scripts.map(\.id)
            let outline = try fixture.sidebarOutline()
            try editSearch("no-matching-script-12345", in: fixture)
            fixture.settle(until: { outline.numberOfRows == 0 })
            try fixture.assertPopulatedLibrary(expectedRows: 0)
            XCTAssertEqual(fixture.state.scripts.map(\.id), originalIDs)
            XCTAssertEqual(fixture.state.selectedScriptID, script.id)
            let bitmap = try fixture.snapshot(named: "search-no-results")
            let text = try fixture.recognizedText(in: bitmap)
            XCTAssertTrue(text.contains { $0.text.contains("没有匹配的脚本") })
            XCTAssertFalse(text.contains { $0.text.contains("创建第一个脚本") },
                           "Zero search matches is not an empty library")
            let noResults = try XCTUnwrap(text.first { $0.text.contains("没有匹配的脚本") })
            XCTAssertTrue(fixture.frame(of: try fixture.sidebar()).contains(noResults.frame))
            try editSearch("", in: fixture)
            fixture.settle(until: { outline.numberOfRows == originalIDs.count })
            try fixture.assertPopulatedLibrary(expectedRows: 2)
            XCTAssertEqual(fixture.state.scripts.map(\.id), originalIDs)
            XCTAssertEqual(fixture.state.selectedScriptID, script.id)
            try fixture.snapshot(named: "search-cleared")
        }
    }

    @MainActor
    private func presentImportPreview(in fixture: HostedLibraryHierarchyFixture) throws {
        let importAction = try fixture.action(named: "导入脚本")
        XCTAssertTrue(importAction.isAccessibilityEnabled())
        XCTAssertTrue(importAction.accessibilityPerformPress())
        fixture.settle(until: { fixture.window.attachedSheet != nil })
        XCTAssertNotNil(fixture.window.attachedSheet, "The actual MainView import flow must present its preview")
    }

    @MainActor
    private func editSearch(_ query: String, in fixture: HostedLibraryHierarchyFixture) throws {
        let field = try fixture.searchField()
        XCTAssertTrue(fixture.window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.insertText(query, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        fixture.settle(until: { field.stringValue == query })
        XCTAssertEqual(field.stringValue, query)
    }
}

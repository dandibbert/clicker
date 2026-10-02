import AppKit
import ClickerCore
import CoreGraphics
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

            fixture.state.undo()
            fixture.settle(until: { fixture.state.scripts.isEmpty })
            XCTAssertTrue(fixture.state.canRedo)
            let undone = try fixture.snapshot(named: "first-blank-undone")
            try fixture.assertEmptyWelcome(text: fixture.recognizedText(in: undone), canRecord: false)
            fixture.state.redo()
            fixture.settle(until: { fixture.state.selectedScriptID == script.id })
            XCTAssertEqual(fixture.state.scripts.map(\.id), [script.id])
            try fixture.assertPopulatedLibrary(expectedRows: 1)
            try fixture.snapshot(named: "first-blank-redone")

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
    func testFirstRecordingCanCancelCountdownThenStopAndSaveFromWelcome() async throws {
        for dark in [false, true] {
            let services = LibraryRecordingServices()
            let fixture = try HostedLibraryHierarchyFixture(dark: dark, makeState: services.makeState)
            defer { fixture.tearDown() }
            XCTAssertTrue(try fixture.action(named: "开始录制").accessibilityPerformPress())
            fixture.settle()
            XCTAssertEqual(fixture.state.phase, .countdown(3))
            XCTAssertEqual(services.recorder.starts, 0)
            try assertWelcomeCanStopRecording(in: fixture)
            try fixture.snapshot(named: "first-recording-countdown")
            XCTAssertTrue(try fixture.action(named: "停止录制").accessibilityPerformPress())
            fixture.settle()
            XCTAssertEqual(fixture.state.phase, .idle)
            XCTAssertEqual(services.countdown.closes, 1)
            XCTAssertEqual(services.recorder.starts, 0)
            XCTAssertTrue(fixture.state.scripts.isEmpty)
            services.countdown.finish(at: 0)
            await Task.yield()
            XCTAssertEqual(fixture.state.phase, .idle, "A cancelled countdown cannot start capture later")
            XCTAssertEqual(services.recorder.starts, 0)

            XCTAssertTrue(try fixture.action(named: "开始录制").accessibilityPerformPress())
            services.countdown.finish(at: 1)
            await Task.yield()
            fixture.settle()
            XCTAssertEqual(fixture.state.phase, .recording)
            XCTAssertEqual(services.recorder.starts, 1)
            XCTAssertEqual(services.indicator.shows, 1)
            fixture.state.hasPermission = false
            fixture.settle()
            try assertWelcomeCanStopRecording(in: fixture)
            try fixture.snapshot(named: "first-recording-active-no-permission")
            XCTAssertTrue(try fixture.action(named: "停止录制").accessibilityPerformPress())
            fixture.settle(until: { fixture.state.scripts.count == 1 })
            XCTAssertEqual(fixture.state.phase, .idle)
            XCTAssertEqual(services.recorder.stops, 1)
            XCTAssertEqual(services.indicator.closes, 2)
            XCTAssertEqual(services.application.restores, 2)
            XCTAssertEqual(services.playback.starts, 0)
            XCTAssertNil(fixture.state.unsavedRecording)
            let saved = try XCTUnwrap(fixture.state.selectedScript)
            XCTAssertFalse(saved.blocks.isEmpty)
            let persisted = fixture.state.store.loadAll().scripts
            XCTAssertEqual(persisted.count, 1)
            XCTAssertEqual(persisted.first?.id, saved.id)
            XCTAssertEqual(persisted.first?.name, saved.name)
            XCTAssertEqual(persisted.first?.blocks, saved.blocks)
            XCTAssertEqual(persisted.first?.trailingDelay, saved.trailingDelay)
            try fixture.assertPopulatedLibrary(expectedRows: 1)
            try fixture.snapshot(named: "first-recording-saved")
        }
    }

    @MainActor
    func testMinimumWelcomeScrollsBelowRecoveryNoticesAndRetrySavesFirstScript() async throws {
        let services = LibraryRecordingServices()
        let fixture = try HostedLibraryHierarchyFixture(makeState: services.makeState)
        defer { fixture.tearDown() }
        XCTAssertTrue(try fixture.action(named: "开始录制").accessibilityPerformPress())
        services.countdown.finish(at: 0)
        await Task.yield()
        XCTAssertEqual(fixture.state.phase, .recording)
        fixture.state.stageRecordingForTermination()
        fixture.state.hasPermission = false
        fixture.state.recordingNotice = RecordingNotice(
            title: "有尚未保存的录制",
            message: "请先重试保存、另存或明确丢弃当前录制，再开始新的录制。"
        )
        fixture.settle()
        XCTAssertNotNil(fixture.state.unsavedRecording)
        XCTAssertTrue(fixture.state.scripts.isEmpty)
        XCTAssertFalse(fixture.descendants(of: fixture.host).contains { $0 is NSSplitView })
        XCTAssertFalse(try fixture.action(named: "开始录制").isAccessibilityEnabled())
        var recoveryBottom: CGFloat = 0
        for title in ["重试保存", "另存为", "丢弃"] {
            let action = try fixture.action(named: title)
            let frame = fixture.frame(of: action)
            XCTAssertTrue(action.isAccessibilityEnabled())
            XCTAssertTrue(fixture.host.bounds.contains(frame), "Recovery controls must stay above the welcome: \(frame)")
            recoveryBottom = max(recoveryBottom, frame.maxY)
        }
        try fixture.snapshot(named: "empty-recovery-notices")
        let scroll = try XCTUnwrap(fixture.descendants(of: fixture.host).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(document.bounds.height, scroll.contentView.bounds.height,
                             "The welcome must scroll when status notices consume the minimum-height window")
        let importAction = try fixture.action(named: "导入脚本")
        let target = document.convert(fixture.window.convertFromScreen(importAction.accessibilityFrame()), from: nil)
        document.scrollToVisible(target.insetBy(dx: 0, dy: -4))
        fixture.settle()
        let importFrame = fixture.frame(of: try fixture.action(named: "导入脚本"))
        XCTAssertTrue(fixture.host.bounds.contains(importFrame), "The final welcome action must be reachable by scrolling")
        XCTAssertGreaterThanOrEqual(importFrame.minY, recoveryBottom,
                                    "Scrolled welcome controls must never cover the recovery actions")
        try fixture.snapshot(named: "empty-recovery-scrolled")
        XCTAssertTrue(try fixture.action(named: "重试保存").accessibilityPerformPress())
        fixture.settle(until: { fixture.state.scripts.count == 1 })
        XCTAssertNil(fixture.state.unsavedRecording)
        XCTAssertEqual(services.recorder.stops, 1)
        XCTAssertEqual(services.playback.starts, 0)
        try fixture.assertPopulatedLibrary(expectedRows: 1)
        try fixture.snapshot(named: "first-recovery-saved")
    }

    @MainActor
    private func assertWelcomeCanStopRecording(in fixture: HostedLibraryHierarchyFixture) throws {
        XCTAssertTrue(fixture.state.scripts.isEmpty)
        XCTAssertFalse(fixture.descendants(of: fixture.host).contains { $0 is NSSplitView })
        let stop = try fixture.action(named: "停止录制")
        XCTAssertTrue(stop.isAccessibilityEnabled(), "Stopping must remain enabled even after permissions disappear")
        XCTAssertTrue(fixture.host.bounds.contains(fixture.frame(of: stop)))
        XCTAssertFalse(try fixture.action(named: "新建空白脚本").isAccessibilityEnabled())
        XCTAssertFalse(try fixture.action(named: "导入脚本").isAccessibilityEnabled())
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

/// Inert services are injected only into first-recording UI tests. They never
/// create an event tap, post input, hide the test app, or show overlay windows.
@MainActor
private final class LibraryRecordingServices {
    let recorder = LibraryFixtureRecorder()
    let countdown = LibraryFixtureCountdown()
    let application = LibraryFixtureApplication()
    let indicator = LibraryFixtureRecordingIndicator()
    let playback = LibraryFixturePlayback()

    func makeState(store: ScriptStore) -> AppState {
        AppState(store: store, recorder: recorder, countdown: countdown,
                 application: application, externalApplicationTracker: LibraryFixtureTracker(),
                 stopShortcutStore: LibraryFixtureStopShortcut(), recordingIndicator: indicator,
                 playbackEngine: playback, playbackIndicator: SilentPlaybackIndicator())
    }
}

private final class LibraryFixtureRecorder: EventRecording {
    var onTapFailure: (() -> Void)?
    var onStopRequest: (() -> Void)?
    var starts = 0
    var stops = 0
    func start(stopShortcut: RecordingStopShortcut) -> Bool { starts += 1; return true }
    func stop() -> RecordingCapture {
        stops += 1
        return .init(events: [RecordedEvent(t: 0.1, kind: .leftDown, x: 20, y: 30),
                              RecordedEvent(t: 0.2, kind: .leftUp, x: 20, y: 30)], duration: 0.8)
    }
    func cutoff(at timestamp: CGEventTimestamp) -> RecordingCutoff { .init(eventCount: 2, duration: 0.8) }
}

private final class LibraryFixtureCountdown: CountdownPresenting {
    var closes = 0
    private var finishes: [() -> Void] = []
    func show(seconds: Int, onTick: @escaping (Int) -> Void, onFinish: @escaping () -> Void) {
        finishes.append(onFinish)
    }
    func finish(at index: Int) { finishes[index]() }
    func close() { closes += 1 }
}

@MainActor
private final class LibraryFixtureApplication: ApplicationControlling {
    var restores = 0
    func activateExternalApplication(bundleIdentifier: String) -> Bool { false }
    func hideClicker() {}
    func restoreClicker() { restores += 1 }
}

@MainActor
private final class LibraryFixtureRecordingIndicator: RecordingIndicatorPresenting {
    var shows = 0
    var closes = 0
    func show(shortcut: RecordingStopShortcut) { shows += 1 }
    func close() { closes += 1 }
}

private final class LibraryFixtureTracker: ExternalApplicationTracking {
    var mostRecentExternalBundleIdentifier: String? { nil }
    func start() {}
}

private final class LibraryFixtureStopShortcut: RecordingStopShortcutProviding {
    var shortcut: RecordingStopShortcut = .defaultValue
}

@MainActor
private final class LibraryFixturePlayback: PlaybackControlling {
    var starts = 0
    func play(script: Script, onIteration: @escaping (Int) -> Void,
              onBlock: @escaping (UUID?) -> Void, onFinish: @escaping () -> Void) { starts += 1 }
    func stop() {}
}

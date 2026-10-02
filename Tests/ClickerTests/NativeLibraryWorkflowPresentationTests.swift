import AppKit
import ClickerCore
import SwiftUI
import XCTest
import Vision
@testable import Clicker

final class NativeLibraryWorkflowPresentationTests: XCTestCase {
    func testSearchTrimsWhitespaceMatchesCaseAndPreservesOrder() {
        let first = Script(name: "Safari 日报")
        let second = Script(name: "文件整理")
        let third = Script(name: "Safari weekly")
        let scripts = [first, second, third]

        XCTAssertEqual(ScriptLibrarySearch.filter(scripts, query: "  safari \n").map(\.id), [first.id, third.id])
        XCTAssertEqual(ScriptLibrarySearch.filter(scripts, query: " \n "), scripts)
        XCTAssertEqual(ScriptLibrarySearch.filter(scripts, query: "日报"), [first])
        XCTAssertTrue(ScriptLibrarySearch.filter(scripts, query: "不存在").isEmpty)
    }

    func testPermissionChecklistTracksEachPermissionIndependently() {
        for (accessibility, input, count) in [(false, false, 0), (true, false, 1), (false, true, 1), (true, true, 2)] {
            let model = PermissionChecklistPresentation(hasAccessibility: accessibility, hasInputMonitoring: input)
            XCTAssertEqual(model.grantedCount, count)
            XCTAssertEqual(model.isReady, count == 2)
        }
    }

    func testMissingPermissionsDisableStartsButNeverDisableStops() {
        let idle = PrimaryActionPresentation.pair(phase: .idle, hasPlayableScript: true, canRecord: false, canPlay: false)
        XCTAssertEqual(idle.map(\.isEnabled), [false, false])
        let recording = PrimaryActionPresentation.pair(phase: .recording, hasPlayableScript: true, canRecord: false, canPlay: false)
        XCTAssertTrue(recording[0].isStop)
        XCTAssertTrue(recording[0].isEnabled)
        let playing = PrimaryActionPresentation.pair(phase: .playing(iteration: 1, currentBlockID: nil), hasPlayableScript: true, canRecord: false, canPlay: false)
        XCTAssertTrue(playing[1].isStop)
        XCTAssertTrue(playing[1].isEnabled)
    }

    func testEstimatedDurationIncludesRepeatsAndOnlyBetweenRoundIntervals() {
        let script = Script(name: "重复", blocks: [.wait(WaitBlock(duration: 1))], repeatCount: 3, repeatInterval: 1.5)
        let presentation = ScriptHeaderPresentation(script: script)
        XCTAssertEqual(presentation.durationText, "约 1.0 秒")
        XCTAssertEqual(presentation.repeatSummaryText, "3 轮")
        XCTAssertEqual(presentation.estimatedDurationText, "约 6.0 秒")
        XCTAssertEqual(CompactScriptHeaderPresentation(script: script, phase: .idle).metadata, "1 个动作 · 3 轮 · 约 6.0 秒")
    }

    func testInfiniteDurationNeverInventsAFinishTime() {
        let script = Script(name: "持续", blocks: [.wait(WaitBlock(duration: 2))], repeatForever: true)
        let presentation = ScriptHeaderPresentation(script: script)
        XCTAssertEqual(presentation.repeatSummaryText, "无限轮")
        XCTAssertEqual(presentation.estimatedDurationText, "单轮约 2.0 秒")
    }

    func testExtremeRepeatDurationStaysReadable() {
        let script = Script(name: "长任务", blocks: [.wait(WaitBlock(duration: 2))], repeatCount: Int.max)
        XCTAssertEqual(ScriptHeaderPresentation(script: script).estimatedDurationText, "预计超过 1 年")
    }

    func testUnboundShortcutHasNoInventedKeyCombination() {
        XCTAssertNil(ScriptShortcutEditor.displayedShortcut(for: nil))
        XCTAssertNil(ScriptShortcutEditor.displayedShortcut(for: Script(name: "新建")))
        let shortcut = ScriptShortcut(keyCode: 18, modifierFlags: KeyCodeMap.maskControl | KeyCodeMap.maskOption)
        let assigned = ScriptShortcutEditor.displayedShortcut(for: Script(name: "已设置", playbackShortcut: shortcut))
        XCTAssertEqual(assigned?.keyCode, shortcut.keyCode)
        XCTAssertEqual(assigned?.modifierFlags, shortcut.modifierFlags)
    }

    func testImportPreviewDistinguishesIdentityFromNameConflicts() {
        let incoming = Script(name: "日报")
        let sameName = Script(name: "日报")
        var sameIdentity = incoming
        sameIdentity.name = "已编辑的日报"
        let nameConflict = ScriptImportPresentation(script: incoming, existingScripts: [sameName])
        XCTAssertTrue(nameConflict.hasNameConflict)
        XCTAssertNil(nameConflict.matchingIdentityName)
        let identityConflict = ScriptImportPresentation(script: incoming, existingScripts: [sameIdentity])
        XCTAssertEqual(identityConflict.matchingIdentityName, "已编辑的日报")
        XCTAssertFalse(identityConflict.hasNameConflict)
    }

    @MainActor
    func testExportNameCannotIntroducePathComponents() {
        XCTAssertEqual(ScriptTransferPanels.exportFileName(for: "日报/发布:检查\\结果"), "日报-发布-检查-结果.json")
        XCTAssertEqual(ScriptTransferPanels.exportFileName(for: " \n "), "Clicker 脚本.json")
    }

    @MainActor
    func testMainViewKeepsNativeLibraryMountedWithoutPermissions() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = AppState(store: ScriptStore(directory: directory))
        state.hasPermission = false
        let script = Script(name: "权限独立验证", blocks: [.wait(WaitBlock(duration: 1))])
        state.scripts = [script]
        state.selectedScriptID = script.id
        let host = NSHostingController(rootView: MainView().environmentObject(state).frame(width: 760, height: 480))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        let views = descendants(of: host.view)
        XCTAssertTrue(views.contains { $0 is NSSplitView })
        XCTAssertGreaterThanOrEqual(views.filter { $0 is NSOutlineView }.count, 2)
        let bitmap = try retinaBitmap(for: host.view)
        let image = try XCTUnwrap(bitmap.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        let text = (request.results ?? []).compactMap { result -> (String, CGRect)? in
            guard let candidate = result.topCandidates(1).first else { return nil }
            let box = result.boundingBox
            return (normalizedVisualText(candidate.string), CGRect(x: box.minX * 760, y: (1 - box.maxY) * 480,
                                                                    width: box.width * 760, height: box.height * 480))
        }
        let banner = try XCTUnwrap(text.first { $0.0.contains("录制与回放需要权限") }?.1)
        let libraryHeading = try XCTUnwrap(text.first { $0.0.contains("脚本库") }?.1)
        let title = try XCTUnwrap(text.first { $0.0.contains(script.name) && $0.1.minX > 210 }?.1)
        XCTAssertGreaterThan(libraryHeading.minY, banner.maxY, "Permission banner must reserve space above the library heading")
        XCTAssertGreaterThan(title.minY, banner.maxY, "Permission banner must not cover the script title")
        XCTAssertTrue(state.canEditScripts)
        XCTAssertTrue(state.createBlankScript())
        XCTAssertEqual(state.scripts.count, 2)
    }

    @MainActor
    func testSidebarActionGlyphsRenderReadableForegroundUnderSelectionTint() throws {
        _ = NSApplication.shared
        for (appearanceName, scheme) in [(NSAppearance.Name.aqua, ColorScheme.light), (.darkAqua, .dark)] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            let expected = try XCTUnwrap(ClickerVisualTheme.resolvedColor(for: .primaryText, appearance: appearance).usingColorSpace(.sRGB))
            let background = try XCTUnwrap(ClickerVisualTheme.resolvedColor(for: .selection, appearance: appearance).usingColorSpace(.sRGB))
            XCTAssertGreaterThan(contrast(expected, background), 4.5)
            for symbol in ["doc.on.doc", "ellipsis"] {
                let hosting = NSHostingView(rootView:
                    Button {} label: { ScriptSidebarActionIcon(systemName: symbol) }
                        .buttonStyle(.borderless)
                        .tint(ClickerVisualTheme.selection)
                        .frame(width: 40, height: 32)
                        .background(ClickerVisualTheme.selection)
                        .environment(\.colorScheme, scheme)
                )
                hosting.appearance = appearance
                hosting.frame = CGRect(x: 0, y: 0, width: 40, height: 32)
                let bitmap = try retinaBitmap(for: hosting)
                var readablePixels = 0
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                        if abs(color.redComponent - expected.redComponent) < 0.1,
                           abs(color.greenComponent - expected.greenComponent) < 0.1,
                           abs(color.blueComponent - expected.blueComponent) < 0.1 {
                            readablePixels += 1
                        }
                    }
                }
                XCTAssertGreaterThan(readablePixels, 4, "The actual \(symbol) glyph must remain visible under sidebar tint")
            }
        }
    }

    private func contrast(_ first: NSColor, _ second: NSColor) -> CGFloat {
        func luminance(_ color: NSColor) -> CGFloat {
            func linear(_ value: CGFloat) -> CGFloat {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    @MainActor
    private func descendants(of root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

import AppKit
import ClickerCore
import SwiftUI
import XCTest
@testable import Clicker

/// Render the real native view hierarchy. These fixtures never register global
/// hooks, record input, or use the production playback event poster.
final class NativeWorkflowSmokeTests: XCTestCase {
    @MainActor
    func testInstallerSmokeModeRequiresExplicitFlagAndKeepsMalformedRequestsInert() {
        XCTAssertNil(StartupSmokeTest(arguments: ["Clicker"]))
        XCTAssertNil(StartupSmokeTest(arguments: ["Clicker", "--smoke-report", "/tmp/report.json"]))
        let valid = StartupSmokeTest(arguments: [
            "Clicker", "--smoke-test", "--smoke-report", "/tmp/clicker-report.json",
        ])
        XCTAssertEqual(valid?.reportURL?.path, "/tmp/clicker-report.json")
        XCTAssertNotEqual(valid?.storeDirectory, ScriptStore.defaultDirectory())
        // Missing output must remain safe mode, never fall through to a real launch.
        XCTAssertNotNil(StartupSmokeTest(arguments: ["Clicker", "--smoke-test"]))
        XCTAssertNil(StartupSmokeTest(arguments: ["Clicker", "--smoke-test"])?.reportURL)
    }

    @MainActor
    func testNativeWorkflowAtMinimumSizeInBothAppearancesAndLargeText() throws {
        _ = NSApplication.shared
        let size = CGSize(width: 760, height: 480)
        for dark in [false, true] {
            for scenario in ["permissions", "long-name", "large-text", "recording-notice", "recording", "playing"] {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Clicker-Visual-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let engine = SmokeFixturePlayback()
                let state = AppState(
                    store: ScriptStore(directory: directory),
                    application: SmokeFixtureApplication(),
                    playbackEngine: engine,
                    playbackIndicator: SilentPlaybackIndicator()
                )
                let script = Script(
                    name: "每月报表整理与网页发布 · 很长的脚本名称用于检查窄窗口中的原生控件是否仍然可用",
                    blocks: [
                        .wait(WaitBlock(duration: 1)),
                        .click(ClickBlock(x: 120, y: 80, button: .left, clickCount: 1)),
                        .wait(WaitBlock(duration: 0.5)),
                    ],
                    repeatCount: 3,
                    repeatInterval: 1.5
                )
                state.scripts = [script, Script(name: "另一个脚本")]
                state.selectedScriptID = script.id
                state.hasPermission = true
                if scenario == "recording-notice" {
                    state.recordingNotice = RecordingNotice(
                        title: "录制已中断",
                        message: "已保留捕获到的操作，请检查后再回放。"
                    )
                }
                if scenario == "playing" {
                    state.playScriptFromShortcut(id: script.id)
                    state.phase = .playing(iteration: 2, currentBlockID: script.blocks[0].id)
                } else if scenario == "recording" {
                    // Display-only state; no recording entry point is invoked.
                    state.phase = .recording
                }
                let large = scenario == "large-text"
                let hostingController = NSHostingController(rootView:
                    MainView()
                        .environmentObject(state)
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .dynamicTypeSize(large ? .accessibility3 : .large)
                        .font(.system(size: large ? 19 : 13))
                        .frame(width: size.width, height: size.height)
                )
                let hosting = hostingController.view
                hosting.appearance = try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
                hosting.frame = CGRect(origin: .zero, size: size)
                let window = NSWindow(
                    contentRect: hosting.frame,
                    styleMask: [.titled],
                    backing: .buffered,
                    defer: false
                )
                window.title = "Clicker"
                window.contentViewController = hostingController
                window.makeKeyAndOrderFront(nil)
                defer { window.orderOut(nil) }
                // Activation notifications may refresh real permissions; apply the
                // fixture value only after the window has entered the run loop.
                settle(hosting)
                state.hasPermission = scenario != "permissions"
                settle(hosting)

                XCTAssertTrue(window.isVisible)
                XCTAssertEqual(hosting.bounds.size, size)
                let bitmap = try retinaBitmap(for: hosting)
                XCTAssertEqual(bitmap.pixelsWide, 1520)
                XCTAssertEqual(bitmap.pixelsHigh, 960)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(png.count, 10_000, "The native UI snapshot must not be blank")
                if let destination = ProcessInfo.processInfo.environment["CLICKER_SNAPSHOT_DIR"] {
                    let output = URL(fileURLWithPath: destination, isDirectory: true)
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                    try png.write(to: output.appendingPathComponent(
                        "\(dark ? "dark" : "light")-\(scenario)-760x480.png"
                    ))
                }

                let nativeViews = descendants(hosting)
                if ["permissions", "recording-notice"].contains(scenario) {
                    let split = try XCTUnwrap(nativeViews.compactMap { $0 as? NSSplitView }.first)
                    let splitFrame = hosting.convert(split.bounds, from: split)
                    let reservedTop = hosting.isFlipped
                        ? splitFrame.minY - hosting.bounds.minY
                        : hosting.bounds.maxY - splitFrame.maxY
                    XCTAssertGreaterThanOrEqual(
                        reservedTop, 28,
                        "\(scenario) must reserve space above the split view, not cover its title"
                    )
                    XCTAssertTrue(hosting.bounds.contains(splitFrame), "The split view must stay inside the viewport")
                }
                let outlines = nativeViews.compactMap { $0 as? NSOutlineView }
                let actions = try XCTUnwrap(outlines.first { $0.numberOfRows == script.blocks.count })
                XCTAssertTrue(actions.window === window)
                let visibleActions = hosting.convert(actions.visibleRect, from: actions)
                XCTAssertGreaterThan(visibleActions.intersection(hosting.bounds).height, 80)
                // Permission denial must leave the library and real editable
                // inputs usable. Disabled playback buttons are not edit controls.
                for placeholder in ["次数", "秒"] {
                    let field = try XCTUnwrap(nativeViews.compactMap { $0 as? NSTextField }.first {
                        $0.placeholderString == placeholder
                    }, "Missing native \(placeholder) input in \(scenario)")
                    let frame = hosting.convert(field.bounds, from: field)
                    XCTAssertTrue(hosting.bounds.contains(frame), "Input escaped the viewport: \(frame)")
                    XCTAssertFalse(field.visibleRect.isEmpty)
                    XCTAssertEqual(field.isEnabled, state.canEditScripts)
                }
                let add = try XCTUnwrap(nativeViews.compactMap { $0 as? NSPopUpButton }.first {
                    $0.accessibilityLabel() == "添加动作"
                })
                XCTAssertTrue(hosting.bounds.contains(hosting.convert(add.bounds, from: add)))
                XCTAssertEqual(add.isEnabled, state.canEditScripts)
                XCTAssertEqual(engine.playCount, scenario == "playing" ? 1 : 0)
                if scenario == "playing" { state.togglePlay() }
            }
        }
    }

    @MainActor
    private func settle(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}

@MainActor
private final class SmokeFixturePlayback: PlaybackControlling {
    private(set) var playCount = 0
    func play(
        script: Script,
        onIteration: @escaping (Int) -> Void,
        onBlock: @escaping (UUID?) -> Void,
        onFinish: @escaping () -> Void
    ) { playCount += 1 }
    func stop() {}
}

@MainActor
private final class SmokeFixtureApplication: ApplicationControlling {
    func activateExternalApplication(bundleIdentifier: String) -> Bool { false }
    func hideClicker() {}
    func restoreClicker() {}
}

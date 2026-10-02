import AppKit
import XCTest
import ClickerCore
@testable import Clicker

@MainActor
final class PlaybackIndicatorControllerTests: XCTestCase {
    private let mainFrame = CGRect(x: 0, y: 24, width: 1440, height: 852)
    private let leftFrame = CGRect(x: -1440, y: -100, width: 1440, height: 852)
    private var initial: PlaybackProgress { PlaybackProgress(script: Script(name: "测试", repeatCount: 3)) }

    func testShowCreatesOneClickableNonKeyPanelOnMainVisibleScreen() throws {
        let factory = PlaybackPanelFactory()
        let screens = [
            PlaybackIndicatorScreenDescriptor(id: "left", visibleFrame: leftFrame, isMain: false),
            PlaybackIndicatorScreenDescriptor(id: "main", visibleFrame: mainFrame, isMain: true),
        ]
        let controller = PlaybackIndicatorController(screens: { screens }, makePanel: factory.make)
        controller.show(progress: initial, onStop: {})

        let panel = try XCTUnwrap(factory.created.first)
        XCTAssertEqual(factory.created.count, 1)
        XCTAssertFalse(panel.configuration.becomesKey)
        XCTAssertFalse(panel.configuration.ignoresMouseEvents)
        XCTAssertTrue(mainFrame.contains(panel.configuration.frame))
        XCTAssertEqual(panel.configuration.frame.maxY, mainFrame.maxY - 16)
        XCTAssertEqual(panel.orderFrontCount, 1)
        XCTAssertEqual(controller.panelCount, 1)
        XCTAssertEqual(panel.progress, [initial])
    }

    func testNegativeOriginFallbackScreenAndUpdatesReusePanel() throws {
        let factory = PlaybackPanelFactory()
        let controller = PlaybackIndicatorController(screens: {
            [PlaybackIndicatorScreenDescriptor(id: "left", visibleFrame: self.leftFrame, isMain: false)]
        }, makePanel: factory.make)
        controller.show(progress: initial, onStop: {})
        let updated = PlaybackProgress(scriptName: "测试", currentStep: 3, totalSteps: 5, iteration: 2, totalIterations: 3)
        controller.update(progress: updated)

        let panel = try XCTUnwrap(factory.created.first)
        XCTAssertEqual(factory.created.count, 1)
        XCTAssertTrue(leftFrame.contains(panel.configuration.frame))
        XCTAssertLessThan(panel.configuration.frame.minX, 0)
        XCTAssertEqual(panel.progress, [initial, updated])
    }

    func testStopAndStaleCallbacksCannotAffectReplacementPanel() throws {
        let factory = PlaybackPanelFactory()
        let controller = PlaybackIndicatorController(screens: {
            [PlaybackIndicatorScreenDescriptor(id: "main", visibleFrame: self.mainFrame, isMain: true)]
        }, makePanel: factory.make)
        var firstStops = 0
        var secondStops = 0
        controller.show(progress: initial, onStop: { firstStops += 1 })
        let old = try XCTUnwrap(factory.created.first)
        controller.show(progress: initial, onStop: { secondStops += 1 })
        let current = try XCTUnwrap(factory.created.last)
        old.onStop()
        old.onStop()
        current.onStop()
        current.onStop()
        controller.close()
        controller.close()
        current.onStop()
        controller.update(progress: initial)

        XCTAssertEqual(firstStops, 0)
        XCTAssertEqual(secondStops, 1)
        XCTAssertEqual(factory.created.map(\.orderOutCount), [1, 1])
        XCTAssertEqual(controller.panelCount, 0)
        XCTAssertEqual(current.progress.count, 1)
    }

    func testNoDisplayDoesNotCreatePanel() {
        let factory = PlaybackPanelFactory()
        let controller = PlaybackIndicatorController(screens: { [] }, makePanel: factory.make)
        controller.show(progress: initial, onStop: { XCTFail("No visible panel can request stop") })
        controller.update(progress: initial)
        controller.close()
        XCTAssertEqual(controller.panelCount, 0)
        XCTAssertTrue(factory.created.isEmpty)
    }

    func testNativePanelCannotTakeKeyOrMainFocus() {
        _ = NSApplication.shared
        let panel = AppKitPlaybackIndicatorPanel(
            configuration: PlaybackIndicatorPanelConfiguration(
                frame: CGRect(x: 0, y: 0, width: 340, height: 100),
                ignoresMouseEvents: false,
                becomesKey: false
            ),
            progress: initial,
            onStop: {}
        )
        defer { panel.orderOut() }
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.contentView?.acceptsFirstMouse(for: nil) == true)
    }

    func testPresentationKeepsStepAndRoundSeparate() {
        let progress = PlaybackProgress(scriptName: "长名称", currentStep: 12, totalSteps: 20, iteration: 3, totalIterations: 5)
        XCTAssertEqual(progress.stepDescription, "步骤 12 / 20")
        XCTAssertEqual(progress.iterationDescription, "第 3 / 5 轮")
    }

    func testNativePanelRendersBothAppearancesWithoutTakingKeyWindow() throws {
        _ = NSApplication.shared
        let owner = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        owner.makeKeyAndOrderFront(nil)
        defer { owner.orderOut(nil) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        let previousKeyWindow = NSApp.keyWindow
        for dark in [false, true] {
            let panel = AppKitPlaybackIndicatorPanel(
                configuration: PlaybackIndicatorPanelConfiguration(
                    frame: CGRect(x: 30, y: 30, width: 340, height: 100),
                    ignoresMouseEvents: false,
                    becomesKey: false
                ),
                progress: PlaybackProgress(
                    scriptName: "每月报表整理 · 很长的名称也保留可见的停止操作",
                    currentStep: 12, totalSteps: 20, iteration: 3, totalIterations: 5
                ),
                onStop: {}
            )
            defer { panel.orderOut() }
            panel.appearance = try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
            panel.orderFrontRegardless()
            let view = try XCTUnwrap(panel.contentView)
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            XCTAssertTrue(NSApp.keyWindow === previousKeyWindow)
            XCTAssertFalse(panel.isKeyWindow)
            let bitmap = try retinaBitmap(for: view)
            XCTAssertEqual(bitmap.pixelsWide, 680)
            XCTAssertEqual(bitmap.pixelsHigh, 200)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 1_000)
            if let path = ProcessInfo.processInfo.environment["CLICKER_SNAPSHOT_DIR"] {
                let directory = URL(fileURLWithPath: path, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try png.write(to: directory.appendingPathComponent("\(dark ? "dark" : "light")-playback-control-340x100.png"))
            }
        }
    }
}

@MainActor
private final class PlaybackPanelFactory {
    var created: [PlaybackPanelSpy] = []
    func make(configuration: PlaybackIndicatorPanelConfiguration, progress: PlaybackProgress, onStop: @escaping () -> Void) -> PlaybackIndicatorPanel {
        let panel = PlaybackPanelSpy(configuration: configuration, progress: progress, onStop: onStop)
        created.append(panel)
        return panel
    }
}

@MainActor
private final class PlaybackPanelSpy: PlaybackIndicatorPanel {
    let configuration: PlaybackIndicatorPanelConfiguration
    let onStop: () -> Void
    var progress: [PlaybackProgress]
    var orderFrontCount = 0
    var orderOutCount = 0
    init(configuration: PlaybackIndicatorPanelConfiguration, progress: PlaybackProgress, onStop: @escaping () -> Void) {
        self.configuration = configuration
        self.progress = [progress]
        self.onStop = onStop
    }
    func orderFrontRegardless() { orderFrontCount += 1 }
    func update(progress: PlaybackProgress) { self.progress.append(progress) }
    func orderOut() { orderOutCount += 1 }
}

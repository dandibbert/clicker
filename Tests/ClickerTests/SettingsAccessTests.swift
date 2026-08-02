import AppKit
import ClickerCore
import Combine
import SwiftUI
import XCTest
@testable import Clicker

final class SettingsAccessTests: XCTestCase {
    @MainActor
    func testIconOnlySettingsButtonInvokesInjectedOpenAction() throws {
        _ = NSApplication.shared
        var openCount = 0
        let hosting = NSHostingView(rootView: SettingsButton { openCount += 1 })
        hosting.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let rendered = descendants(of: hosting)
        let button = try XCTUnwrap(
            rendered.compactMap { $0 as? NSButton }.first,
            "Rendered views: \(rendered.map { String(reflecting: type(of: $0)) })"
        )
        XCTAssertEqual(button.accessibilityLabel(), "设置")
        XCTAssertFalse(button.title.contains("设置"))
        button.performClick(nil)
        XCTAssertEqual(openCount, 1)
    }

    @MainActor
    func testDisabledSettingsButtonRendersDisabledNativeControl() throws {
        _ = NSApplication.shared
        let hosting = NSHostingView(
            rootView: SettingsButton {}
                .disabled(true)
        )
        hosting.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let button = try XCTUnwrap(descendants(of: hosting).compactMap { $0 as? NSButton }.first)
        XCTAssertFalse(button.isEnabled)
    }

    @MainActor
    func testSettingsButtonDisablesNativeControlAfterDynamicStateChange() throws {
        _ = NSApplication.shared
        let harness = SettingsButtonStateHarness()
        let hosting = NSHostingView(rootView: SettingsButtonStateHarnessView(harness: harness))
        hosting.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let enabledButton = try XCTUnwrap(
            descendants(of: hosting).compactMap { $0 as? NSButton }.first
        )
        XCTAssertTrue(enabledButton.isEnabled)
        enabledButton.performClick(nil)
        XCTAssertEqual(harness.openCount, 1)

        harness.isDisabled = true
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let disabledButton = try XCTUnwrap(
            descendants(of: hosting).compactMap { $0 as? NSButton }.first
        )
        XCTAssertFalse(disabledButton.isEnabled)
        disabledButton.performClick(nil)
        XCTAssertEqual(harness.openCount, 1)
    }

    @MainActor
    func testClickerSettingsRootMutatesInjectedSharedState() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let appearanceStore = SettingsAccessAppearanceStoreStub(preference: .system)
        let state = AppState(
            store: ScriptStore(directory: directory),
            appearancePreferenceStore: appearanceStore
        )
        let (hosting, window) = hostSettings(state)
        defer { window.orderOut(nil) }
        let segmented = try XCTUnwrap(
            descendants(of: hosting).compactMap { $0 as? NSSegmentedControl }.first
        )

        try selectSegment(1, in: segmented)

        XCTAssertEqual(state.appearancePreference, .light)
        XCTAssertEqual(appearanceStore.preference, .light)
    }

    @MainActor
    private func descendants(of root: NSView) -> [NSView] {
        root.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor
    private func hostSettings(
        _ state: AppState
    ) -> (hosting: NSHostingView<AnyView>, window: NSWindow) {
        let size = CGSize(width: 440, height: 360)
        let hosting = NSHostingView(
            rootView: AnyView(
                ClickerSettingsView()
                    .environmentObject(state)
                    .environment(\.colorScheme, .light)
            )
        )
        hosting.appearance = NSAppearance(named: .aqua)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        return (hosting, window)
    }

    @MainActor
    private func selectSegment(
        _ index: Int,
        in segmented: NSSegmentedControl
    ) throws {
        let action = try XCTUnwrap(segmented.action)
        segmented.selectedSegment = index
        XCTAssertTrue(segmented.sendAction(action, to: segmented.target))
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
}

private final class SettingsAccessAppearanceStoreStub: AppAppearancePreferenceProviding {
    var preference: AppAppearancePreference

    init(preference: AppAppearancePreference) {
        self.preference = preference
    }
}

private final class SettingsButtonStateHarness: ObservableObject {
    @Published var isDisabled = false
    var openCount = 0
}

private struct SettingsButtonStateHarnessView: View {
    @ObservedObject var harness: SettingsButtonStateHarness

    var body: some View {
        SettingsButton { harness.openCount += 1 }
            .disabled(harness.isDisabled)
    }
}

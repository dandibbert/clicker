import AppKit
import SwiftUI

struct ScreenDescriptor: Equatable {
    let id: String
    let frame: CGRect
    let isMain: Bool
}

@MainActor
protocol RecordingIndicatorPanel: AnyObject {
    func orderFrontRegardless()
    func orderOut()
}

@MainActor
final class RecordingIndicatorController: RecordingIndicatorPresenting {
    typealias ScreenProvider = @MainActor () -> [ScreenDescriptor]
    typealias PanelFactory = @MainActor (ScreenDescriptor, Bool, RecordingStopShortcut) -> RecordingIndicatorPanel

    private let screens: ScreenProvider
    private let makePanel: PanelFactory
    private var panels: [RecordingIndicatorPanel] = []

    var panelCount: Int { panels.count }

    init(
        screens: @escaping ScreenProvider = RecordingIndicatorController.systemScreens,
        makePanel: @escaping PanelFactory = RecordingIndicatorController.makePanel
    ) {
        self.screens = screens
        self.makePanel = makePanel
    }

    func show(shortcut: RecordingStopShortcut) {
        close()
        panels = screens().map { descriptor in
            let panel = makePanel(descriptor, descriptor.isMain, shortcut)
            panel.orderFrontRegardless()
            return panel
        }
    }

    func close() {
        panels.forEach { $0.orderOut() }
        panels.removeAll()
    }

    private static func systemScreens() -> [ScreenDescriptor] {
        let mainScreen = NSScreen.main
        return NSScreen.screens.map { screen in
            ScreenDescriptor(
                id: String(ObjectIdentifier(screen).hashValue),
                frame: screen.frame,
                isMain: screen === mainScreen
            )
        }
    }

    private static func makePanel(
        descriptor: ScreenDescriptor,
        showsHint: Bool,
        shortcut: RecordingStopShortcut
    ) -> RecordingIndicatorPanel {
        AppKitRecordingIndicatorPanel(
            frame: descriptor.frame,
            showsHint: showsHint,
            shortcut: shortcut
        )
    }
}

@MainActor
private final class AppKitRecordingIndicatorPanel: NSPanel, RecordingIndicatorPanel {
    override var canBecomeKey: Bool { false }

    init(frame: CGRect, showsHint: Bool, shortcut: RecordingStopShortcut) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSHostingView(
            rootView: RecordingIndicatorView(shortcut: shortcut, showsHint: showsHint)
        )
    }

    func orderOut() {
        orderOut(nil)
    }
}

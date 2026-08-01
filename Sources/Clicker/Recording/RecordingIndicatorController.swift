import AppKit
import SwiftUI

struct ScreenDescriptor: Equatable {
    let id: String
    let frame: CGRect
    let isMain: Bool
}

struct RecordingIndicatorPanelConfiguration: Equatable {
    let showsHint: Bool
    let ignoresMouseEvents: Bool
    let becomesKey: Bool
}

@MainActor
protocol RecordingIndicatorPanel: AnyObject {
    func orderFrontRegardless()
    func orderOut()
}

@MainActor
final class RecordingIndicatorController: RecordingIndicatorPresenting {
    typealias ScreenProvider = @MainActor () -> [ScreenDescriptor]
    typealias PanelFactory = @MainActor (
        ScreenDescriptor,
        RecordingIndicatorPanelConfiguration,
        RecordingStopShortcut
    ) -> RecordingIndicatorPanel

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
            let configuration = RecordingIndicatorPanelConfiguration(
                showsHint: descriptor.isMain,
                ignoresMouseEvents: true,
                becomesKey: false
            )
            let panel = makePanel(descriptor, configuration, shortcut)
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
        configuration: RecordingIndicatorPanelConfiguration,
        shortcut: RecordingStopShortcut
    ) -> RecordingIndicatorPanel {
        AppKitRecordingIndicatorPanel(
            frame: descriptor.frame,
            configuration: configuration,
            shortcut: shortcut
        )
    }
}

@MainActor
private final class AppKitRecordingIndicatorPanel: NSPanel, RecordingIndicatorPanel {
    private let becomesKey: Bool

    override var canBecomeKey: Bool { becomesKey }

    init(
        frame: CGRect,
        configuration: RecordingIndicatorPanelConfiguration,
        shortcut: RecordingStopShortcut
    ) {
        becomesKey = configuration.becomesKey
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
        ignoresMouseEvents = configuration.ignoresMouseEvents
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = NSHostingView(
            rootView: RecordingIndicatorView(
                shortcut: shortcut,
                showsHint: configuration.showsHint
            )
        )
    }

    func orderOut() {
        orderOut(nil)
    }
}

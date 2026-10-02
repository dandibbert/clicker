import AppKit
import SwiftUI

struct PlaybackIndicatorScreenDescriptor: Equatable {
    let id: String
    let visibleFrame: CGRect
    let isMain: Bool
}

struct PlaybackIndicatorPanelConfiguration: Equatable {
    let frame: CGRect
    let ignoresMouseEvents: Bool
    let becomesKey: Bool
}

@MainActor
protocol PlaybackIndicatorPanel: AnyObject {
    func orderFrontRegardless()
    func update(progress: PlaybackProgress)
    func orderOut()
}

@MainActor
final class PlaybackIndicatorController: PlaybackIndicatorPresenting {
    typealias ScreenProvider = @MainActor () -> [PlaybackIndicatorScreenDescriptor]
    typealias PanelFactory = @MainActor (
        PlaybackIndicatorPanelConfiguration,
        PlaybackProgress,
        @escaping () -> Void
    ) -> PlaybackIndicatorPanel

    private let screens: ScreenProvider
    private let makePanel: PanelFactory
    private var panel: PlaybackIndicatorPanel?
    private var generation = 0
    private var stopRequested = false

    var panelCount: Int { panel == nil ? 0 : 1 }

    init(
        screens: @escaping ScreenProvider = PlaybackIndicatorController.systemScreens,
        makePanel: @escaping PanelFactory = PlaybackIndicatorController.makePanel
    ) {
        self.screens = screens
        self.makePanel = makePanel
    }

    func show(progress: PlaybackProgress, onStop: @escaping () -> Void) {
        close()
        let availableScreens = screens()
        guard let screen = availableScreens.first(where: \.isMain) ?? availableScreens.first else { return }
        let visibleFrame = screen.visibleFrame
        let width = min(340, visibleFrame.width)
        let height = min(100, visibleFrame.height)
        let inset: CGFloat = 16
        let frame = CGRect(
            x: max(visibleFrame.minX, visibleFrame.maxX - width - inset),
            y: max(visibleFrame.minY, visibleFrame.maxY - height - inset),
            width: width,
            height: height
        )
        let configuration = PlaybackIndicatorPanelConfiguration(
            frame: frame,
            ignoresMouseEvents: false,
            becomesKey: false
        )
        let currentGeneration = generation
        stopRequested = false
        let newPanel = makePanel(configuration, progress) { [weak self] in
            guard let self,
                  self.generation == currentGeneration,
                  self.panel != nil,
                  !self.stopRequested else { return }
            self.stopRequested = true
            onStop()
        }
        panel = newPanel
        newPanel.orderFrontRegardless()
    }

    func update(progress: PlaybackProgress) {
        panel?.update(progress: progress)
    }

    func close() {
        generation += 1
        panel?.orderOut()
        panel = nil
        stopRequested = false
    }

    private static func systemScreens() -> [PlaybackIndicatorScreenDescriptor] {
        let mainScreen = NSScreen.main
        return NSScreen.screens.map { screen in
            PlaybackIndicatorScreenDescriptor(
                id: String(ObjectIdentifier(screen).hashValue),
                visibleFrame: screen.visibleFrame,
                isMain: screen === mainScreen
            )
        }
    }

    private static func makePanel(
        configuration: PlaybackIndicatorPanelConfiguration,
        progress: PlaybackProgress,
        onStop: @escaping () -> Void
    ) -> PlaybackIndicatorPanel {
        AppKitPlaybackIndicatorPanel(configuration: configuration, progress: progress, onStop: onStop)
    }
}

@MainActor
final class AppKitPlaybackIndicatorPanel: NSPanel, PlaybackIndicatorPanel {
    private let hosting: PlaybackIndicatorHostingView
    private let onStop: () -> Void

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(
        configuration: PlaybackIndicatorPanelConfiguration,
        progress: PlaybackProgress,
        onStop: @escaping () -> Void
    ) {
        self.onStop = onStop
        hosting = PlaybackIndicatorHostingView(rootView: PlaybackIndicatorView(progress: progress, onStop: onStop))
        super.init(
            contentRect: configuration.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = configuration.ignoresMouseEvents
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hosting
        setAccessibilityLabel("回放控制")
    }

    func update(progress: PlaybackProgress) {
        hosting.rootView = PlaybackIndicatorView(progress: progress, onStop: onStop)
    }

    func orderOut() {
        orderOut(nil)
    }
}

@MainActor
private final class PlaybackIndicatorHostingView: NSHostingView<PlaybackIndicatorView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

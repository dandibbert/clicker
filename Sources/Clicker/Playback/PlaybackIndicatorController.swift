import AppKit
import SwiftUI
import ClickerCore

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
    typealias MainDisplayTopProvider = @MainActor () -> CGFloat
    typealias PanelFactory = @MainActor (
        PlaybackIndicatorPanelConfiguration,
        PlaybackProgress,
        @escaping () -> Void
    ) -> PlaybackIndicatorPanel

    private let screens: ScreenProvider
    private let makePanel: PanelFactory
    private let mainDisplayTop: MainDisplayTopProvider
    private var playbackPoints: [CGPoint] = []
    private var panel: PlaybackIndicatorPanel?
    private var generation = 0
    private var stopRequested = false

    var panelCount: Int { panel == nil ? 0 : 1 }

    init(
        screens: @escaping ScreenProvider = PlaybackIndicatorController.systemScreens,
        makePanel: @escaping PanelFactory = PlaybackIndicatorController.makePanel,
        mainDisplayTop: @escaping MainDisplayTopProvider = PlaybackIndicatorController.systemMainDisplayTop
    ) {
        self.screens = screens
        self.makePanel = makePanel
        self.mainDisplayTop = mainDisplayTop
    }

    func prepare(script: Script) {
        // CGEvent and NSScreen use different vertical origins. The transform is
        // anchored to the primary display, never the currently focused screen.
        let top = mainDisplayTop()
        playbackPoints = BlockExpander.plan(for: script).steps.compactMap { step in
            let point: CGPoint
            switch step.action {
            case .mouseMove(let x, let y, _),
                 .mouseDown(let x, let y, _, _, _),
                 .mouseUp(let x, let y, _, _, _),
                 .mouseDrag(let x, let y, _, _),
                 .scroll(let x, let y, _, _, _):
                point = CGPoint(x: x, y: top - CGFloat(y))
            case .keyDown, .keyUp:
                return nil
            }
            return point.x.isFinite && point.y.isFinite ? point : nil
        }
    }

    func show(progress: PlaybackProgress, onStop: @escaping () -> Void) {
        close()
        let availableScreens = screens().filter { $0.visibleFrame.width > 0 && $0.visibleFrame.height > 0 }
        let orderedScreens = availableScreens.filter(\.isMain) + availableScreens.filter { !$0.isMain }
        let candidates = orderedScreens.flatMap { Self.cornerFrames(in: $0.visibleFrame) }
        guard let fallback = candidates.first else { return }
        let safeFrame = candidates.first { frame in
            let protectedFrame = frame.insetBy(dx: -12, dy: -12)
            return !playbackPoints.contains(where: protectedFrame.contains)
        }
        let configuration = PlaybackIndicatorPanelConfiguration(
            frame: safeFrame ?? fallback,
            ignoresMouseEvents: safeFrame == nil,
            becomesKey: false
        )
        let currentGeneration = generation
        stopRequested = false
        let newPanel = makePanel(configuration, progress) { [weak self] in
            guard let self,
                  !configuration.ignoresMouseEvents,
                  self.generation == currentGeneration,
                  self.panel != nil,
                  !self.stopRequested else { return }
            self.stopRequested = true
            onStop()
        }
        panel = newPanel
        newPanel.orderFrontRegardless()
    }

    private static func cornerFrames(in visibleFrame: CGRect) -> [CGRect] {
        let width = min(340, visibleFrame.width)
        let height = min(100, visibleFrame.height)
        let inset: CGFloat = 16
        let left = min(visibleFrame.minX + inset, visibleFrame.maxX - width)
        let right = max(visibleFrame.minX, visibleFrame.maxX - width - inset)
        let bottom = min(visibleFrame.minY + inset, visibleFrame.maxY - height)
        let top = max(visibleFrame.minY, visibleFrame.maxY - height - inset)
        // Bottom corners are less likely to cover menus or toolbar controls.
        return [(right, bottom), (left, bottom), (right, top), (left, top)].map { x, y in
            CGRect(x: x, y: y, width: width, height: height)
        }
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

    private static func systemMainDisplayTop() -> CGFloat {
        NSScreen.screens.first?.frame.maxY ?? CGDisplayBounds(CGMainDisplayID()).height
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
    private let canStopWithButton: Bool

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(
        configuration: PlaybackIndicatorPanelConfiguration,
        progress: PlaybackProgress,
        onStop: @escaping () -> Void
    ) {
        self.onStop = onStop
        canStopWithButton = !configuration.ignoresMouseEvents
        hosting = PlaybackIndicatorHostingView(rootView: PlaybackIndicatorView(
            progress: progress, onStop: onStop, canStopWithButton: !configuration.ignoresMouseEvents
        ))
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
        // Placement was checked against the recorded path. Moving this panel
        // while playback is active could put Stop underneath synthetic input.
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hosting
        setAccessibilityLabel("回放控制")
    }

    func update(progress: PlaybackProgress) {
        hosting.rootView = PlaybackIndicatorView(progress: progress, onStop: onStop, canStopWithButton: canStopWithButton)
    }

    func orderOut() {
        orderOut(nil)
    }
}

@MainActor
private final class PlaybackIndicatorHostingView: NSHostingView<PlaybackIndicatorView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

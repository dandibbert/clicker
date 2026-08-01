import AppKit
import CoreGraphics
import ClickerCore

protocol EventRecording: AnyObject {
    var onTapFailure: (() -> Void)? { get set }
    var onStopRequest: (() -> Void)? { get set }

    func start(stopShortcut: RecordingStopShortcut) -> Bool
    func stop() -> RecordingCapture
    func cutoff(at timestamp: CGEventTimestamp) -> RecordingCutoff
}

protocol CountdownPresenting: AnyObject {
    func show(
        seconds: Int,
        onTick: @escaping (Int) -> Void,
        onFinish: @escaping () -> Void
    )
    func close()
}

protocol RecordingApplicationControlling: AnyObject {
    func frontmostApplicationBundleIdentifier() -> String?
    func hideClicker()
    func restoreClicker()
}

final class SystemRecordingApplicationController: RecordingApplicationControlling {
    typealias WindowHandle = AnyObject
    typealias WindowList = () -> [WindowHandle]
    typealias WindowAction = (WindowHandle) -> Void

    private let visibleWindows: WindowList
    private let conceal: WindowAction
    private let reveal: WindowAction
    private let deactivateClicker: () -> Void
    private let activateClicker: () -> Void
    private var hiddenWindows: [WindowHandle] = []

    convenience init() {
        self.init(
            visibleWindows: {
                NSApp.windows.filter { window in
                    window.isVisible && !(window is NSPanel)
                }
            },
            conceal: Self.conceal,
            reveal: Self.reveal,
            deactivateClicker: { NSApp.deactivate() },
            activateClicker: { NSApp.activate(ignoringOtherApps: true) }
        )
    }

    init(
        visibleWindows: @escaping WindowList,
        conceal: @escaping WindowAction,
        reveal: @escaping WindowAction,
        deactivateClicker: @escaping () -> Void,
        activateClicker: @escaping () -> Void
    ) {
        self.visibleWindows = visibleWindows
        self.conceal = conceal
        self.reveal = reveal
        self.deactivateClicker = deactivateClicker
        self.activateClicker = activateClicker
    }

    static func conceal(_ handle: WindowHandle) {
        guard let window = handle as? NSWindow else { return }
        window.alphaValue = 0
        window.ignoresMouseEvents = true
    }

    static func reveal(_ handle: WindowHandle) {
        guard let window = handle as? NSWindow else { return }
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        window.orderFront(nil)
    }

    func frontmostApplicationBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func hideClicker() {
        hiddenWindows = visibleWindows()
        hiddenWindows.forEach(conceal)
        deactivateClicker()
    }

    func restoreClicker() {
        hiddenWindows.forEach(reveal)
        hiddenWindows = []
        activateClicker()
    }
}

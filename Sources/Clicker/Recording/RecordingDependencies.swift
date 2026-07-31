import AppKit
import CoreGraphics
import ClickerCore

protocol EventRecording: AnyObject {
    var onTapFailure: (() -> Void)? { get set }
    var onStopRequest: (() -> Void)? { get set }

    func start() -> Bool
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
    private let orderOut: WindowAction
    private let orderFront: WindowAction
    private let activateClicker: () -> Void
    private var hiddenWindows: [WindowHandle] = []

    convenience init() {
        self.init(
            visibleWindows: {
                NSApp.windows.filter { window in
                    window.isVisible && !(window is NSPanel)
                }
            },
            orderOut: { ($0 as? NSWindow)?.orderOut(nil) },
            orderFront: { ($0 as? NSWindow)?.orderFront(nil) },
            activateClicker: { NSApp.activate(ignoringOtherApps: true) }
        )
    }

    init(
        visibleWindows: @escaping WindowList,
        orderOut: @escaping WindowAction,
        orderFront: @escaping WindowAction,
        activateClicker: @escaping () -> Void
    ) {
        self.visibleWindows = visibleWindows
        self.orderOut = orderOut
        self.orderFront = orderFront
        self.activateClicker = activateClicker
    }

    func frontmostApplicationBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func hideClicker() {
        hiddenWindows = visibleWindows()
        hiddenWindows.forEach(orderOut)
    }

    func restoreClicker() {
        hiddenWindows.forEach(orderFront)
        hiddenWindows = []
        activateClicker()
    }
}

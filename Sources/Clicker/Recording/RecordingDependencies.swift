import AppKit
import CoreGraphics
import ClickerCore

protocol EventRecording: AnyObject {
    var onTapFailure: (() -> Void)? { get set }

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
    func frontmostApplicationBundleIdentifier() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func hideClicker() {
        NSApp.hide(nil)
    }

    func restoreClicker() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

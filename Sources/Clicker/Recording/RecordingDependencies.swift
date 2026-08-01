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

@MainActor
protocol RecordingIndicatorPresenting: AnyObject {
    func show(shortcut: RecordingStopShortcut)
    func close()
}

protocol RecordingStopShortcutProviding: AnyObject {
    var shortcut: RecordingStopShortcut { get set }
}

extension RecordingStopShortcutStore: RecordingStopShortcutProviding {}

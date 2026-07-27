import CoreGraphics
import ClickerCore

final class MenuBarRecordingCutoffController {
    private let establishCutoff: (CGEventTimestamp) -> RecordingCutoff?
    private let stopRecording: (RecordingCutoff) -> Void
    private var pendingCutoff: RecordingCutoff?

    init(
        establishCutoff: @escaping (CGEventTimestamp) -> RecordingCutoff?,
        stopRecording: @escaping (RecordingCutoff) -> Void
    ) {
        self.establishCutoff = establishCutoff
        self.stopRecording = stopRecording
    }

    func menuWillOpen(at timestamp: CGEventTimestamp) {
        if pendingCutoff == nil {
            pendingCutoff = establishCutoff(timestamp)
        }
    }

    func interactionBegan(at timestamp: CGEventTimestamp) {
        if pendingCutoff == nil {
            pendingCutoff = establishCutoff(timestamp)
        }
    }

    func interactionCancelled() {
        pendingCutoff = nil
    }

    func stopSelected() {
        guard let pendingCutoff else { return }
        self.pendingCutoff = nil
        stopRecording(pendingCutoff)
    }
}

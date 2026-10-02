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

    /// The quit path needs the same cutoff without committing to saving yet.
    func takePendingCutoff() -> RecordingCutoff? {
        defer { pendingCutoff = nil }
        return pendingCutoff
    }

    func stopSelected() {
        guard let cutoff = takePendingCutoff() else { return }
        stopRecording(cutoff)
    }
}

import AppKit
import CoreGraphics

enum PlaybackStopEventClassifier {
    static func shouldStop(for event: CGEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        return shouldStop(
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            sourceUserData: event.getIntegerValueField(.eventSourceUserData)
        )
    }

    static func shouldStop(keyCode: UInt16, sourceUserData: Int64) -> Bool {
        keyCode == 53 && sourceUserData != EventRecorder.syntheticMarker
    }
}

@MainActor
final class SystemPlaybackStopMonitor: PlaybackStopMonitoring {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start(onStop: @escaping () -> Void) {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if Self.shouldStop(for: event) {
                Task { @MainActor in onStop() }
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Self.shouldStop(for: event) else { return event }
            Task { @MainActor in onStop() }
            return nil
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private static func shouldStop(for event: NSEvent) -> Bool {
        let sourceUserData = event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0
        return PlaybackStopEventClassifier.shouldStop(
            keyCode: event.keyCode,
            sourceUserData: sourceUserData
        )
    }
}

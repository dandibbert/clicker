import AppKit
import ClickerCore

@MainActor
protocol PlaybackTiming: AnyObject {
    var now: TimeInterval { get }
    func sleep(until deadline: TimeInterval) async throws
    func cooperativeYield() async
}

@MainActor
protocol PlaybackEventPosting: AnyObject {
    func post(_ action: StepAction)
}

@MainActor
protocol PlaybackStopMonitoring: AnyObject {
    func start(onStop: @escaping () -> Void)
    func stop()
}

@MainActor
final class SystemPlaybackTiming: PlaybackTiming {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func sleep(until deadline: TimeInterval) async throws {
        let delay = max(0, deadline - now)
        if delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }
    }

    func cooperativeYield() async {
        await Task.yield()
    }
}

@MainActor
final class SystemPlaybackEventPoster: PlaybackEventPosting {
    func post(_ action: StepAction) {
        EventPoster.post(action)
    }
}

@MainActor
final class SystemPlaybackStopMonitor: PlaybackStopMonitoring {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start(onStop: @escaping () -> Void) {
        stop()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                Task { @MainActor in onStop() }
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                Task { @MainActor in onStop() }
                return nil
            }
            return event
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
}

import AppKit
import ClickerCore
import CVirtualDisplayPrivate

@MainActor
protocol PlaybackTiming: AnyObject {
    var now: TimeInterval { get }
    func sleep(until deadline: TimeInterval) async throws
    func cooperativeYield() async
}

@MainActor
protocol PlaybackEventPosting: AnyObject {
    func begin(script: Script) -> Bool
    func post(_ action: StepAction)
    func end()
}

extension PlaybackEventPosting {
    func begin(script _: Script) -> Bool { true }
    func end() {}
}

@MainActor
protocol PlaybackStopMonitoring: AnyObject {
    func start(onStop: @escaping () -> Void)
    func stop()
}

@MainActor
protocol PlaybackControlling: AnyObject {
    func play(
        script: Script,
        onIteration: @escaping (Int) -> Void,
        onBlock: @escaping (UUID?) -> Void,
        onFinish: @escaping () -> Void
    )
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
    private var destination: EventPoster.Destination = .system
    private var parkedWindowID: CGWindowID?
    private var parkingInfo: ClickerSpaceParkingInfo?

    func begin(script: Script) -> Bool {
        restoreParkingIfNeeded()

        switch script.playbackDeliveryMode {
        case .foreground:
            destination = .system
            return true

        case .background:
            guard
                let bundleIdentifier = script.targetBundleIdentifier,
                let initialTarget = BackgroundPlaybackTargetResolver.resolve(
                    bundleIdentifier: bundleIdentifier
                )
            else {
                destination = .system
                return false
            }

            var target = initialTarget

            if !initialTarget.isOnScreen {
                guard let windowID = initialTarget.windowID else {
                    NSLog("[Clicker] background playback: target has no window ID")
                    destination = .system
                    return false
                }

                var info = ClickerSpaceParkingInfo()
                guard clicker_window_park_on_current_space(windowID, &info) else {
                    NSLog("[Clicker] background playback: verified Space parking failed")
                    destination = .system
                    return false
                }

                parkedWindowID = windowID
                parkingInfo = info
                target = BackgroundPlaybackTargetResolver.resolve(
                    bundleIdentifier: bundleIdentifier,
                    preferredWindowID: windowID
                ) ?? initialTarget

                NSLog(
                    "[Clicker] background playback parked window=%u sourceSpace=%llu currentSpace=%llu",
                    windowID,
                    info.sourceSpaceID,
                    info.targetSpaceID
                )
            }

            destination = .process(
                pid: target.pid,
                windowID: target.windowID
            )
            NSLog(
                "[Clicker] background playback ready: pid=%d window=%u originalOnScreen=%@",
                target.pid,
                target.windowID ?? 0,
                initialTarget.isOnScreen ? "yes" : "no"
            )
            return true
        }
    }

    func post(_ action: StepAction) {
        EventPoster.post(action, to: destination)
    }

    func end() {
        restoreParkingIfNeeded()
        destination = .system
    }

    private func restoreParkingIfNeeded() {
        guard var info = parkingInfo, let windowID = parkedWindowID else {
            parkingInfo = nil
            parkedWindowID = nil
            return
        }

        let restored = clicker_window_restore_from_parking(
            windowID,
            &info
        )
        if !restored {
            NSLog(
                "[Clicker] warning: failed restoring parked background window=%u",
                windowID
            )
        }
        parkingInfo = nil
        parkedWindowID = nil
    }
}

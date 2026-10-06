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

    func begin(script: Script) -> Bool {
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
            var translation = CGPoint.zero

            if !initialTarget.isOnScreen {
                guard
                    let displayBounds = BackgroundVirtualDisplayManager.ensureDisplay(),
                    BackgroundWindowRelocator.moveTargetWindow(
                        bundleIdentifier: bundleIdentifier,
                        to: displayBounds
                    )
                else {
                    NSLog("[Clicker] background playback: virtual-display fallback unavailable")
                    destination = .system
                    return false
                }

                let movedTarget = BackgroundPlaybackTargetResolver.resolve(
                    bundleIdentifier: bundleIdentifier
                )
                guard let movedTarget, movedTarget.isOnScreen else {
                    NSLog("[Clicker] background playback: target window remained off-screen")
                    destination = .system
                    return false
                }

                if let before = initialTarget.bounds, let after = movedTarget.bounds {
                    translation = CGPoint(
                        x: after.minX - before.minX,
                        y: after.minY - before.minY
                    )
                }
                target = movedTarget
            }

            NSLog(
                "[Clicker] background playback: pid=%d window=%u onScreen=%@ dx=%.1f dy=%.1f",
                target.pid,
                target.windowID ?? 0,
                target.isOnScreen ? "yes" : "no",
                translation.x,
                translation.y
            )
            destination = .process(
                pid: target.pid,
                windowID: target.windowID,
                translation: translation
            )
            return true
        }
    }

    func post(_ action: StepAction) {
        EventPoster.post(action, to: destination)
    }

    func end() {
        destination = .system
    }
}

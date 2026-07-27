import AppKit

@MainActor
protocol PlaybackApplicationControlling: AnyObject {
    func captureAndActivate(target: String?) -> PlaybackApplicationSession
}

@MainActor
final class PlaybackApplicationSession {
    private var restoreAction: (() -> Void)?

    init(restore: @escaping () -> Void = {}) {
        restoreAction = restore
    }

    func restore() {
        let action = restoreAction
        restoreAction = nil
        action?()
    }
}

@MainActor
final class SystemPlaybackApplicationController: PlaybackApplicationControlling {
    private let frontmostBundleIdentifier: () -> String?
    private let activate: (String) -> Bool

    init() {
        frontmostBundleIdentifier = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
        activate = { bundleIdentifier in
            guard let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).first else {
                return false
            }
            return application.activate(options: [.activateAllWindows])
        }
    }

    init(
        frontmostBundleIdentifier: @escaping () -> String?,
        activate: @escaping (String) -> Bool
    ) {
        self.frontmostBundleIdentifier = frontmostBundleIdentifier
        self.activate = activate
    }

    func captureAndActivate(target: String?) -> PlaybackApplicationSession {
        guard let target, !target.isEmpty else { return PlaybackApplicationSession() }
        let previous = frontmostBundleIdentifier()
        guard previous != target else { return PlaybackApplicationSession() }
        guard activate(target) else { return PlaybackApplicationSession() }
        guard let previous else { return PlaybackApplicationSession() }

        return PlaybackApplicationSession { [activate] in
            _ = activate(previous)
        }
    }
}

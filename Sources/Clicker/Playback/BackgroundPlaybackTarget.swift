import AppKit
import CoreGraphics

struct BackgroundPlaybackTarget: Equatable {
    let pid: pid_t
    let windowID: CGWindowID?
}

/// Resolves a recorded bundle identifier to a live process and, when possible,
/// its top-level window. The window lookup intentionally uses optionAll so
/// windows on inactive Spaces remain eligible.
enum BackgroundPlaybackTargetResolver {
    static func resolve(bundleIdentifier: String) -> BackgroundPlaybackTarget? {
        guard !bundleIdentifier.isEmpty,
              let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
              ).first else {
            return nil
        }

        let pid = application.processIdentifier
        return BackgroundPlaybackTarget(
            pid: pid,
            windowID: firstTopLevelWindowID(for: pid)
        )
    }

    private static func firstTopLevelWindowID(for pid: pid_t) -> CGWindowID? {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else {
            return nil
        }

        for entry in entries {
            guard
                let ownerPID = entry[kCGWindowOwnerPID as String] as? NSNumber,
                ownerPID.int32Value == pid,
                let layer = entry[kCGWindowLayer as String] as? NSNumber,
                layer.intValue == 0,
                let number = entry[kCGWindowNumber as String] as? NSNumber
            else {
                continue
            }

            return CGWindowID(number.uint32Value)
        }

        return nil
    }
}

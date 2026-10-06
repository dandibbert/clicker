import AppKit
import CoreGraphics

struct BackgroundPlaybackTarget: Equatable {
    let pid: pid_t
    let windowID: CGWindowID?
    let bounds: CGRect?
    let isOnScreen: Bool
}

/// Resolves a recorded bundle identifier to a live process and, when possible,
/// its top-level window. The window lookup intentionally uses optionAll so
/// windows on inactive Spaces remain eligible.
enum BackgroundPlaybackTargetResolver {
    static func resolve(
        bundleIdentifier: String,
        preferredWindowID: CGWindowID? = nil
    ) -> BackgroundPlaybackTarget? {
        guard !bundleIdentifier.isEmpty,
              let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
              ).first else {
            return nil
        }

        let pid = application.processIdentifier
        guard let window = firstTopLevelWindow(
            for: pid,
            preferredWindowID: preferredWindowID
        ) else {
            return BackgroundPlaybackTarget(
                pid: pid,
                windowID: nil,
                bounds: nil,
                isOnScreen: false
            )
        }
        return BackgroundPlaybackTarget(
            pid: pid,
            windowID: window.id,
            bounds: window.bounds,
            isOnScreen: window.isOnScreen
        )
    }

    private static func firstTopLevelWindow(
        for pid: pid_t,
        preferredWindowID: CGWindowID?
    ) -> (id: CGWindowID, bounds: CGRect?, isOnScreen: Bool)? {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else {
            return nil
        }

        var fallback: (id: CGWindowID, bounds: CGRect?, isOnScreen: Bool)?
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

            let bounds: CGRect? = {
                guard let dictionary = entry[kCGWindowBounds as String] as? NSDictionary else {
                    return nil
                }
                return CGRect(dictionaryRepresentation: dictionary)
            }()
            let isOnScreen = (
                entry[kCGWindowIsOnscreen as String] as? NSNumber
            )?.boolValue ?? false
            let candidate = (
                id: CGWindowID(number.uint32Value),
                bounds: bounds,
                isOnScreen: isOnScreen
            )

            if candidate.id == preferredWindowID {
                return candidate
            }
            if fallback == nil {
                fallback = candidate
            }
        }

        return fallback
    }
}

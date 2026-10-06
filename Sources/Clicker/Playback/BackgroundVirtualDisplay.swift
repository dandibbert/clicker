import AppKit
import ApplicationServices
import CoreGraphics
import CVirtualDisplayPrivate

@MainActor
enum BackgroundVirtualDisplayManager {
    private static var cachedBounds: CGRect?

    static func ensureDisplay() -> CGRect? {
        if let cachedBounds {
            return cachedBounds
        }

        var info = ClickerVirtualDisplayInfo()
        guard clicker_virtual_display_start(1920, 1080, &info) else {
            return nil
        }

        let bounds = CGRect(
            x: info.x,
            y: info.y,
            width: info.width,
            height: info.height
        )
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }
        cachedBounds = bounds
        return bounds
    }
}

@MainActor
enum BackgroundWindowRelocator {
    static func moveTargetWindow(
        bundleIdentifier: String,
        to displayBounds: CGRect
    ) -> Bool {
        guard
            let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).first
        else {
            return false
        }

        let applicationElement = AXUIElementCreateApplication(
            application.processIdentifier
        )
        guard let window = preferredWindow(of: applicationElement) else {
            NSLog("[Clicker] background playback: no AX window for target")
            return false
        }

        var targetPoint = CGPoint(
            x: displayBounds.minX + 32,
            y: displayBounds.minY + 32
        )
        guard let positionValue = AXValueCreate(.cgPoint, &targetPoint) else {
            return false
        }

        let result = AXUIElementSetAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            positionValue
        )
        guard result == .success else {
            NSLog(
                "[Clicker] background playback: AX move failed (%d)",
                result.rawValue
            )
            return false
        }

        // Raising the window does not activate the application. It only makes
        // the chosen target the top window inside its own process/display.
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        return true
    }

    private static func preferredWindow(
        of application: AXUIElement
    ) -> AXUIElement? {
        if let focused = copyElement(
            from: application,
            attribute: kAXFocusedWindowAttribute as CFString
        ) {
            return focused
        }

        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                application,
                kAXWindowsAttribute as CFString,
                &value
            ) == .success,
            let windows = value as? [AXUIElement]
        else {
            return nil
        }
        return windows.first
    }

    private static func copyElement(
        from element: AXUIElement,
        attribute: CFString
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
            let value,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
}

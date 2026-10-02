import AppKit

@MainActor
protocol ApplicationControlling: AnyObject {
    func activateExternalApplication(bundleIdentifier: String) -> Bool
    func verifyExternalApplicationActivation(bundleIdentifier: String, completion: @escaping (Bool) -> Void)
    func hideClicker()
    func restoreClicker()
}

extension ApplicationControlling {
    func verifyExternalApplicationActivation(bundleIdentifier: String, completion: @escaping (Bool) -> Void) {
        completion(true)
    }
}

@MainActor
final class SystemApplicationController: ApplicationControlling {
    typealias WindowHandle = AnyObject
    typealias WindowList = () -> [WindowHandle]
    typealias WindowAction = (WindowHandle) -> Void

    private let visibleWindows: WindowList
    private let conceal: WindowAction
    private let reveal: WindowAction
    private let deactivateClicker: () -> Void
    private let activateClicker: () -> Void
    private let activateExternal: (String) -> Bool
    private var hiddenWindows: [WindowHandle] = []

    convenience init() {
        self.init(
            visibleWindows: {
                NSApp.windows.filter { window in
                    window.isVisible && !(window is NSPanel)
                }
            },
            conceal: Self.conceal,
            reveal: Self.reveal,
            deactivateClicker: { NSApp.deactivate() },
            activateClicker: { NSApp.activate(ignoringOtherApps: true) },
            activateExternal: { bundleIdentifier in
                guard let application = NSRunningApplication.runningApplications(
                    withBundleIdentifier: bundleIdentifier
                ).first else {
                    return false
                }
                return application.activate(options: [.activateAllWindows])
            }
        )
    }

    init(
        visibleWindows: @escaping WindowList,
        conceal: @escaping WindowAction,
        reveal: @escaping WindowAction,
        deactivateClicker: @escaping () -> Void,
        activateClicker: @escaping () -> Void,
        activateExternal: @escaping (String) -> Bool
    ) {
        self.visibleWindows = visibleWindows
        self.conceal = conceal
        self.reveal = reveal
        self.deactivateClicker = deactivateClicker
        self.activateClicker = activateClicker
        self.activateExternal = activateExternal
    }

    static func conceal(_ handle: WindowHandle) {
        guard let window = handle as? NSWindow else { return }
        window.alphaValue = 0
        window.ignoresMouseEvents = true
    }

    static func reveal(_ handle: WindowHandle) {
        guard let window = handle as? NSWindow else { return }
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        window.orderFront(nil)
    }

    func activateExternalApplication(bundleIdentifier: String) -> Bool {
        activateExternal(bundleIdentifier)
    }

    func verifyExternalApplicationActivation(bundleIdentifier: String, completion: @escaping (Bool) -> Void) {
        Task { @MainActor in
            // Activation is asynchronous; verify the selected app before the first synthetic input.
            for _ in 0..<20 {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier {
                    completion(true)
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            completion(false)
        }
    }

    func hideClicker() {
        hiddenWindows = visibleWindows()
        hiddenWindows.forEach(conceal)
        deactivateClicker()
    }

    func restoreClicker() {
        hiddenWindows.forEach(reveal)
        hiddenWindows = []
        activateClicker()
    }
}

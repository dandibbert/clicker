import AppKit

protocol ExternalApplicationTracking: AnyObject {
    var mostRecentExternalBundleIdentifier: String? { get }
    func start()
}

final class SystemExternalApplicationTracker: ExternalApplicationTracking {
    private let clickerBundleIdentifier: String
    private let initialFrontmostBundleIdentifier: () -> String?
    private let notificationCenter: NotificationCenter
    private let activatedBundleIdentifier: (Notification) -> String?

    private(set) var mostRecentExternalBundleIdentifier: String?
    private var observer: NSObjectProtocol?
    private var hasStarted = false

    init(
        clickerBundleIdentifier: String = "local.rayscripts.clicker",
        initialFrontmostBundleIdentifier: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        activatedBundleIdentifier: @escaping (Notification) -> String? = { notification in
            (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
        }
    ) {
        self.clickerBundleIdentifier = clickerBundleIdentifier
        self.initialFrontmostBundleIdentifier = initialFrontmostBundleIdentifier
        self.notificationCenter = notificationCenter
        self.activatedBundleIdentifier = activatedBundleIdentifier
    }

    deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        accept(initialFrontmostBundleIdentifier())
        observer = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.accept(self?.activatedBundleIdentifier(notification))
        }
    }

    private func accept(_ candidate: String?) {
        guard let candidate, !candidate.isEmpty,
              candidate != clickerBundleIdentifier else { return }
        mostRecentExternalBundleIdentifier = candidate
    }
}

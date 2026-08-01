import Foundation

/// AppKit 已建立应用连接后，再启动依赖系统 UI 的进程级服务。
@MainActor
final class ApplicationServiceCoordinator {
    typealias StatusItemFactory = () -> AnyObject
    typealias HotKeyRegistration = () -> [HotKeyRegistrationIssue]

    private let state: AppState
    private let makeStatusItem: StatusItemFactory
    private let registerHotKeys: HotKeyRegistration
    private var retainedStatusItem: AnyObject?
    private var hasStarted = false

    convenience init(state: AppState) {
        let hotKeys = HotKeyCenter()
        self.init(
            state: state,
            makeStatusItem: { StatusItemController(state: state) },
            registerHotKeys: { hotKeys.register() }
        )
    }

    init(
        state: AppState,
        makeStatusItem: @escaping StatusItemFactory,
        registerHotKeys: @escaping HotKeyRegistration
    ) {
        self.state = state
        self.makeStatusItem = makeStatusItem
        self.registerHotKeys = registerHotKeys
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        state.externalApplicationTracker.start()
        retainedStatusItem = makeStatusItem()
        state.reportHotKeyRegistrationIssues(registerHotKeys())
    }
}

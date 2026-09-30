import Foundation
import Combine
import ClickerCore

/// AppKit 已建立应用连接后，再启动依赖系统 UI 的进程级服务。
@MainActor
final class ApplicationServiceCoordinator {
    typealias StatusItemFactory = () -> AnyObject
    typealias HotKeyRegistration = () -> [HotKeyRegistrationIssue]
    typealias ScriptHotKeyRefresh = ([Script]) -> [ScriptHotKeyRegistrationIssue]

    private let state: AppState
    private let makeStatusItem: StatusItemFactory
    private let registerHotKeys: HotKeyRegistration
    private let refreshScriptHotKeys: ScriptHotKeyRefresh
    private var retainedStatusItem: AnyObject?
    private var scriptObservation: AnyCancellable?
    private var hasStarted = false

    convenience init(state: AppState) {
        let hotKeys = HotKeyCenter()
        let scriptHotKeys = ScriptHotKeyCenter()
        scriptHotKeys.onTrigger = { [weak state] scriptID in
            state?.playScriptFromShortcut(id: scriptID)
        }
        self.init(
            state: state,
            makeStatusItem: { StatusItemController(state: state) },
            registerHotKeys: { hotKeys.register() },
            refreshScriptHotKeys: { scripts in
                scriptHotKeys.start()
                return scriptHotKeys.refresh(scripts: scripts)
            }
        )
    }

    init(
        state: AppState,
        makeStatusItem: @escaping StatusItemFactory,
        registerHotKeys: @escaping HotKeyRegistration,
        refreshScriptHotKeys: @escaping ScriptHotKeyRefresh = { _ in [] }
    ) {
        self.state = state
        self.makeStatusItem = makeStatusItem
        self.registerHotKeys = registerHotKeys
        self.refreshScriptHotKeys = refreshScriptHotKeys
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        state.externalApplicationTracker.start()
        retainedStatusItem = makeStatusItem()
        state.reportHotKeyRegistrationIssues(registerHotKeys())
        scriptObservation = state.$scripts
            .sink { [weak self] scripts in
                guard let self else { return }
                state.reportScriptHotKeyRegistrationIssues(refreshScriptHotKeys(scripts))
            }
    }
}

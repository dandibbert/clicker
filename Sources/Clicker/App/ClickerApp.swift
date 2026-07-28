import SwiftUI

@main
struct ClickerApp: App {
    @StateObject private var state: AppState
    private let hotKeys = HotKeyCenter()
    private let statusItem: StatusItemController

    init() {
        let s = AppState()
        _state = StateObject(wrappedValue: s)
        statusItem = StatusItemController(state: s)
        s.setUp()
        s.reportHotKeyRegistrationIssues(hotKeys.register())
    }

    var body: some Scene {
        Window("Clicker", id: "main") {
            MainView()
                .environmentObject(state)
                .frame(minWidth: 760, minHeight: 480)
        }
    }
}

extension Notification.Name {
    /// 统一的控制通道：菜单栏、快捷键、UI 按钮都发这两个通知，由引擎层监听。
    static let toggleRecord = Notification.Name("clicker.toggleRecord")
    static let togglePlay = Notification.Name("clicker.togglePlay")
}

import SwiftUI

@main
struct ClickerApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(state)
                .frame(minWidth: 760, minHeight: 480)
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(state)
        } label: {
            Image(systemName: menuBarIcon)
        }
    }

    private var menuBarIcon: String {
        switch state.phase {
        case .idle: return "cursorarrow.click.2"
        case .countdown: return "timer"
        case .recording: return "record.circle.fill"
        case .playing: return "play.circle.fill"
        }
    }
}

/// 菜单栏内容。录制/回放控制在 Task 10/11 接入引擎后补全动作。
struct MenuBarContent: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            switch state.phase {
            case .idle:
                Button("开始录制") { NotificationCenter.default.post(name: .toggleRecord, object: nil) }
                    .keyboardShortcut("r", modifiers: [.option, .command])
                Button("回放") { NotificationCenter.default.post(name: .togglePlay, object: nil) }
                    .keyboardShortcut("p", modifiers: [.option, .command])
            case .countdown, .recording:
                Button("停止录制") { NotificationCenter.default.post(name: .toggleRecord, object: ["source": "menubar"]) }
            case .playing:
                Button("停止回放") { NotificationCenter.default.post(name: .togglePlay, object: nil) }
            }
            Divider()
            Button("退出 Clicker") { NSApp.terminate(nil) }
        }
    }
}

extension Notification.Name {
    /// 统一的控制通道：菜单栏、快捷键、UI 按钮都发这两个通知，由引擎层监听。
    static let toggleRecord = Notification.Name("clicker.toggleRecord")
    static let togglePlay = Notification.Name("clicker.togglePlay")
}

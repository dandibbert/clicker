import SwiftUI
import ClickerCore

struct MainView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if state.hasPermission {
                NavigationSplitView {
                    ScriptListView()
                } detail: {
                    ScriptDetailView()
                }
            } else {
                PermissionGuideView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshPermission()
        }
        .alert(item: $state.persistenceIssue) { issue in
            Alert(
                title: Text(issueTitle(issue.operation)),
                message: Text(issueMessage(issue)),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private func issueTitle(_ operation: ScriptStoreIssue.Operation) -> String {
        switch operation {
        case .list, .read, .decode:
            "加载脚本失败"
        case .encode, .createDirectory, .temporaryWrite, .replace:
            "保存脚本失败"
        case .delete:
            "删除脚本失败"
        }
    }

    private func issueMessage(_ issue: ScriptStoreIssue) -> String {
        if let fileName = issue.fileName {
            return "\(fileName)\n\(issue.message)"
        }
        return issue.message
    }
}

/// 无权限时的引导界面。
struct PermissionGuideView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.circle")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("需要辅助功能权限")
                .font(.title2.bold())
            Text("Clicker 需要在「系统设置 → 隐私与安全性 → 辅助功能」中获得授权，才能录制和回放鼠标键盘操作。授权后回到本窗口自动生效。")
                .frame(maxWidth: 420)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button("打开系统设置") { Permissions.openAccessibilitySettings() }
                    .buttonStyle(.borderedProminent)
                Button("重新检测") { state.refreshPermission() }
            }
        }
        .padding(40)
    }
}

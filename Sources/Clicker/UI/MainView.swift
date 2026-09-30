import SwiftUI
import ClickerCore

struct MainView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var shortcutEditorScriptID: UUID?

    var body: some View {
        ClickerNeutralControlScope {
            Group {
                if state.hasPermission {
                    NavigationSplitView {
                        ScriptListView()
                            .navigationSplitViewColumnWidth(
                                min: 210,
                                ideal: ClickerVisualTheme.sidebarIdealWidth,
                                max: 250
                            )
                    } detail: {
                        if state.selectedScript == nil {
                            ClickerEmptyStateView(kind: .noSelection)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(ClickerVisualTheme.canvas)
                        } else {
                            ScriptDetailView()
                        }
                    }
                } else {
                    PermissionGuideView()
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    shortcutEditorScriptID = state.selectedScriptID
                } label: {
                    Label(scriptShortcutToolbarTitle, systemImage: "keyboard.badge.ellipsis")
                }
                .disabled(state.selectedScriptID == nil || !state.canEditScripts)
                .help("设置当前脚本的全局回放快捷键")
            }
            ToolbarItem {
                SettingsButton { openSettings() }
                    .disabled(state.phase != .idle)
            }
        }
        .sheet(item: Binding(
            get: { shortcutEditorScriptID.map(ShortcutEditorTarget.init(id:)) },
            set: { shortcutEditorScriptID = $0?.id }
        )) { target in
            ScriptPlaybackShortcutView(scriptID: target.id)
                .environmentObject(state)
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
        .alert(
            "全局快捷键注册失败",
            isPresented: Binding(
                get: { !state.hotKeyRegistrationIssues.isEmpty },
                set: { if !$0 { state.hotKeyRegistrationIssues = [] } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(hotKeyIssueMessage)
        }
        .alert(
            "脚本快捷键注册失败",
            isPresented: Binding(
                get: { !state.scriptHotKeyRegistrationIssues.isEmpty },
                set: { if !$0 { state.scriptHotKeyRegistrationIssues = [] } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(scriptHotKeyIssueMessage)
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

    private struct ShortcutEditorTarget: Identifiable {
        let id: UUID
    }

    private var scriptShortcutToolbarTitle: String {
        guard let shortcut = state.selectedScript?.playbackShortcut else {
            return "快捷回放"
        }
        return "快捷回放 \(shortcut.displayName)"
    }

    private func issueMessage(_ issue: ScriptStoreIssue) -> String {
        if let fileName = issue.fileName {
            return "\(fileName)\n\(issue.message)"
        }
        return issue.message
    }

    private var hotKeyIssueMessage: String {
        let failures = state.hotKeyRegistrationIssues.map { issue in
            "\(issue.shortcut.displayName)：OSStatus \(issue.status)"
        }
        return failures.joined(separator: "\n") + "\n你仍可使用窗口和菜单栏控制。"
    }

    private var scriptHotKeyIssueMessage: String {
        state.scriptHotKeyRegistrationIssues.map { issue in
            "\(issue.scriptName)（\(issue.shortcut.displayName)）：OSStatus \(issue.status)"
        }.joined(separator: "\n")
    }
}

/// 无权限时的引导界面。
struct PermissionGuideView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ClickerEmptyStateView(
            kind: .permissionRequired,
            action: Permissions.openRelevantSettings,
            secondaryAction: state.refreshPermission
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClickerVisualTheme.canvas)
    }
}

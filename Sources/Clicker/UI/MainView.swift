import AppKit
import SwiftUI
import ClickerCore

struct MainView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var shortcutEditorScriptID: UUID?
    @State private var showsPermissionChecklist = false

    var body: some View {
        ClickerNeutralControlScope {
            NavigationSplitView {
                ScriptListView()
                    .navigationSplitViewColumnWidth(
                        min: 210,
                        ideal: ClickerVisualTheme.sidebarIdealWidth,
                        max: 250
                    )
            } detail: {
                if state.selectedScript == nil {
                    ClickerEmptyStateView(
                        kind: state.scripts.isEmpty ? .emptyLibrary : .noSelection,
                        action: { state.createBlankScript() },
                        secondaryAction: { state.toggleRecord(source: .ui) },
                        isActionEnabled: state.canEditScripts,
                        isSecondaryActionEnabled: state.canStartRecording && state.hasPermission
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ClickerVisualTheme.canvas)
                } else {
                    ScriptDetailView()
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if !state.hasPermission {
                    HStack(spacing: ClickerVisualTheme.spacing8) {
                        Label("录制与回放需要权限", systemImage: "hand.raised")
                        Text("脚本仍可编辑")
                            .foregroundStyle(ClickerVisualTheme.secondaryText)
                        Spacer(minLength: 0)
                        Button("权限设置…") { showsPermissionChecklist = true }
                    }
                    .font(.caption)
                    .padding(.horizontal, ClickerVisualTheme.spacing12)
                    .padding(.vertical, ClickerVisualTheme.spacing8)
                    .background(ClickerVisualTheme.controlSurface)
                }
                if let notice = state.recordingNotice {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(notice.title).font(.headline)
                            Text(notice.message).font(.caption)
                        }
                        Spacer()
                        Button("关闭提示") { state.recordingNotice = nil }
                    }
                    .padding(12)
                    .background(ClickerVisualTheme.controlSurface)
                }
                if let notice = state.playbackNotice {
                    HStack {
                        Label(notice, systemImage: "info.circle").font(.caption)
                        Spacer()
                        Button("关闭提示") { state.playbackNotice = nil }
                    }
                    .padding(ClickerVisualTheme.spacing12)
                    .background(ClickerVisualTheme.controlSurface)
                }
                RecordingRecoveryView()
                PlaybackSessionBanner()
                if let interruption = state.selectedScript?.recordingInterruption {
                    Label("部分录制：\(interruption)", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(ClickerVisualTheme.controlSurface)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { LibraryHistoryKeyboardSupport.undo(in: state) } label: {
                    Label("撤销", systemImage: "arrow.uturn.backward")
                }
                .disabled(!state.canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .help("撤销（⌘Z）")
                Button { LibraryHistoryKeyboardSupport.redo(in: state) } label: {
                    Label("重做", systemImage: "arrow.uturn.forward")
                }
                .disabled(!state.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("重做（⇧⌘Z）")
                Button { showsPermissionChecklist = true } label: {
                    Label("系统权限", systemImage: state.hasPermission ? "checkmark.shield" : "exclamationmark.shield")
                }
                .help("查看辅助功能与输入监控权限")
                .popover(isPresented: $showsPermissionChecklist) {
                    PermissionChecklistView().environmentObject(state)
                }
            }
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
        .alert("无法切换到起始应用", isPresented: Binding(
            get: { state.pendingPlaybackStart != nil },
            set: { _ in }
        )) {
            Button("继续自由回放") { state.continuePendingPlayback() }
            Button("取消", role: .cancel) { state.cancelPendingPlayback() }
        } message: {
            Text("未能切换到「\(state.pendingPlaybackStart?.appIdentifier ?? "所选应用")」。可取消并检查应用，或继续自由回放；继续后将向当前前台应用发送操作。")
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

/// Kept for previews; permission help no longer replaces the script library.
struct PermissionGuideView: View {
    var body: some View {
        PermissionChecklistView()
    }
}


/// Keep Command-Z inside the active native text editor; elsewhere it edits the
/// script library. A field with no text undo must not undo an unrelated script.
@MainActor
enum LibraryHistoryKeyboardSupport {
    static func undo(in state: AppState) {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable {
            editor.undoManager?.undo()
        } else {
            state.undo()
        }
    }

    static func redo(in state: AppState) {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isEditable {
            editor.undoManager?.redo()
        } else {
            state.redo()
        }
    }
}

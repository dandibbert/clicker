import ClickerCore
import SwiftUI

/// A true empty library has no navigation destination, so it uses one compact
/// starting page. Search failures remain inside the populated split view.
struct EmptyLibraryWelcomeView: View {
    @EnvironmentObject private var state: AppState
    let onImport: () -> Void

    private var recordingAction: PrimaryActionPresentation {
        PrimaryActionPresentation.pair(
            phase: state.phase,
            hasPlayableScript: false,
            canRecord: state.canStartRecording && state.hasPermission,
            canPlay: false
        )[0]
    }

    private var title: String {
        switch state.phase {
        case .countdown: "即将开始录制"
        case .recording: "正在录制"
        default: "创建第一个脚本"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                welcomeContent.frame(minHeight: geometry.size.height)
            }
        }
        .background(ClickerVisualTheme.canvas)
    }

    private var welcomeContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(ClickerVisualTheme.primaryText)
                    Text(recordingAction.isStop ? "完成操作后，停止并保存为脚本" : "把重复操作交给 Clicker")
                        .font(.callout)
                        .foregroundStyle(ClickerVisualTheme.secondaryText)
                }

                VStack(spacing: 0) {
                    startRow(symbol: "record.circle", title: "录制鼠标和键盘", detail: "操作一次，保存后随时回放") {
                        ClickerProminentButton(role: .recording) {
                            state.toggleRecord(source: .ui)
                        } label: {
                            Text(recordingAction.isStop ? recordingAction.title : "开始录制").frame(width: 100)
                        }
                        .disabled(!recordingAction.isEnabled)
                        .accessibilityIdentifier("empty-library-record")
                        .accessibilityLabel(recordingAction.accessibilityLabel)
                    }
                    Divider()
                    startRow(symbol: "doc.badge.plus", title: "手动编排动作", detail: "逐步添加点击、按键和等待") {
                        ClickerProminentButton(role: .secondary) {
                            state.createBlankScript()
                        } label: {
                            Text("新建空白脚本").frame(width: 100)
                        }
                        .disabled(!state.canEditScripts)
                        .accessibilityIdentifier("empty-library-new")
                        .accessibilityLabel("新建空白脚本")
                    }
                    Divider()
                    startRow(symbol: "square.and.arrow.down", title: "使用已有脚本", detail: "导入 Clicker JSON 文件") {
                        ClickerProminentButton(role: .secondary, action: onImport) {
                            Text("导入脚本…").frame(width: 100)
                        }
                        .disabled(!state.canEditScripts)
                        .accessibilityIdentifier("empty-library-import")
                        .accessibilityLabel("导入脚本")
                    }
                }

                if !state.recentlyDeletedScripts.isEmpty {
                    Menu {
                        ForEach(state.recentlyDeletedScripts) { script in
                            Button("恢复「\(script.name)」") { state.restoreDeletedScript(id: script.id) }
                        }
                    } label: {
                        Label("最近删除（\(state.recentlyDeletedScripts.count)）", systemImage: "trash")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(!state.canEditScripts)
                    .help("恢复最近删除的脚本")
                    .accessibilityLabel("最近删除")
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 32)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
    }

    private func startRow<Action: View>(
        symbol: String, title: String, detail: String, @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(ClickerVisualTheme.secondaryText)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(ClickerVisualTheme.primaryText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ClickerVisualTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action()
        }
        .padding(.vertical, 16)
    }
}

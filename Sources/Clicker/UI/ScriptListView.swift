import SwiftUI
import ClickerCore

struct ScriptListView: View {
    @EnvironmentObject var state: AppState
    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        List(selection: $state.selectedScriptID) {
            ForEach(state.scripts) { script in
                row(script).tag(script.id)
            }
        }
        .navigationTitle("脚本库")
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .overlay {
            if state.scripts.isEmpty {
                ContentUnavailableView("暂无脚本",
                    systemImage: "cursorarrow.click.badge.clock",
                    description: Text("点击右上角「录制」开始"))
            }
        }
        .alert("重命名脚本", isPresented: Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } })) {
            TextField("名称", text: $renameText)
            Button("确定") {
                if let id = renamingID, var s = state.scripts.first(where: { $0.id == id }) {
                    s.name = renameText
                    state.update(s)
                }
                renamingID = nil
            }
            Button("取消", role: .cancel) { renamingID = nil }
        }
    }

    @ViewBuilder
    private func row(_ script: Script) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(script.name).fontWeight(.medium)
            Text("\(script.blocks.count) 个动作")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("重命名") {
                renameText = script.name
                renamingID = script.id
            }
            Button("复制") { state.duplicateScript(id: script.id) }
            Divider()
            Button("删除", role: .destructive) { state.deleteScript(id: script.id) }
        }
    }
}

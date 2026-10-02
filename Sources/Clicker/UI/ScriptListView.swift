import SwiftUI
import ClickerCore

struct ScriptListView: View {
    @EnvironmentObject var state: AppState
    @State private var importCandidate: ScriptImportCandidate?
    @State private var importError: String?

    var body: some View {
        ScriptSidebarView(
            scripts: state.scripts,
            selectedScriptID: $state.selectedScriptID,
            canEditScripts: state.canEditScripts,
            canStartRecording: state.canStartRecording && state.hasPermission,
            onRename: rename,
            onDuplicate: state.duplicateScript,
            onDelete: state.deleteScript,
            onRecord: startRecording,
            onNew: { state.createBlankScript() },
            onImport: chooseImport,
            onExport: export,
            recentlyDeletedScripts: state.recentlyDeletedScripts,
            onRestore: { state.restoreDeletedScript(id: $0) }
        )
        .sheet(item: $importCandidate) { candidate in
            ScriptImportPreview(candidate: candidate)
                .environmentObject(state)
        }
        .alert("导入失败", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "无法读取脚本文件")
        }
    }

    private func rename(id: UUID, to name: String) {
        guard var script = state.scripts.first(where: { $0.id == id }) else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        script.name = name
        state.update(script)
    }

    private func chooseImport() {
        guard state.canEditScripts else { return }
        do {
            importCandidate = try ScriptTransferPanels.chooseImport()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func export(id: UUID) {
        guard let script = state.scripts.first(where: { $0.id == id }) else { return }
        ScriptTransferPanels.export(script, state: state)
    }

    private func startRecording() {
        NotificationCenter.default.post(name: .toggleRecord, object: ["source": "ui"])
    }
}

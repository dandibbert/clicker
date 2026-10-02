import SwiftUI
import ClickerCore

struct ScriptListView: View {
    @EnvironmentObject var state: AppState
    var onImport: () -> Void = {}

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
            onImport: onImport,
            onExport: export,
            recentlyDeletedScripts: state.recentlyDeletedScripts,
            onRestore: { state.restoreDeletedScript(id: $0) }
        )

    }

    private func rename(id: UUID, to name: String) {
        guard var script = state.scripts.first(where: { $0.id == id }) else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        script.name = name
        state.update(script)
    }

    private func export(id: UUID) {
        guard let script = state.scripts.first(where: { $0.id == id }) else { return }
        ScriptTransferPanels.export(script, state: state)
    }

    private func startRecording() {
        NotificationCenter.default.post(name: .toggleRecord, object: ["source": "ui"])
    }
}

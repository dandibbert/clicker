import SwiftUI
import ClickerCore

struct ScriptListView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScriptSidebarView(
            scripts: state.scripts,
            selectedScriptID: $state.selectedScriptID,
            canEditScripts: state.canEditScripts,
            canStartRecording: state.canStartRecording,
            onRename: rename,
            onDuplicate: state.duplicateScript,
            onDelete: state.deleteScript,
            onRecord: startRecording
        )
    }

    private func rename(id: UUID, to name: String) {
        guard var script = state.scripts.first(where: { $0.id == id }) else { return }
        script.name = name
        state.update(script)
    }

    private func startRecording() {
        NotificationCenter.default.post(
            name: .toggleRecord,
            object: ["source": "ui"]
        )
    }
}

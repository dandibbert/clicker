import ClickerCore
import SwiftUI

struct ScriptSidebarView: View {
    let scripts: [Script]
    @Binding var selectedScriptID: UUID?
    let canEditScripts: Bool
    let canStartRecording: Bool
    let onRename: (UUID, String) -> Void
    let onDuplicate: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onRecord: () -> Void

    @State private var renamingID: UUID?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider()
                .overlay(ClickerVisualTheme.separator)
            scriptList
        }
        .background(ClickerVisualTheme.canvas)
        .alert("重命名脚本", isPresented: renameBinding) {
            TextField("名称", text: $renameText)
            Button("确定", action: commitRename)
            Button("取消", role: .cancel) { renamingID = nil }
        }
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing12) {
            HStack(spacing: ClickerVisualTheme.spacing8) {
                CursorTrailMark()
                Text("Clicker")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(ClickerVisualTheme.primaryText)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("脚本库")
                    .font(.headline)
                    .foregroundStyle(ClickerVisualTheme.primaryText)
                Spacer()
                Text(scripts.count, format: .number)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ClickerVisualTheme.secondaryText)
                    .padding(.horizontal, ClickerVisualTheme.spacing8)
                    .padding(.vertical, ClickerVisualTheme.spacing4)
                    .background(ClickerVisualTheme.elevatedSurface, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(ClickerVisualTheme.separator, lineWidth: 1)
                    }
                    .accessibilityLabel("\(scripts.count) 个脚本")
            }
        }
        .padding(.horizontal, ClickerVisualTheme.spacing16)
        .padding(.top, ClickerVisualTheme.spacing16)
        .padding(.bottom, ClickerVisualTheme.spacing12)
    }

    private var scriptList: some View {
        List(selection: $selectedScriptID) {
            ForEach(scripts) { script in
                ScriptSidebarRow(script: script)
                    .tag(script.id)
                    .listRowBackground(
                        selectedScriptID == script.id
                            ? ClickerVisualTheme.selection
                            : Color.clear
                    )
                    .contextMenu { contextMenu(for: script) }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .overlay {
            if scripts.isEmpty {
                ClickerEmptyStateView(kind: .emptyLibrary, action: onRecord)
                    .disabled(!canStartRecording)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for script: Script) -> some View {
        Button("重命名") {
            renameText = script.name
            renamingID = script.id
        }
        .disabled(!canEditScripts)
        Button("复制") { onDuplicate(script.id) }
            .disabled(!canEditScripts)
        Divider()
        Button("删除", role: .destructive) { onDelete(script.id) }
            .disabled(!canEditScripts)
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } }
        )
    }

    private func commitRename() {
        if let renamingID {
            onRename(renamingID, renameText)
        }
        renamingID = nil
    }
}

private struct ScriptSidebarRow: View {
    let presentation: ScriptRowPresentation

    init(script: Script) {
        presentation = ScriptRowPresentation(script: script)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing4) {
            Text(presentation.name)
                .font(.body.weight(.medium))
                .foregroundStyle(ClickerVisualTheme.primaryText)
                .lineLimit(1)
            Text(presentation.metadataText)
                .font(.caption)
                .foregroundStyle(ClickerVisualTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.vertical, ClickerVisualTheme.spacing4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

private struct CursorTrailMark: View {
    var body: some View {
        ZStack {
            Image(systemName: "cursorarrow")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ClickerVisualTheme.primaryText)
                .offset(x: -3, y: 3)

            Circle()
                .fill(ClickerVisualTheme.activeTrail)
                .frame(width: 5, height: 5)
                .offset(x: 5, y: -8)
            Circle()
                .fill(ClickerVisualTheme.activeTrail)
                .frame(width: 4, height: 4)
                .offset(x: 11, y: -3)
            Circle()
                .fill(ClickerVisualTheme.activeTrail)
                .frame(width: 3, height: 3)
                .offset(x: 13, y: 4)
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }
}

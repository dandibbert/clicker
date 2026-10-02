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
    var onNew: () -> Void = {}
    var onImport: () -> Void = {}
    var onExport: (UUID) -> Void = { _ in }
    var recentlyDeletedScripts: [Script] = []
    var onRestore: (UUID) -> Void = { _ in }

    @State private var searchText = ""
    @State private var renamingID: UUID?
    @State private var renameText = ""

    private var filteredScripts: [Script] {
        ScriptLibrarySearch.filter(scripts, query: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider().overlay(ClickerVisualTheme.separator)
            scriptList
            // Empty-library actions live once, in the detail pane. Keep this
            // footer only when the library already has scripts to work with.
            if !scripts.isEmpty {
                Divider().overlay(ClickerVisualTheme.separator)
                libraryActions
            }
        }
        .background(ClickerVisualTheme.sidebarBackground)
        .alert("重命名脚本", isPresented: renameBinding) {
            TextField("名称", text: $renameText)
            Button("确定", action: commitRename)
            Button("取消", role: .cancel) { renamingID = nil }
        }
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing8) {
            HStack(spacing: ClickerVisualTheme.spacing8) {
                Text("脚本库")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ClickerVisualTheme.secondaryText)
                Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "\(scripts.count)" : "\(filteredScripts.count) / \(scripts.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(ClickerVisualTheme.secondaryText)
                    .accessibilityLabel("显示 \(filteredScripts.count) 个，共 \(scripts.count) 个脚本")
                Spacer(minLength: 0)
                libraryMenu
            }
            HStack(spacing: ClickerVisualTheme.spacing4) {
                Image(systemName: "magnifyingglass").accessibilityHidden(true)
                TextField("搜索脚本", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("搜索脚本")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
            .foregroundStyle(ClickerVisualTheme.secondaryText)
            .padding(ClickerVisualTheme.spacing8)
            .background(ClickerVisualTheme.elevatedSurface,
                        in: RoundedRectangle(cornerRadius: ClickerVisualTheme.controlCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ClickerVisualTheme.controlCornerRadius)
                    .stroke(ClickerVisualTheme.separator, lineWidth: 1)
            }
        }
        .padding(ClickerVisualTheme.spacing12)
    }

    private var libraryMenu: some View {
        Menu {
            Button("新建空白脚本", action: createBlank)
                .disabled(!canEditScripts)
            Button("导入脚本…", action: onImport)
                .disabled(!canEditScripts)
            Button("导出所选脚本…") {
                if let selectedScriptID { onExport(selectedScriptID) }
            }
            .disabled(selectedScriptID == nil)
            Divider()
            Menu("最近删除") {
                if recentlyDeletedScripts.isEmpty {
                    Text("没有可恢复的脚本")
                }
                ForEach(recentlyDeletedScripts) { script in
                    Button("恢复「\(script.name)」") { onRestore(script.id) }
                }
            }
            .disabled(!canEditScripts || recentlyDeletedScripts.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("脚本库操作")
        .help("导入、导出和恢复脚本")
    }

    private var scriptList: some View {
        List(selection: $selectedScriptID) {
            ForEach(filteredScripts) { script in
                HStack(spacing: ClickerVisualTheme.spacing4) {
                    ScriptSidebarRow(script: script)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { onDuplicate(script.id) } label: {
                        ScriptSidebarActionIcon(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canEditScripts)
                    .accessibilityLabel("复制脚本「\(script.name)」")
                    .help("复制脚本")
                    Menu { contextMenu(for: script) } label: {
                        ScriptSidebarActionIcon(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .tint(ClickerVisualTheme.primaryText)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel("脚本「\(script.name)」的更多操作")
                    .help("更多操作")
                }
                .tag(script.id)
                .listRowBackground(selectedScriptID == script.id
                                   ? ClickerVisualTheme.selection : Color.clear)
                .contextMenu { contextMenu(for: script) }
            }
        }
        .listStyle(.sidebar)
        .tint(ClickerVisualTheme.selection)
        .scrollContentBackground(.hidden)
        .overlay {
            if !scripts.isEmpty && filteredScripts.isEmpty {
                VStack(spacing: ClickerVisualTheme.spacing8) {
                    Text("没有匹配的脚本")
                        .font(.callout)
                        .foregroundStyle(ClickerVisualTheme.secondaryText)
                    Button("清除搜索") { searchText = "" }
                        .buttonStyle(.borderless)
                        .foregroundStyle(ClickerVisualTheme.primaryText)
                }
                .padding(ClickerVisualTheme.spacing16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var libraryActions: some View {
        HStack(spacing: ClickerVisualTheme.spacing8) {
            ClickerProminentButton(role: .secondary, action: createBlank) {
                Label("新建", systemImage: "plus").frame(maxWidth: .infinity)
            }
                .disabled(!canEditScripts)
                .help("新建空白脚本")
            ClickerProminentButton(role: .secondary, action: onRecord) {
                Label("录制", systemImage: "record.circle").frame(maxWidth: .infinity)
            }
                .disabled(!canStartRecording)
                .help(canStartRecording ? "录制新脚本" : "录制需要系统权限，或等待当前操作结束")
        }
        .padding(.horizontal, ClickerVisualTheme.spacing12)
        .frame(height: 48)
    }

    @ViewBuilder
    private func contextMenu(for script: Script) -> some View {
        Button("重命名…") {
            renameText = script.name
            renamingID = script.id
        }
        .disabled(!canEditScripts)
        Button("复制") { onDuplicate(script.id) }
            .disabled(!canEditScripts)
        Button("导出…") { onExport(script.id) }
        Divider()
        Button("删除", role: .destructive) { onDelete(script.id) }
            .disabled(!canEditScripts)
    }

    private func createBlank() {
        searchText = ""
        onNew()
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renamingID != nil }, set: { if !$0 { renamingID = nil } })
    }

    private func commitRename() {
        if let renamingID { onRename(renamingID, renameText) }
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
                .help(presentation.name)
            Text(presentation.metadataText)
                .font(.caption)
                .foregroundStyle(ClickerVisualTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.vertical, ClickerVisualTheme.spacing4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .help(presentation.name)
    }
}

/// Pin glyph foregrounds inside native sidebar controls; the list selection tint
/// is a surface color and must never become the glyph color in light appearance.
struct ScriptSidebarActionIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .foregroundStyle(ClickerVisualTheme.primaryText)
    }
}

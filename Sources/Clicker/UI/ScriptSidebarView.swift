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
            Divider().overlay(ClickerVisualTheme.separator)
            libraryActions
        }
        .background(ClickerVisualTheme.sidebarBackground)
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
                Spacer()
                libraryMenu
            }
            HStack(alignment: .firstTextBaseline) {
                Text("脚本库")
                    .font(.headline)
                    .foregroundStyle(ClickerVisualTheme.primaryText)
                Spacer()
                Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "\(scripts.count)" : "\(filteredScripts.count) / \(scripts.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(ClickerVisualTheme.secondaryText)
                    .padding(.horizontal, ClickerVisualTheme.spacing8)
                    .padding(.vertical, ClickerVisualTheme.spacing4)
                    .background(ClickerVisualTheme.elevatedSurface, in: Capsule())
                    .overlay { Capsule().stroke(ClickerVisualTheme.separator, lineWidth: 1) }
                    .accessibilityLabel("显示 \(filteredScripts.count) 个，共 \(scripts.count) 个脚本")
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
        .padding(.horizontal, ClickerVisualTheme.spacing16)
        .padding(.top, ClickerVisualTheme.spacing16)
        .padding(.bottom, ClickerVisualTheme.spacing12)
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
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canEditScripts)
                    .accessibilityLabel("复制脚本「\(script.name)」")
                    .help("复制脚本")
                    Menu { contextMenu(for: script) } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
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
            if scripts.isEmpty {
                ClickerEmptyStateView(
                    kind: .emptyLibrary,
                    action: createBlank,
                    secondaryAction: onRecord,
                    isActionEnabled: canEditScripts,
                    isSecondaryActionEnabled: canStartRecording
                )
            } else if filteredScripts.isEmpty {
                ClickerEmptyStateView(kind: .noSearchResults, action: { searchText = "" })
            }
        }
    }

    private var libraryActions: some View {
        HStack(spacing: ClickerVisualTheme.spacing8) {
            Button(action: createBlank) { Label("新建", systemImage: "plus") }
                .disabled(!canEditScripts)
                .help("新建空白脚本")
            Spacer(minLength: 0)
            Button(action: onRecord) { Label("录制", systemImage: "record.circle") }
                .disabled(!canStartRecording)
                .help(canStartRecording ? "录制新脚本" : "录制需要系统权限，或等待当前操作结束")
        }
        .padding(ClickerVisualTheme.spacing12)
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

private struct CursorTrailMark: View {
    var body: some View {
        ZStack {
            Image(systemName: "cursorarrow")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ClickerVisualTheme.primaryText)
                .offset(x: -3, y: 3)
            Circle().fill(ClickerVisualTheme.activeTrail)
                .frame(width: 5, height: 5).offset(x: 5, y: -8)
            Circle().fill(ClickerVisualTheme.activeTrail)
                .frame(width: 4, height: 4).offset(x: 11, y: -3)
            Circle().fill(ClickerVisualTheme.activeTrail)
                .frame(width: 3, height: 3).offset(x: 13, y: 4)
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }
}

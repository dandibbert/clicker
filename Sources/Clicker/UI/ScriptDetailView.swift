import SwiftUI
import ClickerCore

struct ScriptDetailView: View {
    @EnvironmentObject var state: AppState
    @State private var editorTarget: EditTarget?
    @State private var selectedBlockIDs: Set<UUID> = []

    var body: some View {
        Group {
            if let script = state.selectedScript { content(script) }
            else { ContentUnavailableView("未选择脚本", systemImage: "sidebar.left") }
        }
        .sheet(item: $editorTarget) { target in
            BlockEditorView(draft: target.draft, isSaveEnabled: state.canEditScripts,
                saveErrorMessage: { state.persistenceIssue?.message }) { updated in
                guard state.canEditScripts,
                      var current = state.scripts.first(where: { $0.id == target.scriptID }) else { return false }
                if target.draft.original != nil {
                    guard let index = current.blocks.firstIndex(where: { $0.id == target.draft.id }) else { return false }
                    current.blocks = TimelineMutation.replacing(at: index, with: updated, in: current.blocks)
                } else {
                    current.blocks = TimelineMutation.inserting(updated, at: current.blocks.count, in: current.blocks)
                }
                return state.update(current)
            }
        }
        .onChange(of: state.selectedScriptID) { _, _ in selectedBlockIDs.removeAll() }
        .onChange(of: state.selectedScript?.blocks.map(\.id)) { _, ids in
            selectedBlockIDs.formIntersection(Set(ids ?? []))
        }
    }

    private struct EditTarget: Identifiable {
        let id = UUID()
        let scriptID: UUID
        let draft: ActionEditorDraft
    }

    private func content(_ script: Script) -> some View {
        VStack(spacing: 0) {
            ScriptHeaderView(script: script)
            Divider()
            blockList(script)
        }
    }

    private func edit(_ block: ActionBlock, in script: Script) {
        guard state.canEditScripts else { return }
        editorTarget = EditTarget(scriptID: script.id, draft: ActionEditorDraft(block: block))
    }

    private func selection(in script: Script, including block: ActionBlock) -> Set<UUID> {
        if selectedBlockIDs.contains(block.id) { return selectedBlockIDs }
        return [block.id]
    }

    @ViewBuilder private func blockList(_ script: Script) -> some View {
        let activeID: UUID? = {
            if state.activePlaybackScript?.id == script.id,
               case .playing(_, let id) = state.phase { return id }
            return nil
        }()
        ZStack {
            List(selection: $selectedBlockIDs) {
                ForEach(Array(script.blocks.enumerated()), id: \.element.id) { index, block in
                    ActionCardView(block: block, isActive: block.id == activeID,
                        isEditEnabled: state.canEditScripts,
                        onEdit: { edit(block, in: script) },
                        onCopy: { state.copyActions(scriptID: script.id, blockIDs: selection(in: script, including: block)) })
                        .tag(block.id)
                        .overlay(alignment: .bottom) {
                            if index < script.blocks.count - 1 {
                                Rectangle().fill(ClickerVisualTheme.separator).frame(height: 1)
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22))
                        .contentShape(Rectangle())
                        .moveDisabled(!state.canEditScripts)
                        .deleteDisabled(!state.canEditScripts)
                        .contextMenu {
                            Button("编辑…") { edit(block, in: script) }.disabled(!state.canEditScripts)
                            Button("复制动作") {
                                state.copyActions(scriptID: script.id, blockIDs: selection(in: script, including: block))
                            }
                            Button("在此后粘贴动作") { _ = state.pasteActions(into: script.id, at: index + 1) }
                                .disabled(!state.canEditScripts || !state.hasCopiedActions)
                            Button("试运行所选动作一次") {
                                state.trialActions(scriptID: script.id, blockIDs: selection(in: script, including: block))
                            }
                            .disabled(!state.canEditScripts || !state.hasPermission)
                            Button("创建副本") {
                                mutate(script.id) { blocks in TimelineMutation.duplicating(at: index, in: blocks) }
                            }
                            .disabled(!state.canEditScripts)
                            Divider()
                            Button("删除", role: .destructive) {
                                let ids = selection(in: script, including: block)
                                mutate(script.id) { blocks in
                                    TimelineMutation.deleting(atOffsets: IndexSet(blocks.indices.filter { ids.contains(blocks[$0].id) }), in: blocks)
                                }
                            }
                            .disabled(!state.canEditScripts)
                        }
                }
                .onMove { from, to in
                    mutate(script.id) { TimelineMutation.moving(fromOffsets: from, toOffset: to, in: $0) }
                }
                .onDelete { offsets in
                    mutate(script.id) { TimelineMutation.deleting(atOffsets: offsets, in: $0) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .help("单击选择动作，Shift 单击选择连续范围，Command 单击选择多个动作")

            if script.blocks.isEmpty {
                ClickerEmptyStateView(kind: .emptyScript, action: startRecording,
                    isActionEnabled: state.canStartRecording && state.hasPermission)
            }
        }
        .background(ClickerVisualTheme.canvas)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: ClickerVisualTheme.spacing12) {
                AddActionMenu(isEnabled: state.canEditScripts) { kind in
                    editorTarget = EditTarget(scriptID: script.id, draft: ActionEditorDraft(kind: kind))
                }
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Rectangle())
                .fixedSize()
                Button { paste(into: script) } label: { Image(systemName: "doc.on.clipboard") }
                    .buttonStyle(.borderless)
                    .disabled(!state.canEditScripts || !state.hasCopiedActions)
                    .help("粘贴动作到所选动作之后；未选择时添加到末尾")
                    .accessibilityLabel("粘贴动作")
                Spacer(minLength: 0)
                if !selectedBlockIDs.isEmpty {
                    Text("已选 \(selectedBlockIDs.count)")
                        .font(.caption).foregroundStyle(ClickerVisualTheme.secondaryText)
                    Button {
                        state.trialActions(scriptID: script.id, blockIDs: selectedBlockIDs)
                    } label: { Label("试运行一次", systemImage: "play") }
                    .buttonStyle(.borderless)
                    .disabled(!state.canEditScripts || !state.hasPermission)
                    .help("仅回放所选动作一次，保留相对时间；不会修改脚本的重复设置")
                }
            }
            .foregroundStyle(ClickerVisualTheme.primaryText)
            .padding(.horizontal, 22)
            .frame(height: ClickerVisualTheme.spacing24 * 2)
            .background(ClickerVisualTheme.elevatedSurface)
        }
    }

    private func mutate(_ scriptID: UUID, blocks mutation: ([ActionBlock]) -> [ActionBlock]) {
        guard state.canEditScripts, var current = state.scripts.first(where: { $0.id == scriptID }) else { return }
        current.blocks = mutation(current.blocks)
        state.update(current)
    }

    private func paste(into script: Script) {
        let insertionIndex = script.blocks.lastIndex(where: { selectedBlockIDs.contains($0.id) }).map { $0 + 1 }
            ?? script.blocks.count
        _ = state.pasteActions(into: script.id, at: insertionIndex)
    }

    private func startRecording() {
        NotificationCenter.default.post(name: .toggleRecord, object: ["source": "ui"])
    }
}

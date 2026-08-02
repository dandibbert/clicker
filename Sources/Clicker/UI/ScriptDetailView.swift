import SwiftUI
import ClickerCore

struct ScriptDetailView: View {
    @EnvironmentObject var state: AppState
    @State private var editingBlockID: UUID?

    var body: some View {
        if let script = state.selectedScript {
            content(script)
        } else {
            ContentUnavailableView("未选择脚本", systemImage: "sidebar.left")
        }
    }

    @ViewBuilder
    private func content(_ script: Script) -> some View {
        VStack(spacing: 0) {
            ScriptHeaderView(script: script)
            Divider()
            blockList(script)
        }
        .sheet(item: Binding(
            get: { editingBlockID.map(EditTarget.init(id:)) },
            set: { editingBlockID = $0?.id })) { target in
            if let block = script.blocks.first(where: { $0.id == target.id }) {
                BlockEditorView(block: block) { updated in
                    guard state.canEditScripts,
                          var current = state.scripts.first(where: { $0.id == script.id }),
                          let index = current.blocks.firstIndex(where: { $0.id == target.id }) else {
                        return
                    }
                    current.blocks[index] = updated
                    state.update(current)
                }
            }
        }
        .onChange(of: state.canEditScripts) { _, canEdit in
            if !canEdit { editingBlockID = nil }
        }
    }

    private struct EditTarget: Identifiable {
        let id: UUID
    }

    // MARK: 块列表

    @ViewBuilder
    private func blockList(_ script: Script) -> some View {
        let activeID: UUID? = {
            if case .playing(_, let id) = state.phase { return id }
            return nil
        }()
        ZStack {
            List {
                ForEach(Array(script.blocks.enumerated()), id: \.element.id) { index, block in
                    ActionCardView(
                        block: block,
                        isActive: block.id == activeID,
                        isEditEnabled: state.canEditScripts,
                        onEdit: { editingBlockID = block.id }
                    )
                        .overlay(alignment: .bottom) {
                            if index < script.blocks.count - 1 {
                                Rectangle()
                                    .fill(ClickerVisualTheme.separator)
                                    .frame(height: 1)
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22))
                        .contentShape(Rectangle())
                        .moveDisabled(!state.canEditScripts)
                        .deleteDisabled(!state.canEditScripts)
                        .contextMenu {
                            Button("编辑…") { editingBlockID = block.id }
                                .disabled(!state.canEditScripts)
                            Button("复制") {
                                var s = script
                                s.blocks = TimelineMutation.duplicating(
                                    at: index,
                                    in: s.blocks
                                )
                                state.update(s)
                            }
                            .disabled(!state.canEditScripts)
                            Divider()
                            Button("删除", role: .destructive) {
                                var s = script
                                s.blocks = TimelineMutation.deleting(
                                    at: index,
                                    in: s.blocks
                                )
                                state.update(s)
                            }
                            .disabled(!state.canEditScripts)
                        }
                }
                .onMove { from, to in
                    var s = script
                    s.blocks = TimelineMutation.moving(
                        fromOffsets: from,
                        toOffset: to,
                        in: s.blocks
                    )
                    state.update(s)
                }
                .onDelete { offsets in
                    var s = script
                    s.blocks = TimelineMutation.deleting(
                        atOffsets: offsets,
                        in: s.blocks
                    )
                    state.update(s)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            if script.blocks.isEmpty {
                ClickerEmptyStateView(kind: .emptyScript, action: startRecording)
                    .disabled(!state.canStartRecording)
            }
        }
        .background(ClickerVisualTheme.canvas)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Menu {
                    Button("点击") { append(.click(ClickBlock(x: 500, y: 400, button: .left, clickCount: 1)), to: script) }
                    Button("输入文本") { append(.typeText(TypeTextBlock(text: "文本", keystrokes: [])), to: script) }
                    Button("快捷键") { append(.shortcut(ShortcutBlock(keyCode: 8, flags: KeyCodeMap.maskCommand)), to: script) }
                    Button("等待") { append(.wait(WaitBlock(duration: 1.0)), to: script) }
                    Button("移动鼠标") { append(.move(MoveBlock(duration: 0.5, points: [
                        TrackPoint(t: 0, x: 400, y: 300), TrackPoint(t: 0.5, x: 600, y: 400)])), to: script) }
                } label: {
                    Label("添加动作", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!state.canEditScripts)
                Spacer()
            }
            .padding(.horizontal, 22)
            .frame(height: ClickerVisualTheme.spacing24 * 2)
            .background(ClickerVisualTheme.elevatedSurface)
        }
    }

    private func startRecording() {
        NotificationCenter.default.post(
            name: .toggleRecord,
            object: ["source": "ui"]
        )
    }

    private func append(_ block: ActionBlock, to script: Script) {
        guard state.canEditScripts else { return }
        var s = script
        s.blocks = TimelineMutation.inserting(
            block,
            at: s.blocks.count,
            in: s.blocks
        )
        state.update(s)
    }
}

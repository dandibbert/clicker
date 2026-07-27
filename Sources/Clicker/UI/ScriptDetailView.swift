import SwiftUI
import ClickerCore

struct ScriptDetailView: View {
    @EnvironmentObject var state: AppState
    @State private var editingBlockIndex: Int?

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
            controlBar(script)
            Divider()
            blockList(script)
        }
        .toolbar {
            ToolbarItemGroup {
                recordButton
                playButton(script)
            }
        }
        .sheet(item: Binding(
            get: { editingBlockIndex.map { EditTarget(index: $0) } },
            set: { editingBlockIndex = $0?.index })) { target in
            if script.blocks.indices.contains(target.index) {
                BlockEditorView(block: script.blocks[target.index]) { updated in
                    var s = script
                    s.blocks[target.index] = updated
                    state.update(s)
                }
            }
        }
    }

    private struct EditTarget: Identifiable {
        let index: Int
        var id: Int { index }
    }

    // MARK: 控制栏：重复次数 + 间隔

    @ViewBuilder
    private func controlBar(_ script: Script) -> some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Text("重复")
                TextField("次数", value: Binding(
                    get: { script.repeatCount },
                    set: { var s = script; s.repeatCount = max(1, $0); state.update(s) }),
                    format: .number)
                    .frame(width: 50)
                    .disabled(script.repeatForever)
                Text("次")
                Toggle("无限", isOn: Binding(
                    get: { script.repeatForever },
                    set: { var s = script; s.repeatForever = $0; state.update(s) }))
                    .toggleStyle(.checkbox)
            }
            HStack(spacing: 6) {
                Text("间隔")
                TextField("秒", value: Binding(
                    get: { script.repeatInterval },
                    set: { var s = script; s.repeatInterval = max(0, $0); state.update(s) }),
                    format: .number)
                    .frame(width: 50)
                Text("秒")
            }
            Spacer()
            if case .playing(let iteration, _) = state.phase {
                Label(script.repeatForever ? "第 \(iteration) 轮" : "第 \(iteration)/\(script.repeatCount) 轮",
                      systemImage: "play.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 块列表

    @ViewBuilder
    private func blockList(_ script: Script) -> some View {
        let activeID: UUID? = {
            if case .playing(_, let id) = state.phase { return id }
            return nil
        }()
        List {
            ForEach(Array(script.blocks.enumerated()), id: \.element.id) { index, block in
                BlockRowView(block: block, isActive: block.id == activeID)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editingBlockIndex = index }
                    .contextMenu {
                        Button("编辑…") { editingBlockIndex = index }
                        Button("复制") {
                            var s = script
                            s.blocks = TimelineMutation.duplicating(
                                at: index,
                                in: s.blocks
                            )
                            state.update(s)
                        }
                        Divider()
                        Button("删除", role: .destructive) {
                            var s = script
                            s.blocks = TimelineMutation.deleting(
                                at: index,
                                in: s.blocks
                            )
                            state.update(s)
                        }
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
                Spacer()
            }
            .padding(10)
            .background(.bar)
        }
    }

    private func append(_ block: ActionBlock, to script: Script) {
        var s = script
        s.blocks = TimelineMutation.inserting(
            block,
            at: s.blocks.count,
            in: s.blocks
        )
        state.update(s)
    }

    // MARK: 工具栏按钮

    @ViewBuilder
    private var recordButton: some View {
        switch state.phase {
        case .recording, .countdown:
            Button {
                NotificationCenter.default.post(name: .toggleRecord, object: ["source": "ui"])
            } label: { Label("停止录制", systemImage: "stop.circle.fill") }
        default:
            Button {
                NotificationCenter.default.post(name: .toggleRecord, object: ["source": "ui"])
            } label: { Label("录制", systemImage: "record.circle") }
                .disabled(state.phase != .idle)
        }
    }

    @ViewBuilder
    private func playButton(_ script: Script) -> some View {
        if case .playing = state.phase {
            Button {
                NotificationCenter.default.post(name: .togglePlay, object: nil)
            } label: { Label("停止", systemImage: "stop.fill") }
        } else {
            Button {
                NotificationCenter.default.post(name: .togglePlay, object: nil)
            } label: { Label("回放", systemImage: "play.fill") }
                .disabled(state.phase != .idle || script.blocks.isEmpty)
        }
    }
}

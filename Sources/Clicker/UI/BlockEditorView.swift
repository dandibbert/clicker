import SwiftUI
import ClickerCore

/// 块参数编辑 sheet。按块类型显示对应表单，保存时回调 onSave。
struct BlockEditorView: View {
    let block: ActionBlock
    let onSave: (ActionBlock) -> Void
    @Environment(\.dismiss) private var dismiss

    // 通用编辑字段（按块类型选用）
    @State private var x: Double = 0
    @State private var y: Double = 0
    @State private var endX: Double = 0
    @State private var endY: Double = 0
    @State private var duration: Double = 0
    @State private var text: String = ""
    @State private var button: MouseButton = .left
    @State private var clickCount: Int = 1
    @State private var keyCode: UInt16 = 0
    @State private var useCommand = false
    @State private var useOption = false
    @State private var useControl = false
    @State private var useShift = false

    var body: some View {
        VStack(spacing: 0) {
            Form { formFields }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(ClickerVisualTheme.windowBackground)
            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(ClickerVisualTheme.focusRing)
                    .foregroundStyle(ClickerVisualTheme.primaryText)
                ClickerProminentButton(role: .neutral, action: save) {
                    Text("保存")
                }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(ClickerVisualTheme.spacing12)
            .background(ClickerVisualTheme.windowBackground)
        }
        .frame(width: 380)
        .background(ClickerVisualTheme.windowBackground)
        .onAppear(perform: load)
    }

    @ViewBuilder
    private var formFields: some View {
        switch block {
        case .click:
            Section("点击") {
                TextField("X 坐标", value: $x, format: .number)
                TextField("Y 坐标", value: $y, format: .number)
                Picker("按键", selection: $button) {
                    Text("左键").tag(MouseButton.left)
                    Text("右键").tag(MouseButton.right)
                }
                Stepper("点击次数：\(clickCount)", value: $clickCount, in: 1...3)
            }
        case .move:
            Section("移动鼠标") {
                TextField("终点 X", value: $endX, format: .number)
                TextField("终点 Y", value: $endY, format: .number)
                TextField("时长（秒）", value: $duration, format: .number)
                Text("修改终点后，轨迹将整体平移至新终点")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .drag:
            Section("拖拽") {
                TextField("起点 X", value: $x, format: .number)
                TextField("起点 Y", value: $y, format: .number)
                TextField("终点 X", value: $endX, format: .number)
                TextField("终点 Y", value: $endY, format: .number)
                TextField("时长（秒）", value: $duration, format: .number)
            }
        case .scroll:
            Section("滚动") {
                TextField("垂直滚动量（负为向下）", value: $y, format: .number)
            }
        case .typeText:
            Section("输入文本") {
                TextField("文本", text: $text, axis: .vertical)
                    .lineLimit(3...6)
            }
        case .shortcut:
            Section("快捷键") {
                Toggle("⌘ Command", isOn: $useCommand)
                Toggle("⌥ Option", isOn: $useOption)
                Toggle("⌃ Control", isOn: $useControl)
                Toggle("⇧ Shift", isOn: $useShift)
                Picker("主键", selection: $keyCode) {
                    ForEach(commonKeys, id: \.code) { k in
                        Text(k.name).tag(k.code)
                    }
                }
            }
        case .wait:
            Section("等待") {
                TextField("时长（秒）", value: $duration, format: .number)
            }
        }
    }

    private var commonKeys: [(code: UInt16, name: String)] {
        let letters: [(UInt16, String)] = [
            (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"), (5, "G"),
            (4, "H"), (34, "I"), (38, "J"), (40, "K"), (37, "L"), (46, "M"), (45, "N"),
            (31, "O"), (35, "P"), (12, "Q"), (15, "R"), (1, "S"), (17, "T"), (32, "U"),
            (9, "V"), (13, "W"), (7, "X"), (16, "Y"), (6, "Z"),
        ]
        let others: [(UInt16, String)] = [
            (36, "Return"), (49, "Space"), (48, "Tab"), (53, "Esc"), (51, "Delete"),
            (123, "←"), (124, "→"), (125, "↓"), (126, "↑"),
        ]
        return (letters + others).map { (code: $0.0, name: $0.1) }
    }

    private func load() {
        switch block {
        case .click(let b):
            x = b.x; y = b.y; button = b.button; clickCount = b.clickCount
        case .move(let b):
            endX = b.points.last?.x ?? 0; endY = b.points.last?.y ?? 0; duration = b.duration
        case .drag(let b):
            x = b.points.first?.x ?? 0; y = b.points.first?.y ?? 0
            endX = b.points.last?.x ?? 0; endY = b.points.last?.y ?? 0
            duration = b.duration
        case .scroll(let b):
            y = b.steps.reduce(0.0) { $0 + $1.dy }
        case .typeText(let b):
            text = b.text
        case .shortcut(let b):
            keyCode = b.keyCode
            useCommand = b.flags & KeyCodeMap.maskCommand != 0
            useOption = b.flags & KeyCodeMap.maskOption != 0
            useControl = b.flags & KeyCodeMap.maskControl != 0
            useShift = b.flags & KeyCodeMap.maskShift != 0
        case .wait(let b):
            duration = b.duration
        }
    }

    private func save() {
        var shortcutFlags: UInt64 = 0
        if useCommand { shortcutFlags |= KeyCodeMap.maskCommand }
        if useOption { shortcutFlags |= KeyCodeMap.maskOption }
        if useControl { shortcutFlags |= KeyCodeMap.maskControl }
        if useShift { shortcutFlags |= KeyCodeMap.maskShift }
        let values = ActionBlockEditValues(
            x: x,
            y: y,
            endX: endX,
            endY: endY,
            duration: duration,
            text: text,
            button: button,
            clickCount: clickCount,
            keyCode: keyCode,
            shortcutFlags: shortcutFlags,
            scrollDeltaY: y
        )
        let updated = ActionBlockEditor.edit(block, values: values)
        onSave(updated)
        dismiss()
    }
}

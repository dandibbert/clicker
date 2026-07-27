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
            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 380)
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

    private func rescaledPoints(
        _ points: [TrackPoint],
        fromDuration oldDuration: Double,
        toDuration newDuration: Double
    ) -> [TrackPoint] {
        let clampedDuration = max(0, newDuration)
        if oldDuration > 0 {
            let ratio = clampedDuration / oldDuration
            return points.map { TrackPoint(t: $0.t * ratio, x: $0.x, y: $0.y) }
        }
        if points.count > 1, clampedDuration > 0 {
            let lastIndex = Double(points.count - 1)
            return points.enumerated().map { index, point in
                TrackPoint(
                    t: clampedDuration * Double(index) / lastIndex,
                    x: point.x,
                    y: point.y
                )
            }
        }
        return points.map { TrackPoint(t: 0, x: $0.x, y: $0.y) }
    }

    private func save() {
        var updated = block
        switch block {
        case .click(var b):
            b.x = x; b.y = y; b.button = button; b.clickCount = clickCount
            updated = .click(b)
        case .move(var b):
            if let last = b.points.last {
                let dx = endX - last.x, dy = endY - last.y
                b.points = b.points.map { TrackPoint(t: $0.t, x: $0.x + dx, y: $0.y + dy) }
            }
            let newDuration = max(0, duration)
            if newDuration != b.duration {
                b.points = rescaledPoints(
                    b.points,
                    fromDuration: b.duration,
                    toDuration: newDuration
                )
            }
            b.duration = newDuration
            updated = .move(b)
        case .drag(var b):
            if let first = b.points.first, let last = b.points.last,
               b.points.count >= 2 {
                let oldSpanX = last.x - first.x, oldSpanY = last.y - first.y
                let newSpanX = endX - x, newSpanY = endY - y
                let timeSpan = last.t - first.t
                let pointCount = b.points.count
                b.points = b.points.enumerated().map { index, p in
                    let fallbackProgress: Double
                    if index == 0 {
                        fallbackProgress = 0
                    } else if index == pointCount - 1 {
                        fallbackProgress = 1
                    } else if timeSpan > 0 {
                        fallbackProgress = (p.t - first.t) / timeSpan
                    } else {
                        fallbackProgress = Double(index) / Double(pointCount - 1)
                    }
                    let fx = oldSpanX == 0 ? fallbackProgress : (p.x - first.x) / oldSpanX
                    let fy = oldSpanY == 0 ? fallbackProgress : (p.y - first.y) / oldSpanY
                    return TrackPoint(t: p.t, x: x + fx * newSpanX, y: y + fy * newSpanY)
                }
            }
            let newDuration = max(0, duration)
            if newDuration != b.duration {
                b.points = rescaledPoints(
                    b.points,
                    fromDuration: b.duration,
                    toDuration: newDuration
                )
            }
            b.duration = newDuration
            updated = .drag(b)
        case .scroll(var b):
            b.steps = [ScrollStep(t: 0, dx: 0, dy: y)]
            b.duration = 0
            updated = .scroll(b)
        case .typeText(var b):
            b.text = text
            updated = .typeText(b)
        case .shortcut(var b):
            b.keyCode = keyCode
            var flags: UInt64 = 0
            if useCommand { flags |= KeyCodeMap.maskCommand }
            if useOption { flags |= KeyCodeMap.maskOption }
            if useControl { flags |= KeyCodeMap.maskControl }
            if useShift { flags |= KeyCodeMap.maskShift }
            b.flags = flags
            updated = .shortcut(b)
        case .wait(var b):
            b.duration = max(0, duration)
            updated = .wait(b)
        }
        onSave(updated)
        dismiss()
    }
}

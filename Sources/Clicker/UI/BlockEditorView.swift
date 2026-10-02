import SwiftUI
import ClickerCore

/// Text-backed numeric fields retain invalid input instead of silently saving the
/// last valid value. A new draft has no implicit pointer target or shortcut.
struct ActionEditorDraft: Equatable {
    let original: ActionBlock?
    let kind: AddActionKind
    let id: UUID
    var x = ""
    var y = ""
    var endX = ""
    var endY = ""
    var duration = "0.5"
    var text = ""
    var scrollDeltaY = ""
    var button: MouseButton = .left
    var clickCount = 1
    var keyCode: UInt16?
    var shortcutFlags: UInt64 = 0

    init(kind: AddActionKind) {
        self.kind = kind
        original = nil
        id = UUID()
        if kind == .wait { duration = "1" }
    }

    init(block: ActionBlock) {
        original = block
        kind = AddActionKind(block: block)
        id = block.id
        duration = String(block.duration)
        switch block {
        case .click(let b):
            x = String(b.x); y = String(b.y); button = b.button; clickCount = b.clickCount
        case .move(let b):
            endX = b.points.last.map { String($0.x) } ?? ""
            endY = b.points.last.map { String($0.y) } ?? ""
        case .drag(let b):
            x = b.points.first.map { String($0.x) } ?? ""
            y = b.points.first.map { String($0.y) } ?? ""
            endX = b.points.last.map { String($0.x) } ?? ""
            endY = b.points.last.map { String($0.y) } ?? ""
            button = b.button
        case .scroll(let b):
            x = String(b.x); y = String(b.y)
            scrollDeltaY = String(b.steps.reduce(0) { $0 + $1.dy })
        case .typeText(let b): text = b.text
        case .shortcut(let b): keyCode = b.keyCode; shortcutFlags = b.flags
        case .wait: break
        }
    }

    static func number(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Double(trimmed), number.isFinite { return number }
        let scanner = Scanner(string: trimmed)
        scanner.locale = Locale.current
        guard let number = scanner.scanDouble(), scanner.isAtEnd, number.isFinite else { return nil }
        return number
    }

    func build() throws -> ActionBlock {
        func number(_ text: String, _ label: String) throws -> Double {
            guard let value = Self.number(text) else { throw DraftError.invalid("请输入有效的\(label)") }
            return value
        }
        func seconds() throws -> Double {
            let value = try number(duration, "时长")
            guard value >= 0, value < Double(Int64.max) / 1_000_000_000 - 1 else {
                throw DraftError.invalid("时长必须为零或正数，且不能超出回放范围")
            }
            return value
        }
        // Keeping an untouched recorded block also preserves its raw input fidelity.
        if let original, self == ActionEditorDraft(block: original) { return original }
        var values = ActionBlockEditValues(x: 0, y: 0, endX: 0, endY: 0, duration: 0,
            text: text, button: button, clickCount: clickCount, keyCode: keyCode ?? 0,
            shortcutFlags: shortcutFlags, scrollDeltaY: 0)
        switch kind {
        case .click, .drag, .scroll:
            values.x = try number(x, "X 坐标")
            values.y = try number(y, "Y 坐标")
        case .move where original == nil:
            values.x = try number(x, "起点 X 坐标")
            values.y = try number(y, "起点 Y 坐标")
        default: break
        }
        switch kind {
        case .move, .drag:
            values.endX = try number(endX, "终点 X 坐标")
            values.endY = try number(endY, "终点 Y 坐标")
            values.duration = try seconds()
        case .wait: values.duration = try seconds()
        case .scroll: values.scrollDeltaY = try number(scrollDeltaY, "滚动量")
        case .shortcut:
            guard keyCode != nil else { throw DraftError.invalid("请选择快捷键的主键") }
        case .typeText:
            guard !text.isEmpty else { throw DraftError.invalid("请输入文本") }
        case .click:
            guard (1...3).contains(clickCount) else { throw DraftError.invalid("点击次数必须为 1 至 3") }
        }
        if let original {
            var updated = ActionBlockEditor.edit(original, values: values)
            if case .drag(var payload) = updated {
                payload.button = button
                updated = .drag(payload)
            }
            if case .scroll(var payload) = updated {
                let dx = values.x - payload.x, dy = values.y - payload.y
                let oldX = payload.x, oldY = payload.y
                payload.steps = payload.steps.map { step in
                    var step = step
                    step.x = (step.x ?? oldX) + dx
                    step.y = (step.y ?? oldY) + dy
                    return step
                }
                payload.x = values.x; payload.y = values.y
                updated = .scroll(payload)
            }
            return updated
        }
        switch kind {
        case .click:
            return .click(ClickBlock(id: id, x: values.x, y: values.y, button: button, clickCount: clickCount))
        case .move:
            return .move(MoveBlock(id: id, duration: values.duration, points: [
                TrackPoint(t: 0, x: values.x, y: values.y),
                TrackPoint(t: values.duration, x: values.endX, y: values.endY),
            ]))
        case .drag:
            return .drag(DragBlock(id: id, button: button, duration: values.duration, points: [
                TrackPoint(t: 0, x: values.x, y: values.y, ordinal: 0),
                TrackPoint(t: values.duration, x: values.endX, y: values.endY, ordinal: 1),
            ]))
        case .scroll:
            return .scroll(ScrollBlock(id: id, x: values.x, y: values.y, duration: 0,
                steps: [ScrollStep(t: 0, x: values.x, y: values.y, dx: 0, dy: values.scrollDeltaY)]))
        case .typeText: return .typeText(TypeTextBlock(id: id, text: text, keystrokes: []))
        case .shortcut: return .shortcut(ShortcutBlock(id: id, keyCode: values.keyCode, flags: shortcutFlags))
        case .wait: return .wait(WaitBlock(id: id, duration: values.duration))
        }
    }

    enum DraftError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let message): message }
        }
    }
}

/// Dismissal is a result of a confirmed save, never a side effect of trying one.
struct ActionEditorSession {
    var draft: ActionEditorDraft
    private let initial: ActionEditorDraft
    private(set) var saveError: String?
    private(set) var didSave = false

    init(draft: ActionEditorDraft) { self.draft = draft; initial = draft }
    var isDirty: Bool { draft != initial }

    mutating func save(using persist: (ActionBlock) -> Bool, errorMessage: () -> String?) -> Bool {
        guard !didSave else { return false }
        do {
            let candidate = try draft.build()
            guard persist(candidate) else {
                saveError = errorMessage() ?? "保存失败，输入已保留。请重试。"
                return false
            }
            saveError = nil
            didSave = true
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }
}

struct BlockEditorView: View {
    let onSave: (ActionBlock) -> Bool
    let saveErrorMessage: () -> String?
    let isSaveEnabled: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var session: ActionEditorSession
    @State private var confirmsDiscard = false
    @StateObject private var coordinatePicker = CoordinatePickerController()

    init(block: ActionBlock, isSaveEnabled: Bool = true,
         saveErrorMessage: @escaping () -> String? = { nil },
         onSave: @escaping (ActionBlock) -> Bool) {
        self.init(draft: ActionEditorDraft(block: block), isSaveEnabled: isSaveEnabled,
                  saveErrorMessage: saveErrorMessage, onSave: onSave)
    }

    init(draft: ActionEditorDraft, isSaveEnabled: Bool = true,
         saveErrorMessage: @escaping () -> String? = { nil },
         onSave: @escaping (ActionBlock) -> Bool) {
        self.onSave = onSave
        self.saveErrorMessage = saveErrorMessage
        self.isSaveEnabled = isSaveEnabled
        _session = State(initialValue: ActionEditorSession(draft: draft))
    }

    var body: some View {
        ClickerNeutralControlScope {
            VStack(spacing: 0) {
                Form { formFields }
                    .formStyle(.grouped)
                    .scrollContentBackground(.hidden)
                    .background { Rectangle().fill(ClickerVisualTheme.windowBackground) }
                if let error = session.saveError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(ClickerVisualTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, ClickerVisualTheme.spacing12)
                        .padding(.bottom, ClickerVisualTheme.spacing8)
                        .accessibilityLabel("保存失败。\(error)")
                }
                if !isSaveEnabled {
                    Text("录制或回放结束后可保存。输入会保留。")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(ClickerVisualTheme.spacing8)
                }
                Divider()
                HStack {
                    Spacer()
                    Button("取消", action: cancel)
                        .buttonStyle(.bordered)
                        .foregroundStyle(ClickerVisualTheme.primaryText)
                        .keyboardShortcut(.cancelAction)
                    ClickerProminentButton(role: .neutral, action: save) {
                        Text(session.saveError == nil ? "保存" : "重试保存")
                    }
                    .disabled(!isSaveEnabled || coordinatePicker.isPicking)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(ClickerVisualTheme.spacing12)
                .background { Rectangle().fill(ClickerVisualTheme.windowBackground) }
            }
        }
        .frame(width: 380)
        .frame(minHeight: 180, idealHeight: editorHeight, maxHeight: editorHeight)
        .background { Rectangle().fill(ClickerVisualTheme.windowBackground) }
        .interactiveDismissDisabled(session.isDirty)
        .onExitCommand(perform: cancel)
        .confirmationDialog("放弃未保存的修改？", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("放弃修改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) { }
        }
        .onDisappear { coordinatePicker.cancel() }
        .onChange(of: isSaveEnabled) { _, enabled in
            if !enabled { coordinatePicker.cancel() }
        }
    }

    private var editorHeight: CGFloat {
        switch session.draft.kind {
        case .drag, .move: 530
        case .click, .scroll: 440
        case .shortcut: 350
        case .typeText: 280
        case .wait: 200
        }
    }

    @ViewBuilder private var formFields: some View {
        Section(session.draft.kind.title) {
            switch session.draft.kind {
            case .click:
                positionFields(isEnd: false, title: "位置")
                mouseButtonPicker
                Stepper("点击次数：\(session.draft.clickCount)", value: $session.draft.clickCount, in: 1...3)
            case .move:
                if session.draft.original == nil { positionFields(isEnd: false, title: "起点") }
                positionFields(isEnd: true, title: "终点")
                TextField("时长（秒）", text: $session.draft.duration)
                if session.draft.original != nil {
                    Text("修改终点后，轨迹将整体平移至新终点")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .drag:
                positionFields(isEnd: false, title: "起点")
                positionFields(isEnd: true, title: "终点")
                mouseButtonPicker
                TextField("时长（秒）", text: $session.draft.duration)
            case .scroll:
                positionFields(isEnd: false, title: "滚动位置")
                TextField("垂直滚动量（负为向下）", text: $session.draft.scrollDeltaY)
            case .typeText:
                TextField("文本", text: $session.draft.text, axis: .vertical).lineLimit(3...6)
            case .shortcut:
                Toggle("⌘ Command", isOn: flagBinding(KeyCodeMap.maskCommand))
                Toggle("⌥ Option", isOn: flagBinding(KeyCodeMap.maskOption))
                Toggle("⌃ Control", isOn: flagBinding(KeyCodeMap.maskControl))
                Toggle("⇧ Shift", isOn: flagBinding(KeyCodeMap.maskShift))
                Picker("主键", selection: $session.draft.keyCode) {
                    Text("请选择…").tag(Optional<UInt16>.none)
                    ForEach(commonKeys, id: \.code) { key in
                        Text(key.name).tag(Optional(key.code))
                    }
                }
            case .wait: TextField("时长（秒）", text: $session.draft.duration)
            }
        }
        if [.click, .move, .drag, .scroll].contains(session.draft.kind) {
            Section("位置预览") {
                CoordinatePreview(points: previewPoints)
                    .frame(height: 88)
                Text("主显示器左上角为原点，单位为点；支持负坐标。预览为屏幕示意，不截取屏幕内容。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var mouseButtonPicker: some View {
        Picker("按键", selection: $session.draft.button) {
            Text("左键").tag(MouseButton.left)
            Text("右键").tag(MouseButton.right)
        }
    }

    private func positionFields(isEnd: Bool, title: String) -> some View {
        VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing8) {
            HStack {
                TextField("\(title) X", text: isEnd ? $session.draft.endX : $session.draft.x)
                TextField("\(title) Y", text: isEnd ? $session.draft.endY : $session.draft.y)
            }
            Button("在屏幕上选择\(title)…", systemImage: "scope") {
                coordinatePicker.pick { point in
                    guard let point else { return }
                    if isEnd {
                        session.draft.endX = String(Double(point.x))
                        session.draft.endY = String(Double(point.y))
                    } else {
                        session.draft.x = String(Double(point.x))
                        session.draft.y = String(Double(point.y))
                    }
                }
            }
            .disabled(!isSaveEnabled || coordinatePicker.isPicking)
        }
    }

    private var previewPoints: [CGPoint] {
        [(session.draft.x, session.draft.y), (session.draft.endX, session.draft.endY)].compactMap { x, y in
            guard let x = ActionEditorDraft.number(x), let y = ActionEditorDraft.number(y) else { return nil }
            return CGPoint(x: x, y: y)
        }
    }

    private func flagBinding(_ flag: UInt64) -> Binding<Bool> {
        Binding(get: { session.draft.shortcutFlags & flag != 0 }, set: { selected in
            if selected { session.draft.shortcutFlags |= flag }
            else { session.draft.shortcutFlags &= ~flag }
        })
    }

    private var commonKeys: [(code: UInt16, name: String)] {
        let keys: [(UInt16, String)] = [
            (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"), (3, "F"), (5, "G"),
            (4, "H"), (34, "I"), (38, "J"), (40, "K"), (37, "L"), (46, "M"), (45, "N"),
            (31, "O"), (35, "P"), (12, "Q"), (15, "R"), (1, "S"), (17, "T"), (32, "U"),
            (9, "V"), (13, "W"), (7, "X"), (16, "Y"), (6, "Z"),
            (36, "Return"), (49, "Space"), (48, "Tab"), (53, "Esc"), (51, "Delete"),
            (123, "←"), (124, "→"), (125, "↓"), (126, "↑"),
        ]
        var result = keys.map { (code: $0.0, name: $0.1) }
        if let code = session.draft.keyCode, !result.contains(where: { $0.code == code }) {
            result.append((code: code, name: "键码 \(code)"))
        }
        return result
    }

    private func cancel() {
        if coordinatePicker.isPicking { coordinatePicker.cancel(); return }
        if session.isDirty { confirmsDiscard = true } else { dismiss() }
    }

    private func save() {
        guard isSaveEnabled, !coordinatePicker.isPicking else { return }
        if session.save(using: onSave, errorMessage: saveErrorMessage) { dismiss() }
    }
}

import SwiftUI
import ClickerCore

struct RecordingShortcutEditor {
    private static let globalRecord = RecordingStopShortcut(
        keyCode: 15,
        modifierFlags: KeyCodeMap.maskOption | KeyCodeMap.maskCommand
    )
    private static let globalPlay = RecordingStopShortcut(
        keyCode: 35,
        modifierFlags: KeyCodeMap.maskOption | KeyCodeMap.maskCommand
    )

    private(set) var shortcut: RecordingStopShortcut
    private(set) var message: String?

    init(shortcut: RecordingStopShortcut) {
        self.shortcut = shortcut
    }

    @discardableResult
    mutating func accept(_ candidate: RecordingStopShortcut) -> Bool {
        switch candidate.validation(
            globalRecord: Self.globalRecord,
            globalPlay: Self.globalPlay
        ) {
        case .conflict(let name):
            message = "与全局快捷键「\(name)」冲突"
            return false
        case .modifierOnly:
            return false
        case .riskyTextKey:
            shortcut = candidate
            message = "裸文本键可能在输入文字时误触发"
            return true
        case .valid:
            shortcut = candidate
            message = nil
            return true
        }
    }

    mutating func restoreDefault() {
        shortcut = .defaultValue
        message = nil
    }
}

struct RecordingSettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isCapturing = false
    @State private var editor = RecordingShortcutEditor(shortcut: .defaultValue)

    var body: some View {
        NavigationStack {
            Form {
                Section("停止录制") {
                    LabeledContent("当前快捷键") {
                        Text(editor.shortcut.displayName)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel("当前快捷键 \(editor.shortcut.displayName)")
                    }

                    Button(isCapturing ? "请按下新的快捷键…" : "更改快捷键") {
                        isCapturing.toggle()
                    }

                    if isCapturing {
                        ShortcutCaptureView(onCandidate: accept)
                            .frame(height: 1)
                    }
                }

                Section("提示") {
                    if let message = editor.message {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        Text("录制时可在任意应用中按此快捷键停止。")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("恢复默认值（Esc）") {
                        editor.restoreDefault()
                        state.recordingStopShortcut = editor.shortcut
                        isCapturing = false
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("录制设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(width: 440, height: 360)
        .disabled(state.phase != .idle)
        .onAppear {
            editor = RecordingShortcutEditor(shortcut: state.recordingStopShortcut)
        }
        .onChange(of: state.phase) { _, phase in
            if phase != .idle { dismiss() }
        }
    }

    private func accept(_ candidate: RecordingStopShortcut) {
        if editor.accept(candidate) {
            state.recordingStopShortcut = editor.shortcut
        }
        isCapturing = false
    }
}

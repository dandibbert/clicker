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

struct RecordingSettingsPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(ClickerVisualTheme.spacing16)
            .background(
                ClickerVisualTheme.elevatedSurface,
                in: RoundedRectangle(
                    cornerRadius: ClickerVisualTheme.panelCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: ClickerVisualTheme.panelCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    ClickerVisualTheme.separator,
                    lineWidth: ClickerVisualTheme.cardBorderWidth
                )
            }
    }
}

struct RecordingSettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isCapturing = false
    @State private var editor = RecordingShortcutEditor(shortcut: .defaultValue)

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing16) {
                RecordingSettingsPanel {
                    VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing12) {
                        Text("停止录制")
                            .font(.headline)
                            .foregroundStyle(ClickerVisualTheme.primaryText)

                        HStack(spacing: ClickerVisualTheme.spacing12) {
                            Text("当前快捷键")
                                .foregroundStyle(ClickerVisualTheme.secondaryText)
                            Spacer()
                            shortcutToken
                        }

                        Divider()

                        Button(isCapturing ? "请按下新的快捷键…" : "更改快捷键") {
                            isCapturing.toggle()
                        }

                        if isCapturing {
                            ShortcutCaptureView(onCandidate: accept)
                                .frame(height: 1)
                        }
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: ClickerVisualTheme.spacing8) {
                    if let message = editor.message {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    } else {
                        Text("录制时可在任意应用中按此快捷键停止。")
                            .foregroundStyle(ClickerVisualTheme.secondaryText)
                    }
                }
                .padding(.horizontal, ClickerVisualTheme.spacing4)

                Spacer(minLength: 0)

                HStack(spacing: ClickerVisualTheme.spacing8) {
                    Button("恢复默认值") {
                        editor.restoreDefault()
                        state.recordingStopShortcut = editor.shortcut
                        isCapturing = false
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    ClickerProminentButton(role: .neutral, action: { dismiss() }) {
                        Text("完成")
                    }
                }
            }
            .padding(ClickerVisualTheme.spacing24)
            .background(ClickerVisualTheme.canvas)
            .navigationTitle("录制设置")
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

    private var shortcutToken: some View {
        Text(editor.shortcut.displayName)
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .foregroundStyle(ClickerVisualTheme.primaryText)
            .padding(.horizontal, ClickerVisualTheme.spacing12)
            .padding(.vertical, ClickerVisualTheme.spacing4)
            .background(
                ClickerVisualTheme.cardSurface,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(ClickerVisualTheme.separator, lineWidth: 1)
            }
            .accessibilityLabel("当前快捷键 \(editor.shortcut.displayName)")
    }
}

import SwiftUI
import ClickerCore

struct ClickerSettingsView: View {
    var body: some View {
        RecordingSettingsView()
    }
}

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

struct RecordingSettingsMessage: View {
    let message: String?

    var foregroundRole: ClickerVisualTheme.ColorRole {
        message == nil ? .secondaryText : .primaryText
    }

    var body: some View {
        Group {
            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
            } else {
                Text("录制时可在任意应用中按此快捷键停止。")
            }
        }
        .foregroundStyle(ClickerVisualTheme.color(for: foregroundRole))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ClickerVisualTheme.spacing4)
    }
}

struct RecordingSettingsFooter: View {
    let restoreDefaults: () -> Void
    let done: () -> Void

    var body: some View {
        HStack(spacing: ClickerVisualTheme.spacing8) {
            Button("恢复默认值", action: restoreDefaults)
                .buttonStyle(.bordered)

            Spacer()

            ClickerProminentButton(role: .neutral, action: done) {
                Text("完成")
            }
        }
        .padding(.horizontal, ClickerVisualTheme.spacing24)
        .padding(.vertical, ClickerVisualTheme.spacing16)
        .background(ClickerVisualTheme.canvas)
    }
}

struct RecordingSettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isCapturing = false
    @State private var editor = RecordingShortcutEditor(shortcut: .defaultValue)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing16) {
                    RecordingSettingsPanel {
                        VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing12) {
                            Text("外观")
                                .font(.headline)
                                .foregroundStyle(ClickerVisualTheme.primaryText)

                            Picker("外观", selection: $state.appearancePreference) {
                                ForEach(AppAppearancePreference.allCases, id: \.self) { preference in
                                    Text(preference.title).tag(preference)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }

                    ShortcutCaptureCard(
                        shortcut: editor.shortcut,
                        isCapturing: isCapturing,
                        action: { isCapturing = true }
                    )
                    .background {
                        if isCapturing {
                            ShortcutCaptureView(onCandidate: accept)
                                .frame(width: 1, height: 1)
                                .opacity(0)
                                .accessibilityHidden(true)
                        }
                    }

                    RecordingSettingsMessage(message: editor.message)
                }
                .padding(.horizontal, ClickerVisualTheme.spacing24)
                .padding(.top, ClickerVisualTheme.spacing24)
                .padding(.bottom, ClickerVisualTheme.spacing16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RecordingSettingsFooter(
                    restoreDefaults: restoreDefaults,
                    done: { dismiss() }
                )
            }
            .background(ClickerVisualTheme.canvas)
            .navigationTitle("录制设置")
        }
        .frame(width: 440, height: 360)
        .disabled(state.phase != .idle)
        .onAppear {
            editor = RecordingShortcutEditor(shortcut: state.recordingStopShortcut)
        }
    }

    private func restoreDefaults() {
        editor.restoreDefault()
        state.recordingStopShortcut = editor.shortcut
        isCapturing = false
    }

    private func accept(_ candidate: RecordingStopShortcut) {
        if editor.accept(candidate) {
            state.recordingStopShortcut = editor.shortcut
        }
        isCapturing = false
    }
}

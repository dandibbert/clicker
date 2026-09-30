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
    mutating func accept(
        _ candidate: RecordingStopShortcut,
        scripts: [Script] = []
    ) -> Bool {
        let candidateScriptShortcut = ScriptShortcut(
            keyCode: candidate.keyCode,
            modifierFlags: candidate.modifierFlags
        )
        if let conflict = scripts.first(where: {
            $0.playbackShortcut == candidateScriptShortcut
        }) {
            message = "与脚本「\(conflict.name)」的回放快捷键冲突"
            return false
        }
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
                ClickerVisualTheme.controlSurface,
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

struct RecordingSettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var isCapturing = false
    @State private var editor = RecordingShortcutEditor(shortcut: .defaultValue)

    var body: some View {
        ClickerNeutralControlScope {
            ScrollView {
                VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing16) {
                    settingsSection("通用") {
                        RecordingSettingsPanel {
                            HStack(spacing: ClickerVisualTheme.spacing12) {
                                Text("外观")
                                    .foregroundStyle(ClickerVisualTheme.primaryText)

                                Picker("外观", selection: $state.appearancePreference) {
                                    ForEach(AppAppearancePreference.allCases, id: \.self) { preference in
                                        Text(preference.title).tag(preference)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .frame(width: 240)
                                .disabled(state.phase != .idle)
                            }
                        }
                    }

                    settingsSection("录制") {
                        ShortcutCaptureCard(
                            shortcut: editor.shortcut,
                            isCapturing: isCapturing,
                            action: beginCapture
                        )
                        .disabled(state.phase != .idle)
                        .background {
                            if isCapturing {
                                ShortcutCaptureView(onCandidate: accept)
                                    .frame(width: 1, height: 1)
                                    .opacity(0)
                                    .accessibilityHidden(true)
                            }
                        }

                        RecordingSettingsMessage(message: editor.message)

                        Button("恢复默认设置", action: restoreDefaults)
                            .buttonStyle(.bordered)
                            .foregroundStyle(ClickerVisualTheme.secondaryText)
                            .disabled(state.phase != .idle)
                    }
                }
                .padding(.horizontal, ClickerVisualTheme.spacing24)
                .padding(.vertical, ClickerVisualTheme.spacing16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(ClickerVisualTheme.canvas)
        .frame(width: 440, height: 360)
        .onAppear {
            editor = RecordingShortcutEditor(shortcut: state.recordingStopShortcut)
        }
        .onChange(of: state.phase) { _, phase in
            if phase != .idle {
                isCapturing = false
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing8) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(ClickerVisualTheme.primaryText)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func beginCapture() {
        guard state.phase == .idle else { return }
        isCapturing = true
    }

    private func restoreDefaults() {
        editor.restoreDefault()
        state.recordingStopShortcut = editor.shortcut
        state.appearancePreference = .system
        isCapturing = false
    }

    private func accept(_ candidate: RecordingStopShortcut) {
        if editor.accept(candidate, scripts: state.scripts) {
            state.recordingStopShortcut = editor.shortcut
        }
        isCapturing = false
    }
}

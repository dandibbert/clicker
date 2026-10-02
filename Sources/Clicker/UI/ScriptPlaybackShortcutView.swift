import ClickerCore
import SwiftUI

enum ScriptShortcutValidation: Equatable {
    case success(ScriptShortcut)
    case failure(String)
}

enum ScriptShortcutEditor {
    private static let globalRecord = ScriptShortcut(
        keyCode: 15,
        modifierFlags: KeyCodeMap.maskOption | KeyCodeMap.maskCommand
    )
    private static let globalPlay = ScriptShortcut(
        keyCode: 35,
        modifierFlags: KeyCodeMap.maskOption | KeyCodeMap.maskCommand
    )

    static func displayedShortcut(for script: Script?) -> RecordingStopShortcut? {
        guard let shortcut = script?.playbackShortcut else { return nil }
        return RecordingStopShortcut(keyCode: shortcut.keyCode, modifierFlags: shortcut.modifierFlags)
    }

    static func validate(
        candidate: ScriptShortcut,
        scriptID: UUID,
        scripts: [Script],
        recordingStopShortcut: RecordingStopShortcut = .defaultValue
    ) -> ScriptShortcutValidation {
        guard candidate.modifierFlags != 0 else {
            return .failure("脚本回放快捷键必须包含至少一个修饰键")
        }
        if candidate == globalRecord {
            return .failure("与全局快捷键「开始/停止录制」冲突")
        }
        if candidate == globalPlay {
            return .failure("与全局快捷键「开始/停止回放」冲突")
        }
        let stopShortcut = ScriptShortcut(
            keyCode: recordingStopShortcut.keyCode,
            modifierFlags: recordingStopShortcut.modifierFlags
        )
        if candidate == stopShortcut {
            return .failure("与停止录制快捷键冲突")
        }
        if let conflict = scripts.first(where: {
            $0.id != scriptID && $0.playbackShortcut == candidate
        }) {
            return .failure("与脚本「\(conflict.name)」的回放快捷键冲突")
        }
        return .success(candidate)
    }
}

struct ScriptPlaybackShortcutView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let scriptID: UUID
    @State private var isCapturing = false
    @State private var message: String?

    private var script: Script? {
        state.scripts.first { $0.id == scriptID }
    }

    private var displayedShortcut: RecordingStopShortcut? {
        ScriptShortcutEditor.displayedShortcut(for: script)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing16) {
            Text("脚本回放快捷键")
                .font(.title2.weight(.semibold))
                .foregroundStyle(ClickerVisualTheme.primaryText)

            Text("在任意应用中按下快捷键，直接回放「\(script?.name ?? "脚本")」。")
                .foregroundStyle(ClickerVisualTheme.secondaryText)

            Group {
                if let displayedShortcut {
                    ShortcutCaptureCard(
                        shortcut: displayedShortcut,
                        isCapturing: isCapturing,
                        title: "回放快捷键",
                        action: { isCapturing = true }
                    )
                } else {
                    UnboundScriptShortcutCard(isCapturing: isCapturing) { isCapturing = true }
                }
            }
            .disabled(!state.canEditScripts)
            .background {
                if isCapturing {
                    ShortcutCaptureView(onCandidate: accept)
                        .frame(width: 1, height: 1)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            }

            if let message {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(ClickerVisualTheme.primaryText)
            } else {
                Text("必须包含 ⌃、⌥、⇧ 或 ⌘ 中至少一个修饰键。")
                    .foregroundStyle(ClickerVisualTheme.secondaryText)
            }

            HStack {
                Button("清除快捷键", action: clear)
                    .disabled(script?.playbackShortcut == nil || !state.canEditScripts)
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ClickerVisualTheme.spacing24)
        .frame(width: 440)
        .background(ClickerVisualTheme.canvas)
        .onChange(of: state.canEditScripts) { _, canEdit in
            if !canEdit { isCapturing = false }
        }
    }

    private func accept(_ candidate: RecordingStopShortcut) {
        guard var script else { return }
        let shortcut = ScriptShortcut(
            keyCode: candidate.keyCode,
            modifierFlags: candidate.modifierFlags
        )
        switch ScriptShortcutEditor.validate(
            candidate: shortcut,
            scriptID: script.id,
            scripts: state.scripts,
            recordingStopShortcut: state.recordingStopShortcut
        ) {
        case .success:
            script.playbackShortcut = shortcut
            if state.update(script) { message = nil }
        case .failure(let failure):
            message = failure
        }
        isCapturing = false
    }

    private func clear() {
        guard var script else { return }
        script.playbackShortcut = nil
        if state.update(script) { message = nil }
        isCapturing = false
    }
}


/// An unbound shortcut has no keycaps: a suggestion must never look registered.
struct UnboundScriptShortcutCard: View {
    let isCapturing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ClickerVisualTheme.spacing12) {
                Image(systemName: "keyboard").font(.title2)
                VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing4) {
                    Text("尚未设置").font(.headline)
                    Text(isCapturing ? "请按下新的组合键…" : "点击录入快捷键")
                        .font(.callout)
                        .foregroundStyle(ClickerVisualTheme.secondaryText)
                }
                Spacer()
            }
            .foregroundStyle(ClickerVisualTheme.primaryText)
            .padding(ClickerVisualTheme.spacing12)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .background(ClickerVisualTheme.cardSurface,
                        in: RoundedRectangle(cornerRadius: ClickerVisualTheme.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: ClickerVisualTheme.cardCornerRadius)
                    .strokeBorder(isCapturing ? ClickerVisualTheme.primaryText : ClickerVisualTheme.separator,
                                  lineWidth: ClickerVisualTheme.cardBorderWidth)
            }
            .contentShape(RoundedRectangle(cornerRadius: ClickerVisualTheme.cardCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCapturing ? "尚未设置，请按下新的组合键" : "尚未设置，点击录入快捷键")
    }
}

import ClickerCore
import SwiftUI

struct ShortcutKeycapPresentation: Equatable {
    let keys: [String]
    let title = "停止录制快捷键"
    let instruction: String
    let accessibilityLabel: String

    init(shortcut: RecordingStopShortcut, isCapturing: Bool) {
        let modifiers: [(mask: UInt64, symbol: String)] = [
            (KeyCodeMap.maskControl, "⌃"),
            (KeyCodeMap.maskOption, "⌥"),
            (KeyCodeMap.maskShift, "⇧"),
            (KeyCodeMap.maskCommand, "⌘"),
        ]
        keys = modifiers.compactMap { modifier in
            shortcut.modifierFlags & modifier.mask == 0 ? nil : modifier.symbol
        } + [KeyCodeMap.name(for: shortcut.keyCode)]
        instruction = isCapturing ? "请按下新的组合键…" : "点击重新录入"
        accessibilityLabel = "停止录制快捷键，\(shortcut.displayName)，\(instruction)"
    }
}

struct ShortcutCaptureCard: View {
    let shortcut: RecordingStopShortcut
    let isCapturing: Bool
    let action: () -> Void

    private var presentation: ShortcutKeycapPresentation {
        ShortcutKeycapPresentation(shortcut: shortcut, isCapturing: isCapturing)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: ClickerVisualTheme.spacing12) {
                VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing8) {
                    Text(presentation.title)
                        .font(.headline)
                        .foregroundStyle(ClickerVisualTheme.primaryText)

                    HStack(spacing: ClickerVisualTheme.spacing4) {
                        ForEach(Array(presentation.keys.enumerated()), id: \.offset) { _, key in
                            Text(key)
                                .font(.system(.body, design: .monospaced).weight(.semibold))
                                .foregroundStyle(ClickerVisualTheme.primaryText)
                                .frame(minWidth: 30, minHeight: 30)
                                .padding(.horizontal, ClickerVisualTheme.spacing4)
                                .background(
                                    ClickerVisualTheme.elevatedSurface,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(ClickerVisualTheme.separator, lineWidth: 1)
                                }
                        }
                    }
                }

                Spacer(minLength: ClickerVisualTheme.spacing8)

                Text(presentation.instruction)
                    .foregroundStyle(
                        isCapturing
                            ? ClickerVisualTheme.primaryText
                            : ClickerVisualTheme.secondaryText
                    )
                    .multilineTextAlignment(.trailing)
                    .frame(width: 104, alignment: .trailing)
            }
            .padding(ClickerVisualTheme.spacing16)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(
                ClickerVisualTheme.cardSurface,
                in: RoundedRectangle(
                    cornerRadius: ClickerVisualTheme.cardCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: ClickerVisualTheme.cardCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    isCapturing
                        ? ClickerVisualTheme.primaryText
                        : ClickerVisualTheme.separator,
                    lineWidth: ClickerVisualTheme.cardBorderWidth
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

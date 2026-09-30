import ClickerCore
import SwiftUI

struct ShortcutKeycapPresentation: Equatable {
    let keys: [String]
    let title: String
    let instruction: String
    let accessibilityLabel: String

    init(
        shortcut: RecordingStopShortcut,
        isCapturing: Bool,
        title: String = "停止录制快捷键"
    ) {
        self.title = title
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
        accessibilityLabel = "\(title)，\(shortcut.displayName)，\(instruction)"
    }
}

struct ShortcutCaptureCard: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    let shortcut: RecordingStopShortcut
    let isCapturing: Bool
    var title = "停止录制快捷键"
    let action: () -> Void

    private var presentation: ShortcutKeycapPresentation {
        ShortcutKeycapPresentation(
            shortcut: shortcut,
            isCapturing: isCapturing,
            title: title
        )
    }

    private var layoutPolicy: ClickerPresentationLayoutPolicy {
        ClickerPresentationLayoutPolicy(dynamicTypeSize: dynamicTypeSize)
    }

    var body: some View {
        Button(action: action) {
            cardContent
        }
        .buttonStyle(ShortcutCaptureButtonStyle(
            isCapturing: isCapturing,
            isEnabled: isEnabled,
            isHovered: isHovered,
            isFocused: isFocused
        ))
        .onHover { isHovered = $0 }
        .focused($isFocused)
        .focusEffectDisabled()
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    @ViewBuilder
    private var cardContent: some View {
        if layoutPolicy.usesAccessibilityLayout {
            VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing8) {
                titleView
                keycaps
                instruction
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(ClickerVisualTheme.spacing12)
            .frame(
                maxWidth: .infinity,
                minHeight: layoutPolicy.shortcutCardHeight,
                maxHeight: layoutPolicy.shortcutCardHeight,
                alignment: .leading
            )
        } else {
            HStack(spacing: ClickerVisualTheme.spacing12) {
                VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing4) {
                    titleView
                    keycaps
                }

                Spacer(minLength: ClickerVisualTheme.spacing8)
                instruction
                    .frame(width: 104, alignment: .trailing)
            }
            .padding(.horizontal, ClickerVisualTheme.spacing12)
            .frame(
                maxWidth: .infinity,
                minHeight: layoutPolicy.shortcutCardHeight,
                maxHeight: layoutPolicy.shortcutCardHeight,
                alignment: .leading
            )
        }
    }

    private var titleView: some View {
        Text(presentation.title)
            .font(.headline)
            .foregroundStyle(ClickerVisualTheme.primaryText)
    }

    private var instruction: some View {
        Text(presentation.instruction)
            .foregroundStyle(
                isCapturing
                    ? ClickerVisualTheme.primaryText
                    : ClickerVisualTheme.secondaryText
            )
            .multilineTextAlignment(layoutPolicy.usesAccessibilityLayout ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var keycaps: some View {
        HStack(spacing: ClickerVisualTheme.spacing4) {
            ForEach(Array(presentation.keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(ClickerVisualTheme.primaryText)
                    .frame(minWidth: 26, minHeight: 26)
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
}

private struct ShortcutCaptureButtonStyle: ButtonStyle {
    let isCapturing: Bool
    let isEnabled: Bool
    let isHovered: Bool
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        let state = ClickerInteractiveSurfaceState(
            isHovered: isHovered,
            isPressed: configuration.isPressed,
            isEnabled: isEnabled,
            isFocused: isFocused
        )
        configuration.label
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
            .contentShape(
                RoundedRectangle(
                    cornerRadius: ClickerVisualTheme.cardCornerRadius,
                    style: .continuous
                )
            )
            .modifier(ClickerInteractiveSurfaceModifier(
                state: state,
                cornerRadius: ClickerVisualTheme.cardCornerRadius
            ))
    }
}

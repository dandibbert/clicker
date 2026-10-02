import SwiftUI
import ClickerCore

struct ActionCardEditConfiguration {
    private let onEdit: (() -> Void)?

    init(isEnabled: Bool, onEdit: @escaping () -> Void) {
        self.onEdit = isEnabled ? onEdit : nil
    }

    var isEnabled: Bool { onEdit != nil }
    let accessibilityActionName = "编辑动作"
    let accessibilityHint = "双击，按 Return 或 Space，或使用 VoiceOver“编辑动作”操作"

    func performEdit() {
        onEdit?()
    }
}

struct ActionCardActiveTrail: View {
    let feedbackStyle: ActiveFeedbackStyle?
    let isDimmed: Bool

    var trailOpacity: Double {
        switch feedbackStyle {
        case nil:
            0
        case .staticHighlight:
            1
        case .pulsingTrail:
            isDimmed ? 0.86 : 1
        }
    }

    var body: some View {
        Capsule()
            .fill(ClickerVisualTheme.activeTrail)
            .frame(width: 3)
            .padding(.vertical, ClickerVisualTheme.spacing4)
            .opacity(trailOpacity)
            .animation(trailAnimation, value: isDimmed)
    }

    private var trailAnimation: Animation? {
        guard feedbackStyle == .pulsingTrail else { return nil }
        return .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
    }
}

struct ActionCardView: View {
    let block: ActionBlock
    let isActive: Bool
    private let editConfiguration: ActionCardEditConfiguration?
    private let onCopy: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isTrailDimmed = false

    init(
        block: ActionBlock,
        isActive: Bool,
        isEditEnabled: Bool = false,
        onEdit: (() -> Void)? = nil,
        onCopy: (() -> Void)? = nil
    ) {
        self.block = block
        self.isActive = isActive
        self.onCopy = onCopy
        editConfiguration = onEdit.map {
            ActionCardEditConfiguration(isEnabled: isEditEnabled, onEdit: $0)
        }
    }

    private var presentation: ActionCardPresentation {
        ActionCardPresentation(block: block)
    }

    private var feedbackStyle: ActiveFeedbackStyle? {
        ActiveFeedbackStyle.resolve(
            isActive: isActive,
            reduceMotion: accessibilityReduceMotion
        )
    }

    var body: some View {
        HStack(spacing: ClickerVisualTheme.spacing12) {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ClickerVisualTheme.primaryText)
                .frame(width: 30, height: 30)
                .background(
                    ClickerVisualTheme.elevatedSurface,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing4) {
                Text(presentation.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(ClickerVisualTheme.primaryText)
                    .lineLimit(1)
                Text(presentation.summary)
                    .font(.caption)
                    .foregroundStyle(ClickerVisualTheme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: ClickerVisualTheme.spacing8)

            Text(presentation.trailingText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(ClickerVisualTheme.secondaryText)
                .lineLimit(1)
                .frame(width: 64, alignment: .trailing)

            if let configuration = editConfiguration {
                Button(action: configuration.performEdit) {
                    Image(systemName: "pencil")
                        .frame(width: 24, height: 28)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(ClickerVisualTheme.secondaryText)
                .disabled(!configuration.isEnabled)
                .help("编辑动作")
                .accessibilityLabel("编辑动作")
            }
            if let onCopy {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 24, height: 28)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(ClickerVisualTheme.secondaryText)
                .help("复制动作，可粘贴到其他脚本")
                .accessibilityLabel("复制动作")
            }
        }
        .padding(.vertical, ClickerVisualTheme.spacing8)
        .frame(minHeight: 56)
        .background {
            if isActive {
                ClickerVisualTheme.selection
            }
        }
        .overlay(alignment: .leading) {
            ActionCardActiveTrail(
                feedbackStyle: feedbackStyle,
                isDimmed: isTrailDimmed
            )
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            isActive ? presentation.activeAccessibilityLabel : presentation.accessibilityLabel
        )
        .modifier(ActionCardEditModifier(configuration: editConfiguration))
        .onAppear { updateTrailPulse() }
        .onChange(of: feedbackStyle) { _, _ in updateTrailPulse() }
    }

    private func updateTrailPulse() {
        isTrailDimmed = feedbackStyle == .pulsingTrail
    }
}

struct ActionCardEditModifier: ViewModifier {
    let configuration: ActionCardEditConfiguration?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let configuration, configuration.isEnabled {
            content
                .focusable()
                .onTapGesture(count: 2) {
                    configuration.performEdit()
                }
                .onKeyPress(.return) {
                    configuration.performEdit()
                    return .handled
                }
                .onKeyPress(.space) {
                    configuration.performEdit()
                    return .handled
                }
                .accessibilityAction(named: Text(configuration.accessibilityActionName)) {
                    configuration.performEdit()
                }
                .accessibilityHint(configuration.accessibilityHint)
        } else {
            content
        }
    }
}

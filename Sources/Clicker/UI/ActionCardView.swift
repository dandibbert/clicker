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

struct ActionCardView: View {
    let block: ActionBlock
    let isActive: Bool
    private let editConfiguration: ActionCardEditConfiguration?

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isTrailDimmed = false

    init(
        block: ActionBlock,
        isActive: Bool,
        isEditEnabled: Bool = false,
        onEdit: (() -> Void)? = nil
    ) {
        self.block = block
        self.isActive = isActive
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
        }
        .padding(.vertical, ClickerVisualTheme.spacing8)
        .padding(.horizontal, ClickerVisualTheme.spacing12)
        .background(
            isActive ? ClickerVisualTheme.selection : ClickerVisualTheme.cardSurface,
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
                ClickerVisualTheme.separator,
                lineWidth: ClickerVisualTheme.cardBorderWidth
            )
        }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(ClickerVisualTheme.activeTrail)
                .frame(width: 3)
                .padding(.vertical, ClickerVisualTheme.spacing4)
                .opacity(trailOpacity)
                .animation(trailAnimation, value: isTrailDimmed)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isActive ? presentation.activeAccessibilityLabel : presentation.accessibilityLabel
        )
        .modifier(ActionCardEditModifier(configuration: editConfiguration))
        .onAppear { updateTrailPulse() }
        .onChange(of: feedbackStyle) { _, _ in updateTrailPulse() }
    }

    private var trailOpacity: Double {
        switch feedbackStyle {
        case nil:
            0
        case .staticHighlight:
            1
        case .pulsingTrail:
            isTrailDimmed ? 0.42 : 1
        }
    }

    private var trailAnimation: Animation? {
        guard feedbackStyle == .pulsingTrail else { return nil }
        return .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
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

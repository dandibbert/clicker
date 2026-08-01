import SwiftUI
import ClickerCore

enum ActionCardEditTrigger {
    case doubleClick
    case returnKey
    case spaceKey
    case accessibilityAction
}

struct ActionCardEditPolicy {
    let isEnabled: Bool

    var isFocusable: Bool { isEnabled }
    var accessibilityActionName: String? { isEnabled ? "编辑动作" : nil }

    func allows(_ trigger: ActionCardEditTrigger) -> Bool {
        isEnabled
    }
}

struct ActionCardView: View {
    let block: ActionBlock
    let isActive: Bool
    private let editPolicy: ActionCardEditPolicy
    private let onEdit: (() -> Void)?

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
        editPolicy = ActionCardEditPolicy(isEnabled: isEditEnabled && onEdit != nil)
        self.onEdit = onEdit
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
        .modifier(ActionCardEditModifier(policy: editPolicy, onEdit: onEdit))
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

private struct ActionCardEditModifier: ViewModifier {
    let policy: ActionCardEditPolicy
    let onEdit: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if policy.isFocusable, let onEdit, let actionName = policy.accessibilityActionName {
            content
                .focusable()
                .onTapGesture(count: 2) {
                    if policy.allows(.doubleClick) { onEdit() }
                }
                .onKeyPress(.return) {
                    guard policy.allows(.returnKey) else { return .ignored }
                    onEdit()
                    return .handled
                }
                .onKeyPress(.space) {
                    guard policy.allows(.spaceKey) else { return .ignored }
                    onEdit()
                    return .handled
                }
                .accessibilityAction(named: Text(actionName)) {
                    if policy.allows(.accessibilityAction) { onEdit() }
                }
                .accessibilityHint("双击或按 Return 编辑")
        } else {
            content
        }
    }
}

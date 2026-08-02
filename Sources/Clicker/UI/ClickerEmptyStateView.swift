import SwiftUI

struct ClickerEmptyStateView: View {
    private let kind: ClickerEmptyStateKind
    private let presentation: ClickerEmptyStatePresentation
    private let action: (() -> Void)?
    private let secondaryAction: (() -> Void)?

    init(
        kind: ClickerEmptyStateKind,
        action: (() -> Void)? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.kind = kind
        presentation = ClickerEmptyStatePresentation(kind: kind)
        self.action = action
        self.secondaryAction = secondaryAction
    }

    var body: some View {
        VStack(spacing: ClickerVisualTheme.spacing12) {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(ClickerVisualTheme.primaryText)
                .accessibilityHidden(true)

            VStack(spacing: ClickerVisualTheme.spacing4) {
                Text(presentation.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ClickerVisualTheme.primaryText)
                Text(presentation.description)
                    .font(.callout)
                    .foregroundStyle(ClickerVisualTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            HStack(spacing: ClickerVisualTheme.spacing8) {
                if let actionTitle = presentation.actionTitle, let action {
                    ClickerProminentButton(role: primaryActionRole, action: action) {
                        Text(actionTitle)
                    }
                }

                if let secondaryActionTitle = presentation.secondaryActionTitle,
                   let secondaryAction {
                    ClickerProminentButton(role: .neutral, action: secondaryAction) {
                        Text(secondaryActionTitle)
                    }
                }
            }
        }
        .padding(ClickerVisualTheme.spacing24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClickerVisualTheme.windowBackground)
    }

    private var primaryActionRole: ClickerProminentButtonRole {
        kind == .permissionRequired
            ? .neutral
            : .recording
    }
}

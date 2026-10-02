import SwiftUI

struct ClickerEmptyStateView: View {
    private let kind: ClickerEmptyStateKind
    private let presentation: ClickerEmptyStatePresentation
    private let action: (() -> Void)?
    private let secondaryAction: (() -> Void)?
    private let isActionEnabled: Bool
    private let isSecondaryActionEnabled: Bool

    init(
        kind: ClickerEmptyStateKind,
        action: (() -> Void)? = nil,
        secondaryAction: (() -> Void)? = nil,
        isActionEnabled: Bool = true,
        isSecondaryActionEnabled: Bool = true
    ) {
        self.kind = kind
        presentation = ClickerEmptyStatePresentation(kind: kind)
        self.action = action
        self.secondaryAction = secondaryAction
        self.isActionEnabled = isActionEnabled
        self.isSecondaryActionEnabled = isSecondaryActionEnabled
    }

    var body: some View {
        ZStack {
            Rectangle().fill(ClickerVisualTheme.windowBackground)
                .accessibilityHidden(true)

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

                VStack(spacing: ClickerVisualTheme.spacing8) {
                    if let actionTitle = presentation.actionTitle, let action {
                        ClickerProminentButton(role: primaryActionRole, action: action) {
                            Text(actionTitle)
                        }
                        .disabled(!isActionEnabled)
                    }

                    if let secondaryActionTitle = presentation.secondaryActionTitle,
                       let secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .buttonStyle(.bordered)
                            .tint(ClickerVisualTheme.focusRing)
                            .foregroundStyle(ClickerVisualTheme.primaryText)
                            .disabled(!isSecondaryActionEnabled)
                    }
                }
            }
            .padding(ClickerVisualTheme.spacing24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var primaryActionRole: ClickerProminentButtonRole {
        kind == .emptyScript ? .recording : .neutral
    }
}

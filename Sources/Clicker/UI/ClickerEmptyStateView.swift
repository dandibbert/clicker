import SwiftUI

struct ClickerEmptyStateView: View {
    private let presentation: ClickerEmptyStatePresentation
    private let action: (() -> Void)?

    init(kind: ClickerEmptyStateKind, action: (() -> Void)? = nil) {
        presentation = ClickerEmptyStatePresentation(kind: kind)
        self.action = action
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

            if let actionTitle = presentation.actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(ClickerVisualTheme.recordFill)
            }
        }
        .padding(ClickerVisualTheme.spacing24)
    }
}

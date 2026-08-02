import SwiftUI

enum ClickerProminentButtonRole: Equatable {
    case recording
    case neutral

    var fillRole: ClickerVisualTheme.ColorRole {
        .playbackFill
    }

    var foregroundRole: ClickerVisualTheme.ColorRole {
        .prominentForeground
    }

    var cueRole: ClickerVisualTheme.ColorRole? {
        self == .recording ? .recordFill : nil
    }
}

struct ClickerProminentButton<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled

    let role: ClickerProminentButtonRole
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(ClickerProminentButtonStyle(role: role, isEnabled: isEnabled))
    }
}

private struct ClickerProminentButtonStyle: ButtonStyle {
    let role: ClickerProminentButtonRole
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(ClickerVisualTheme.color(for: role.foregroundRole))
            .padding(.horizontal, ClickerVisualTheme.spacing12)
            .frame(minHeight: ClickerVisualTheme.primaryControlHeight)
            .background(
                ClickerVisualTheme.color(for: role.fillRole),
                in: RoundedRectangle(
                    cornerRadius: ClickerVisualTheme.controlCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: ClickerVisualTheme.controlCornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    ClickerVisualTheme.color(for: role.cueRole ?? .focusRing),
                    lineWidth: role.cueRole == nil ? 1 : 2
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .contentShape(
                RoundedRectangle(
                    cornerRadius: ClickerVisualTheme.controlCornerRadius,
                    style: .continuous
                )
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.45)
    }
}

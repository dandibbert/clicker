import SwiftUI

enum ClickerProminentButtonRole: Equatable {
    case recording
    case neutral
    case secondary

    var fillRole: ClickerVisualTheme.ColorRole {
        switch self {
        case .recording: .recordSurface
        case .neutral: .playbackFill
        case .secondary: .controlSurface
        }
    }

    var foregroundRole: ClickerVisualTheme.ColorRole {
        switch self {
        case .recording: .recordForeground
        case .neutral: .prominentForeground
        case .secondary: .primaryText
        }
    }

    var cueRole: ClickerVisualTheme.ColorRole? {
        self == .recording ? .recordFill : nil
    }
}

struct ClickerProminentButton<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    let role: ClickerProminentButtonRole
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(ClickerProminentButtonStyle(
            role: role,
            isEnabled: isEnabled,
            isHovered: isHovered,
            isFocused: isFocused
        ))
        .onHover { isHovered = $0 }
        .focused($isFocused)
        .focusEffectDisabled()
    }
}

private struct ClickerProminentButtonStyle: ButtonStyle {
    let role: ClickerProminentButtonRole
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
            .modifier(ClickerInteractiveSurfaceModifier(
                state: state,
                cornerRadius: ClickerVisualTheme.controlCornerRadius
            ))
    }
}

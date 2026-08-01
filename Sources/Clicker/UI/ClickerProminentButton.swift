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
    let role: ClickerProminentButtonRole
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(ClickerVisualTheme.color(for: role.foregroundRole))
        }
        .buttonStyle(.borderedProminent)
        .tint(ClickerVisualTheme.color(for: role.fillRole))
        .overlay {
            if let cueRole = role.cueRole {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(ClickerVisualTheme.color(for: cueRole), lineWidth: 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

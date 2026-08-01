import SwiftUI

enum ClickerProminentButtonRole: Equatable {
    case recording
    case neutral

    var fillRole: ClickerVisualTheme.ColorRole {
        switch self {
        case .recording:
            .recordFill
        case .neutral:
            .playbackFill
        }
    }

    var foregroundRole: ClickerVisualTheme.ColorRole {
        .prominentForeground
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
    }
}

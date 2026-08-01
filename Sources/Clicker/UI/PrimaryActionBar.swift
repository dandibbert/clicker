import SwiftUI

struct PrimaryActionBar: View {
    let phase: AppPhase
    let hasPlayableScript: Bool

    private var actions: [PrimaryActionPresentation] {
        PrimaryActionPresentation.pair(
            phase: phase,
            hasPlayableScript: hasPlayableScript
        )
    }

    var body: some View {
        HStack(spacing: ClickerVisualTheme.spacing8) {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                Button {
                    post(action)
                } label: {
                    actionLabel(action)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint(for: action))
                .disabled(!action.isEnabled)
                .accessibilityLabel(action.accessibilityLabel)
                .help(action.accessibilityLabel)
                .frame(maxWidth: .infinity)
                .frame(
                    minWidth: 108,
                    minHeight: ClickerVisualTheme.primaryControlHeight
                )
            }
        }
    }

    @ViewBuilder
    private func actionLabel(_ action: PrimaryActionPresentation) -> some View {
        switch action.kind {
        case .record:
            Label(action.title, systemImage: action.systemImage)
        case .play:
            Label(action.title, systemImage: action.systemImage)
                .foregroundStyle(ClickerVisualTheme.playbackForeground)
        }
    }

    private func tint(for action: PrimaryActionPresentation) -> Color {
        switch action.kind {
        case .record:
            ClickerVisualTheme.recordFill
        case .play:
            ClickerVisualTheme.playbackFill
        }
    }

    private func post(_ action: PrimaryActionPresentation) {
        switch action.kind {
        case .record:
            NotificationCenter.default.post(name: .toggleRecord, object: ["source": "ui"])
        case .play:
            NotificationCenter.default.post(name: .togglePlay, object: nil)
        }
    }
}

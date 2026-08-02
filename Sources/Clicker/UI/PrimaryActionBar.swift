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
                ClickerProminentButton(role: buttonRole(for: action)) {
                    post(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: ClickerVisualTheme.primaryControlHeight)
                }
                .disabled(!action.isEnabled)
                .accessibilityLabel(action.accessibilityLabel)
                .help(action.accessibilityLabel)
                .frame(maxWidth: .infinity)
                .frame(
                    minWidth: 96,
                    minHeight: ClickerVisualTheme.primaryControlHeight
                )
            }
        }
    }

    private func buttonRole(for action: PrimaryActionPresentation) -> ClickerProminentButtonRole {
        switch action.kind {
        case .record:
            .recording
        case .play:
            .neutral
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

import SwiftUI

struct PlaybackIndicatorView: View {
    let progress: PlaybackProgress
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .accessibilityHidden(true)
                Text(progress.scriptName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(progress.scriptName)
                Spacer(minLength: 4)
                Text("Esc 停止")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ClickerVisualTheme.secondaryText)
            }
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(progress.stepDescription)
                        .font(.system(size: 12, weight: .medium))
                    Text(progress.iterationDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(ClickerVisualTheme.secondaryText)
                }
                .monospacedDigit()
                Spacer(minLength: 8)
                Button(action: onStop) {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(ClickerVisualTheme.focusRing)
                .accessibilityLabel("停止回放")
                .help("停止回放（Esc）")
            }
        }
        .foregroundStyle(ClickerVisualTheme.primaryText)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(ClickerVisualTheme.separator.opacity(0.4), lineWidth: 1)
        }
    }
}

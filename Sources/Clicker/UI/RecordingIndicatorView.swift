import SwiftUI

enum RecordingIndicatorFeedbackStyle: Equatable {
    case pulsing
    case staticHighlight

    static func resolve(reduceMotion: Bool) -> Self {
        reduceMotion ? .staticHighlight : .pulsing
    }
}

struct RecordingIndicatorView: View {
    let shortcut: RecordingStopShortcut
    let showsHint: Bool
    let hintTopPadding: CGFloat

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isPulsing = false

    private var feedbackStyle: RecordingIndicatorFeedbackStyle {
        .resolve(reduceMotion: accessibilityReduceMotion)
    }

    var body: some View {
        ZStack {
            Color.clear

            RoundedRectangle(cornerRadius: 12)
                .stroke(ClickerVisualTheme.recordFill, lineWidth: 5)
                .padding(8)
                .opacity(borderOpacity)
                .animation(borderAnimation, value: isPulsing)

            if showsHint {
                VStack {
                    Text("正在录制 · 按 \(shortcut.displayName) 停止")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .environment(\.colorScheme, .dark)
                        .padding(.top, hintTopPadding)
                    Spacer()
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { updatePulse() }
        .onChange(of: feedbackStyle) { _, _ in updatePulse() }
    }

    private var borderOpacity: Double {
        switch feedbackStyle {
        case .pulsing:
            isPulsing ? 1 : 0.35
        case .staticHighlight:
            1
        }
    }

    private var borderAnimation: Animation? {
        guard feedbackStyle == .pulsing else { return nil }
        return .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
    }

    private func updatePulse() {
        isPulsing = feedbackStyle == .pulsing
    }
}

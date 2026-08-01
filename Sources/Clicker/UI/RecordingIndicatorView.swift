import SwiftUI

struct RecordingIndicatorView: View {
    let shortcut: RecordingStopShortcut
    let showsHint: Bool

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Color.clear

            RoundedRectangle(cornerRadius: 12)
                .stroke(.red, lineWidth: 5)
                .padding(8)
                .opacity(isPulsing ? 1 : 0.35)
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            if showsHint {
                VStack {
                    Text("正在录制 · 按 \(shortcut.displayName) 停止")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                        .environment(\.colorScheme, .dark)
                        .padding(.top, 28)
                    Spacer()
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { isPulsing = true }
    }
}

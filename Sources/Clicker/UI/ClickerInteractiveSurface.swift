import SwiftUI

struct ClickerInteractiveSurfaceState: Equatable {
    var isHovered = false
    var isPressed = false
    var isEnabled = true
    var isFocused = false
}

struct ClickerInteractiveSurfacePresentation: Equatable {
    let contentOpacity: CGFloat
    let overlayOpacity: CGFloat
    let scale: CGFloat
    let focusLineWidth: CGFloat

    init(state: ClickerInteractiveSurfaceState) {
        guard state.isEnabled else {
            contentOpacity = 0.45
            overlayOpacity = 0
            scale = 1
            focusLineWidth = 0
            return
        }
        contentOpacity = 1
        overlayOpacity = state.isPressed ? 0.18 : (state.isHovered ? 0.08 : 0)
        scale = state.isPressed ? 0.985 : 1
        focusLineWidth = state.isFocused ? 2 : 0
    }
}

struct ClickerInteractiveSurfaceFeedback: View {
    let state: ClickerInteractiveSurfaceState
    let cornerRadius: CGFloat

    var body: some View {
        let presentation = ClickerInteractiveSurfacePresentation(state: state)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(ClickerVisualTheme.focusRing.opacity(presentation.overlayOpacity))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        ClickerVisualTheme.focusRing,
                        lineWidth: presentation.focusLineWidth
                    )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct ClickerInteractiveSurfaceModifier: ViewModifier {
    let state: ClickerInteractiveSurfaceState
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let presentation = ClickerInteractiveSurfacePresentation(state: state)
        content
            .overlay {
                ClickerInteractiveSurfaceFeedback(
                    state: state,
                    cornerRadius: cornerRadius
                )
            }
            .scaleEffect(presentation.scale)
            .opacity(presentation.contentOpacity)
    }
}

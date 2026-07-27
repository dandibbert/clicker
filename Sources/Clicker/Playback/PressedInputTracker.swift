import ClickerCore

struct PressedInputTracker {
    private struct HeldMouseButton {
        var x: Double
        var y: Double
        var clickCount: Int
        var flags: UInt64
    }

    private var heldKeyFlags: [UInt16: UInt64] = [:]
    private var heldMouseButtons: [MouseButton: HeldMouseButton] = [:]

    mutating func observe(_ action: StepAction) {
        switch action {
        case .keyDown(let keyCode, let flags, _):
            heldKeyFlags[keyCode] = flags
        case .keyUp(let keyCode, _):
            heldKeyFlags.removeValue(forKey: keyCode)
        case .mouseDown(let x, let y, let button, let clickCount, let flags):
            heldMouseButtons[button] = HeldMouseButton(
                x: x,
                y: y,
                clickCount: clickCount,
                flags: flags
            )
        case .mouseUp(_, _, let button, _, _):
            heldMouseButtons.removeValue(forKey: button)
        case .mouseDrag(let x, let y, let button, let flags):
            guard var heldButton = heldMouseButtons[button] else { return }
            heldButton.x = x
            heldButton.y = y
            heldButton.flags = flags
            heldMouseButtons[button] = heldButton
        case .mouseMove, .scroll:
            break
        }
    }

    mutating func releaseActions() -> [StepAction] {
        let keyReleases = heldKeyFlags
            .sorted { $0.key < $1.key }
            .map { keyCode, flags in
                StepAction.keyUp(keyCode: keyCode, flags: flags)
            }
        let buttonOrder: [MouseButton] = [.left, .right]
        let mouseReleases = buttonOrder.compactMap { button -> StepAction? in
            guard let heldButton = heldMouseButtons[button] else { return nil }
            return .mouseUp(
                x: heldButton.x,
                y: heldButton.y,
                button: button,
                clickCount: heldButton.clickCount,
                flags: heldButton.flags
            )
        }

        heldKeyFlags.removeAll()
        heldMouseButtons.removeAll()
        return keyReleases + mouseReleases
    }
}

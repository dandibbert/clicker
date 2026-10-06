import CoreGraphics
import ClickerCore

/// StepAction → CGEvent delivery. All events carry syntheticMarker so the
/// recording engine will not capture Clicker's own playback.
enum EventPoster {
    enum Destination: Equatable {
        case system
        case process(pid: pid_t, windowID: CGWindowID?)
    }

    static func scrollDelta(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        let truncated = value.rounded(.towardZero)
        if truncated >= Double(Int32.max) { return Int32.max }
        if truncated <= Double(Int32.min) { return Int32.min }
        return Int32(truncated)
    }

    private static func mark(_ event: CGEvent) {
        event.setIntegerValueField(
            .eventSourceUserData,
            value: EventRecorder.syntheticMarker
        )
    }

    private static func deliver(
        _ event: CGEvent,
        to destination: Destination,
        windowAware: Bool = false
    ) {
        mark(event)

        switch destination {
        case .system:
            event.post(tap: .cghidEventTap)

        case .process(let pid, let windowID):
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
            if windowAware, let windowID {
                let value = Int64(windowID)
                event.setIntegerValueField(
                    .mouseEventWindowUnderMousePointer,
                    value: value
                )
                event.setIntegerValueField(
                    .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
                    value: value
                )
            }
            event.postToPid(pid)
        }
    }

    static func post(_ action: StepAction, to destination: Destination = .system) {
        switch action {
        case .mouseMove(let x, let y, let flags):
            guard let event = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: CGPoint(x: x, y: y),
                mouseButton: .left
            ) else { return }
            event.flags = CGEventFlags(rawValue: flags)
            deliver(event, to: destination, windowAware: true)

        case .mouseDown(let x, let y, let button, let clickCount, let flags):
            let type: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
            let cgButton: CGMouseButton = button == .left ? .left : .right
            guard let event = CGEvent(
                mouseEventSource: nil,
                mouseType: type,
                mouseCursorPosition: CGPoint(x: x, y: y),
                mouseButton: cgButton
            ) else { return }
            event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            event.flags = CGEventFlags(rawValue: flags)
            deliver(event, to: destination, windowAware: true)

        case .mouseUp(let x, let y, let button, let clickCount, let flags):
            let type: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
            let cgButton: CGMouseButton = button == .left ? .left : .right
            guard let event = CGEvent(
                mouseEventSource: nil,
                mouseType: type,
                mouseCursorPosition: CGPoint(x: x, y: y),
                mouseButton: cgButton
            ) else { return }
            event.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            event.flags = CGEventFlags(rawValue: flags)
            deliver(event, to: destination, windowAware: true)

        case .mouseDrag(let x, let y, let button, let flags):
            let type: CGEventType = button == .left ? .leftMouseDragged : .rightMouseDragged
            let cgButton: CGMouseButton = button == .left ? .left : .right
            guard let event = CGEvent(
                mouseEventSource: nil,
                mouseType: type,
                mouseCursorPosition: CGPoint(x: x, y: y),
                mouseButton: cgButton
            ) else { return }
            event.flags = CGEventFlags(rawValue: flags)
            deliver(event, to: destination, windowAware: true)

        case .keyDown(let keyCode, let flags, let chars):
            guard let event = CGEvent(
                keyboardEventSource: nil,
                virtualKey: CGKeyCode(keyCode),
                keyDown: true
            ) else { return }
            if !chars.isEmpty {
                let utf16 = Array(chars.utf16)
                event.keyboardSetUnicodeString(
                    stringLength: utf16.count,
                    unicodeString: utf16
                )
            }
            event.flags = CGEventFlags(rawValue: flags)
            deliver(event, to: destination)

        case .keyUp(let keyCode, let flags):
            guard let event = CGEvent(
                keyboardEventSource: nil,
                virtualKey: CGKeyCode(keyCode),
                keyDown: false
            ) else { return }
            event.flags = CGEventFlags(rawValue: flags)
            deliver(event, to: destination)

        case .scroll(let x, let y, let dx, let dy, let flags):
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: scrollDelta(dy),
                wheel2: scrollDelta(dx),
                wheel3: 0
            ) else { return }
            event.location = CGPoint(x: x, y: y)
            event.flags = CGEventFlags(rawValue: flags)
            deliver(event, to: destination, windowAware: true)
        }
    }
}

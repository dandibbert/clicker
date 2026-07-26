import CoreGraphics
import ClickerCore

/// StepAction → CGEvent.post。所有事件带 syntheticMarker，避免被录制引擎捕获。
enum EventPoster {
    private static func mark(_ e: CGEvent) {
        e.setIntegerValueField(.eventSourceUserData, value: EventRecorder.syntheticMarker)
    }

    static func post(_ action: StepAction) {
        switch action {
        case .mouseMove(let x, let y):
            guard let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                  mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
            else { return }
            mark(e); e.post(tap: .cghidEventTap)

        case .mouseDown(let x, let y, let button, let clickCount):
            let type: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
            let cgButton: CGMouseButton = button == .left ? .left : .right
            guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: cgButton)
            else { return }
            e.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            mark(e); e.post(tap: .cghidEventTap)

        case .mouseUp(let x, let y, let button):
            let type: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
            let cgButton: CGMouseButton = button == .left ? .left : .right
            guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: cgButton)
            else { return }
            mark(e); e.post(tap: .cghidEventTap)

        case .mouseDrag(let x, let y, let button):
            let type: CGEventType = button == .left ? .leftMouseDragged : .rightMouseDragged
            let cgButton: CGMouseButton = button == .left ? .left : .right
            guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: cgButton)
            else { return }
            mark(e); e.post(tap: .cghidEventTap)

        case .keyDown(let keyCode, let flags, let chars):
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode),
                                  keyDown: true) else { return }
            if keyCode == 0 && !chars.isEmpty {
                // unicode 注入路径（编辑过的文本）
                let utf16 = Array(chars.utf16)
                e.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            }
            e.flags = CGEventFlags(rawValue: flags)
            mark(e); e.post(tap: .cghidEventTap)

        case .keyUp(let keyCode, let flags):
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode),
                                  keyDown: false) else { return }
            e.flags = CGEventFlags(rawValue: flags)
            mark(e); e.post(tap: .cghidEventTap)

        case .scroll(let dx, let dy):
            guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)
            else { return }
            mark(e); e.post(tap: .cghidEventTap)
        }
    }
}

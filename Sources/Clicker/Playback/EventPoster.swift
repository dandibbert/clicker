import CoreGraphics
import ClickerCore

/// StepAction → CGEvent.post。所有事件带 syntheticMarker，避免被录制引擎捕获。
enum EventPoster {
    static func scrollDelta(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        let truncated = value.rounded(.towardZero)
        if truncated >= Double(Int32.max) { return Int32.max }
        if truncated <= Double(Int32.min) { return Int32.min }
        return Int32(truncated)
    }

    private static func mark(_ e: CGEvent) {
        e.setIntegerValueField(.eventSourceUserData, value: EventRecorder.syntheticMarker)
    }

    static func post(_ action: StepAction) {
        switch action {
        case .mouseMove(let x, let y, let flags):
            guard let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                  mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
            else { return }
            e.flags = CGEventFlags(rawValue: flags)
            mark(e); e.post(tap: .cghidEventTap)

        case .mouseDown(let x, let y, let button, let clickCount, let flags):
            let type: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
            let cgButton: CGMouseButton = button == .left ? .left : .right
            guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: cgButton)
            else { return }
            e.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            e.flags = CGEventFlags(rawValue: flags)
            mark(e); e.post(tap: .cghidEventTap)

        case .mouseUp(let x, let y, let button, let clickCount, let flags):
            let type: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
            let cgButton: CGMouseButton = button == .left ? .left : .right
            guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: cgButton)
            else { return }
            e.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            e.flags = CGEventFlags(rawValue: flags)
            mark(e); e.post(tap: .cghidEventTap)

        case .mouseDrag(let x, let y, let button, let flags):
            let type: CGEventType = button == .left ? .leftMouseDragged : .rightMouseDragged
            let cgButton: CGMouseButton = button == .left ? .left : .right
            guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: cgButton)
            else { return }
            e.flags = CGEventFlags(rawValue: flags)
            mark(e); e.post(tap: .cghidEventTap)

        case .keyDown(let keyCode, let flags, let chars):
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode),
                                  keyDown: true) else { return }
            if !chars.isEmpty {
                // unicode 注入路径：keyboardSetUnicodeString 覆盖字符解释但保留 keyCode，
                // 录制的字符（含大小写、移位符号）按原样重放。
                // 快捷键块 chars 为 ""，保持纯虚拟键行为。
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

        case .scroll(let x, let y, let dx, let dy, let flags):
            guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: scrollDelta(dy), wheel2: scrollDelta(dx), wheel3: 0)
            else { return }
            e.location = CGPoint(x: x, y: y)
            e.flags = CGEventFlags(rawValue: flags)
            mark(e); e.post(tap: .cghidEventTap)
        }
    }
}

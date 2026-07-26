import CoreGraphics
import AppKit
import ClickerCore

/// CGEventTap 监听（listenOnly），把系统事件转成 RecordedEvent。
final class EventRecorder {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var startTime: CFAbsoluteTime = 0
    private(set) var events: [RecordedEvent] = []
    /// tap 被系统禁用且重建失败时回调（主线程）。
    var onTapFailure: (() -> Void)?

    var isRunning: Bool { tap != nil }

    /// 回放期间发出的合成事件带此标记，录制时跳过（防自录）。
    static let syntheticMarker: Int64 = 0x434C4B52  // "CLKR"

    func start() -> Bool {
        events = []
        startTime = CFAbsoluteTimeGetCurrent()

        // 注：原为一条 11 项按位或的长表达式，Swift 编译器类型检查超时，
        // 改为等价的 reduce 形式（语义完全一致）。
        let maskTypes: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .scrollWheel,
            .keyDown, .keyUp, .flagsChanged,
        ]
        let mask: CGEventMask = maskTypes.reduce(CGEventMask(0)) { acc, type in
            acc | (CGEventMask(1) << CGEventMask(type.rawValue))
        }

        let callback: CGEventTapCallBack = { _, type, cgEvent, refcon in
            let recorder = Unmanaged<EventRecorder>.fromOpaque(refcon!).takeUnretainedValue()
            recorder.handle(type: type, cgEvent: cgEvent)
            return Unmanaged.passUnretained(cgEvent)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() -> [RecordedEvent] {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        runLoopSource = nil
        return events
    }

    private func handle(type: CGEventType, cgEvent: CGEvent) {
        // tap 被系统禁用（超时/权限变化）：尝试重启，并确认重启成功
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
                if !CGEvent.tapIsEnabled(tap: tap) {
                    DispatchQueue.main.async { [weak self] in self?.onTapFailure?() }
                }
            } else {
                DispatchQueue.main.async { [weak self] in self?.onTapFailure?() }
            }
            return
        }
        // 跳过回放引擎发出的合成事件
        if cgEvent.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker { return }

        let t = CFAbsoluteTimeGetCurrent() - startTime
        let loc = cgEvent.location
        let kind: EventKind
        switch type {
        case .mouseMoved: kind = .mouseMove
        case .leftMouseDown: kind = .leftDown
        case .leftMouseUp: kind = .leftUp
        case .leftMouseDragged: kind = .leftDrag
        case .rightMouseDown: kind = .rightDown
        case .rightMouseUp: kind = .rightUp
        case .rightMouseDragged: kind = .rightDrag
        case .scrollWheel: kind = .scroll
        case .keyDown: kind = .keyDown
        case .keyUp: kind = .keyUp
        case .flagsChanged: kind = .flagsChanged
        default: return
        }

        var chars = ""
        var keyCode: UInt16 = 0
        if kind == .keyDown || kind == .keyUp || kind == .flagsChanged {
            keyCode = UInt16(cgEvent.getIntegerValueField(.keyboardEventKeycode))
            if kind == .keyDown {
                var length = 0
                var buffer = [UniChar](repeating: 0, count: 4)
                cgEvent.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length,
                                                 unicodeString: &buffer)
                chars = String(utf16CodeUnits: buffer, count: length)
                // 过滤控制字符（回车、删除等本身有 keyCode，不需要 chars）
                chars = chars.filter { ch in
                    if ch.isNewline { return false }
                    if let ascii = ch.asciiValue, ascii < 32 || ascii == 127 { return false }
                    return true
                }
            }
        }

        events.append(RecordedEvent(
            t: t, kind: kind, x: loc.x, y: loc.y,
            keyCode: keyCode, flags: cgEvent.flags.rawValue, chars: chars,
            clickCount: Int(cgEvent.getIntegerValueField(.mouseEventClickState)),
            scrollDX: Double(cgEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)),
            scrollDY: Double(cgEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        ))
    }
}

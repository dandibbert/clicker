import CoreGraphics
import AppKit
import ClickerCore

/// CGEventTap 监听（listenOnly），把系统事件转成 RecordedEvent。
final class EventRecorder {
    private let eventTap: EventTapSession
    private let timestampNow: () -> CGEventTimestamp
    private let timestampInterval: (CGEventTimestamp, CGEventTimestamp) -> TimeInterval
    private var startTimestamp: CGEventTimestamp?
    private(set) var events: [RecordedEvent] = []
    /// tap 被系统禁用且重建失败时回调（主线程）。
    var onTapFailure: (() -> Void)?

    var isRunning: Bool { eventTap.isRunning }

    /// 回放期间发出的合成事件带此标记，录制时跳过（防自录）。
    static let syntheticMarker: Int64 = 0x434C4B52  // "CLKR"

    init(
        eventTap: EventTapSession = CoreGraphicsEventTapSession(),
        timestampNow: @escaping () -> CGEventTimestamp = {
            clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        },
        elapsedTime: @escaping (CGEventTimestamp, CGEventTimestamp) -> TimeInterval = {
            start, end in
            guard end >= start else { return 0 }
            return TimeInterval(end - start) / 1_000_000_000
        }
    ) {
        self.eventTap = eventTap
        self.timestampNow = timestampNow
        timestampInterval = elapsedTime
    }

    func start() -> Bool {
        events = []
        let start = timestampNow()
        guard eventTap.start(handler: { [weak self] type, event in
            self?.handle(type: type, cgEvent: event)
        }) else {
            startTimestamp = nil
            return false
        }
        startTimestamp = start
        return true
    }

    func stop() -> RecordingCapture {
        let end = timestampNow()
        eventTap.stop()
        defer { startTimestamp = nil }
        return RecordingCapture(
            events: events,
            duration: elapsedTime(at: end)
        )
    }

    private func handle(type: CGEventType, cgEvent: CGEvent) {
        // tap 被系统禁用（超时/权限变化）：尝试重启，并确认重启成功
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if !eventTap.reenable() {
                DispatchQueue.main.async { [weak self] in self?.onTapFailure?() }
            }
            return
        }
        // 跳过回放引擎发出的合成事件
        if cgEvent.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker { return }

        let t = elapsedTime(at: cgEvent.timestamp)
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
            scrollDY: Double(cgEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)),
            isRepeat: kind == .keyDown
                && cgEvent.getIntegerValueField(.keyboardEventAutorepeat) != 0
        ))
    }

    private func elapsedTime(at timestamp: CGEventTimestamp) -> TimeInterval {
        guard let startTimestamp, timestamp >= startTimestamp else { return 0 }
        return timestampInterval(startTimestamp, timestamp)
    }
}

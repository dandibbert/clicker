import CoreGraphics
import AppKit
import ClickerCore

/// CGEventTap 监听（listenOnly），把系统事件转成 RecordedEvent。
final class EventRecorder: EventRecording {
    private let eventTap: EventTapSession
    private let stopHotKey: RecordingStopHotKeyMonitoring
    private let hasListenAccess: () -> Bool
    private let requestListenAccess: () -> Bool
    private let timestampNow: () -> CGEventTimestamp
    private let timestampInterval: (CGEventTimestamp, CGEventTimestamp) -> TimeInterval
    private var startTimestamp: CGEventTimestamp?
    private var stopShortcut: RecordingStopShortcut?
    private var stopRequested = false
    private(set) var events: [RecordedEvent] = []
    /// tap 被系统禁用且重建失败时回调（主线程）。
    var onTapFailure: (() -> Void)?
    /// 用户按下录制停止手势时请求结束当前录制（主线程）。
    var onStopRequest: (() -> Void)?

    var isRunning: Bool { eventTap.isRunning }

    /// 回放期间发出的合成事件带此标记，录制时跳过（防自录）。
    static let syntheticMarker: Int64 = 0x434C4B52  // "CLKR"

    init(
        eventTap: EventTapSession = CoreGraphicsEventTapSession(),
        stopHotKey: RecordingStopHotKeyMonitoring = CarbonRecordingStopHotKeyMonitor(),
        hasListenAccess: @escaping () -> Bool = CGPreflightListenEventAccess,
        requestListenAccess: @escaping () -> Bool = CGRequestListenEventAccess,
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
        self.stopHotKey = stopHotKey
        self.hasListenAccess = hasListenAccess
        self.requestListenAccess = requestListenAccess
        self.timestampNow = timestampNow
        timestampInterval = elapsedTime
    }

    func start(stopShortcut: RecordingStopShortcut) -> Bool {
        events = []
        stopRequested = false
        self.stopShortcut = nil
        stopHotKey.stop()
        guard !eventTap.requiresListenAccess || hasListenAccess() || requestListenAccess() else {
            startTimestamp = nil
            return false
        }
        let start = timestampNow()
        guard eventTap.start(handler: { [weak self] type, event in
            self?.handle(type: type, cgEvent: event)
        }) else {
            startTimestamp = nil
            return false
        }
        self.stopShortcut = stopShortcut
        startTimestamp = start
        _ = stopHotKey.start(shortcut: stopShortcut) { [weak self] in
            self?.requestStop()
        }
        return true
    }

    func stop() -> RecordingCapture {
        let end = timestampNow()
        stopHotKey.stop()
        eventTap.stop()
        defer { startTimestamp = nil }
        return RecordingCapture(
            events: events,
            duration: elapsedTime(at: end)
        )
    }

    func cutoff(at timestamp: CGEventTimestamp) -> RecordingCutoff {
        let duration = elapsedTime(at: timestamp)
        let eventCount = events.prefix { event in
            event.t < duration
        }.count
        return RecordingCutoff(eventCount: eventCount, duration: duration)
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
        if stopRequested { return }
        if type == .keyDown,
           let stopShortcut,
           stopShortcut.matches(
                keyCode: UInt16(cgEvent.getIntegerValueField(.keyboardEventKeycode)),
                flags: cgEvent.flags.rawValue
           ) {
            requestStop()
            return
        }

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
                chars = Self.unicodeString(from: cgEvent)
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

    private static func unicodeString(from event: CGEvent) -> String {
        // actualStringLength reports the event's full length, even when no buffer
        // is supplied. Query first so multi-unit input is not truncated.
        var requiredLength = 0
        event.keyboardGetUnicodeString(
            maxStringLength: 0,
            actualStringLength: &requiredLength,
            unicodeString: nil
        )
        guard requiredLength > 0 else { return "" }

        var buffer = [UniChar](repeating: 0, count: requiredLength)
        var actualLength = 0
        buffer.withUnsafeMutableBufferPointer { units in
            event.keyboardGetUnicodeString(
                maxStringLength: units.count,
                actualStringLength: &actualLength,
                unicodeString: units.baseAddress
            )
        }
        // The reported length is not a promise that this many units were copied.
        // Only decode units inside the supplied buffer, including if it changed.
        let copiedLength = min(buffer.count, max(0, actualLength))
        return String(decoding: buffer.prefix(copiedLength), as: UTF16.self)
    }

    private func elapsedTime(at timestamp: CGEventTimestamp) -> TimeInterval {
        guard let startTimestamp, timestamp >= startTimestamp else { return 0 }
        return timestampInterval(startTimestamp, timestamp)
    }

    private func requestStop() {
        guard !stopRequested else { return }
        stopRequested = true
        DispatchQueue.main.async { [weak self] in self?.onStopRequest?() }
    }
}

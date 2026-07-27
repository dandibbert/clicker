import Foundation

/// 录制停止时的尾部清理。纯函数。
public enum TailTrimmer {
    private static let maximumTimelineTime = Double(Int64.max) / 1_000_000_000 - 1

    /// 剔除停止快捷键产生的按键事件。兼容旧数组调用方。
    public static func trimHotKeyStop(
        _ events: [RecordedEvent],
        stopKeyCode: UInt16,
        stopFlags: UInt64
    ) -> [RecordedEvent] {
        trimHotKeyStop(
            RecordingCapture(events: events, duration: events.last?.t ?? 0),
            stopKeyCode: stopKeyCode,
            stopFlags: stopFlags
        ).events
    }

    public static func trimHotKeyStop(
        _ capture: RecordingCapture,
        stopKeyCode: UInt16,
        stopFlags: UInt64
    ) -> RecordingCapture {
        guard !capture.events.isEmpty else { return capture }

        var cursor = capture.events.count - 1
        while cursor >= 0, capture.events[cursor].kind == .flagsChanged {
            cursor -= 1
        }

        if cursor >= 0,
           capture.events[cursor].kind == .keyUp,
           capture.events[cursor].keyCode == stopKeyCode {
            cursor -= 1
            while cursor >= 0, capture.events[cursor].kind == .flagsChanged {
                cursor -= 1
            }
        }

        guard cursor >= 0 else { return capture }
        let stopKeyDown = capture.events[cursor]
        guard stopKeyDown.kind == .keyDown,
              stopKeyDown.keyCode == stopKeyCode,
              stopKeyDown.flags & stopFlags == stopFlags else {
            return capture
        }

        var sequenceStart = cursor
        while sequenceStart > 0 {
            let precedingEvent = capture.events[sequenceStart - 1]
            guard precedingEvent.kind == .flagsChanged,
                  isStopModifierEvent(precedingEvent, stopFlags: stopFlags) else {
                break
            }
            sequenceStart -= 1
        }

        return RecordingCapture(
            events: Array(capture.events.prefix(sequenceStart)),
            duration: sanitizedDuration(capture.events[sequenceStart].t)
        )
    }

    public static func trim(
        _ capture: RecordingCapture,
        at cutoff: RecordingCutoff
    ) -> RecordingCapture {
        let eventCount = min(max(0, cutoff.eventCount), capture.events.count)
        return RecordingCapture(
            events: Array(capture.events.prefix(eventCount)),
            duration: sanitizedDuration(cutoff.duration)
        )
    }

    /// 剔除点击菜单栏停止的尾部动作：最后一次 leftDown..leftUp 及其前面紧邻的连续 mouseMove。
    public static func trimMenuBarStop(_ events: [RecordedEvent]) -> [RecordedEvent] {
        var result = events
        guard result.count >= 2,
              result[result.count - 1].kind == .leftUp,
              result[result.count - 2].kind == .leftDown else {
            return result
        }
        result.removeLast(2)
        while let last = result.last, last.kind == .mouseMove {
            result.removeLast()
        }
        return result
    }

    private static func isStopModifierEvent(
        _ event: RecordedEvent,
        stopFlags: UInt64
    ) -> Bool {
        guard stopFlags != 0 else { return false }
        if event.flags & stopFlags != 0 {
            return true
        }
        return modifierMask(for: event.keyCode) & stopFlags != 0
    }

    private static func modifierMask(for keyCode: UInt16) -> UInt64 {
        switch keyCode {
        case 54, 55:
            return KeyCodeMap.maskCommand
        case 56, 60:
            return KeyCodeMap.maskShift
        case 58, 61:
            return KeyCodeMap.maskOption
        case 59, 62:
            return KeyCodeMap.maskControl
        default:
            return 0
        }
    }

    private static func sanitizedDuration(_ duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(duration, maximumTimelineTime)
    }
}

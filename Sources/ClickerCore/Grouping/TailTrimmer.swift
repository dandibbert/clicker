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
        }

        var sequenceStart: Int?
        var foundStopKeyDown = false
        while cursor >= 0 {
            let event = capture.events[cursor]
            if event.kind == .keyDown,
               event.keyCode == stopKeyCode,
               event.flags & stopFlags == stopFlags {
                foundStopKeyDown = true
                sequenceStart = cursor
                cursor -= 1
                continue
            }
            if foundStopKeyDown,
               event.kind == .keyUp,
               event.keyCode == stopKeyCode {
                cursor -= 1
                continue
            }
            if event.kind == .flagsChanged,
               !foundStopKeyDown || event.flags & stopFlags != 0 {
                sequenceStart = cursor
                cursor -= 1
                continue
            }
            break
        }

        guard foundStopKeyDown, let sequenceStart else { return capture }
        return RecordingCapture(
            events: Array(capture.events.prefix(sequenceStart)),
            duration: capture.duration
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

    private static func sanitizedDuration(_ duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite, duration > 0 else { return 0 }
        return min(duration, maximumTimelineTime)
    }
}

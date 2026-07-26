import Foundation

/// 录制停止时的尾部清理。纯函数。
public enum TailTrimmer {
    /// 剔除停止快捷键产生的按键事件：
    /// 从尾部向前，删除 keyCode 匹配的 keyDown/keyUp，以及它们之后/之间的 flagsChanged。
    public static func trimHotKeyStop(_ events: [RecordedEvent],
                                      stopKeyCode: UInt16,
                                      stopFlags: UInt64) -> [RecordedEvent] {
        var result = events
        // 尾部连续删除：匹配停止键的 keyDown/keyUp，或紧邻的 flagsChanged（修饰键按压过程）
        while let last = result.last {
            let isStopKey = (last.kind == .keyDown || last.kind == .keyUp) && last.keyCode == stopKeyCode
            let isModifierNoise = last.kind == .flagsChanged
            if isStopKey || isModifierNoise {
                result.removeLast()
            } else {
                break
            }
        }
        return result
    }

    /// 剔除点击菜单栏停止的尾部动作：最后一次 leftDown..leftUp 及其前面紧邻的连续 mouseMove。
    public static func trimMenuBarStop(_ events: [RecordedEvent]) -> [RecordedEvent] {
        var result = events
        // 尾部应为 ... mouseMove* leftDown leftUp
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
}

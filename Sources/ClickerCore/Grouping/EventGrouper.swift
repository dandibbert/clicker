import Foundation

/// 原始事件流 → 语义化动作块。纯函数，无系统依赖。
public enum EventGrouper {
    /// 无操作间隔阈值：≥ 此值产生独立 WaitBlock。
    public static let waitThreshold: TimeInterval = 0.5

    public static func group(_ events: [RecordedEvent]) -> [ActionBlock] {
        var blocks: [ActionBlock] = []
        var i = 0
        // 上一个已消费事件的时间，用于插入 wait
        var lastT: TimeInterval? = nil

        func insertWaitIfNeeded(before t: TimeInterval) {
            if let last = lastT, t - last >= waitThreshold {
                blocks.append(.wait(WaitBlock(duration: t - last)))
            }
        }

        while i < events.count {
            let e = events[i]

            switch e.kind {
            case .flagsChanged:
                // 纯修饰键按压不生成块，也不推进 lastT（避免打断 wait 计算）
                i += 1

            case .mouseMove:
                insertWaitIfNeeded(before: e.t)
                // 收集连续 move（中间间隔 < 阈值）
                var pts: [TrackPoint] = []
                let start = e.t
                var j = i
                var prevT = e.t
                while j < events.count, events[j].kind == .mouseMove,
                      events[j].t - prevT < waitThreshold {
                    pts.append(TrackPoint(t: events[j].t - start, x: events[j].x, y: events[j].y))
                    prevT = events[j].t
                    j += 1
                }
                blocks.append(.move(MoveBlock(duration: prevT - start, points: pts)))
                lastT = prevT
                i = j

            case .leftDown, .rightDown:
                insertWaitIfNeeded(before: e.t)
                let button: MouseButton = e.kind == .leftDown ? .left : .right
                let upKind: EventKind = button == .left ? .leftUp : .rightUp
                let dragKind: EventKind = button == .left ? .leftDrag : .rightDrag
                // 向后找对应 up，收集中间 drag
                var pts: [TrackPoint] = [TrackPoint(t: 0, x: e.x, y: e.y)]
                var j = i + 1
                var sawDrag = false
                var endT = e.t
                var matched = false
                while j < events.count {
                    let n = events[j]
                    if n.kind == dragKind {
                        sawDrag = true
                        pts.append(TrackPoint(t: n.t - e.t, x: n.x, y: n.y))
                        j += 1
                    } else if n.kind == upKind {
                        pts.append(TrackPoint(t: n.t - e.t, x: n.x, y: n.y))
                        endT = n.t
                        matched = true
                        j += 1
                        break
                    } else {
                        break  // 中间夹了别的事件：截断，按已收集内容出块
                    }
                }
                if sawDrag {
                    blocks.append(.drag(DragBlock(button: button, duration: endT - e.t, points: pts)))
                } else {
                    blocks.append(.click(ClickBlock(x: e.x, y: e.y, button: button,
                                                    clickCount: max(1, e.clickCount))))
                }
                lastT = matched ? endT : e.t
                i = j

            case .leftUp, .rightUp, .leftDrag, .rightDrag:
                // 孤立 up/drag（正常流程已被 down 分支消费）：跳过
                i += 1

            case .scroll:
                insertWaitIfNeeded(before: e.t)
                var steps: [ScrollStep] = []
                let start = e.t
                var prevT = e.t
                var j = i
                while j < events.count, events[j].kind == .scroll,
                      events[j].t - prevT < waitThreshold {
                    steps.append(ScrollStep(t: events[j].t - start,
                                            dx: events[j].scrollDX, dy: events[j].scrollDY))
                    prevT = events[j].t
                    j += 1
                }
                blocks.append(.scroll(ScrollBlock(x: e.x, y: e.y, duration: prevT - start, steps: steps)))
                lastT = prevT
                i = j

            case .keyDown:
                insertWaitIfNeeded(before: e.t)
                let modifiers = e.flags & (KeyCodeMap.maskCommand | KeyCodeMap.maskControl | KeyCodeMap.maskOption)
                if modifiers != 0 {
                    // 快捷键块（⌘/⌃/⌥；纯 Shift 属于打字）
                    blocks.append(.shortcut(ShortcutBlock(keyCode: e.keyCode, flags: e.flags)))
                    // 吞掉对应 keyUp
                    var j = i + 1
                    var endT = e.t
                    if j < events.count, events[j].kind == .keyUp, events[j].keyCode == e.keyCode {
                        endT = events[j].t
                        j += 1
                    }
                    lastT = endT
                    i = j
                } else {
                    // 连续打字：收集后续无修饰 keyDown（间隔 < 阈值），跳过夹在中间的 keyUp
                    var keystrokes: [Keystroke] = []
                    var text = ""
                    let start = e.t
                    var prevT = e.t
                    var j = i
                    loop: while j < events.count {
                        let n = events[j]
                        switch n.kind {
                        case .keyDown:
                            let mods = n.flags & (KeyCodeMap.maskCommand | KeyCodeMap.maskControl | KeyCodeMap.maskOption)
                            guard mods == 0, n.t - prevT < waitThreshold else { break loop }
                            keystrokes.append(Keystroke(t: n.t - start, keyCode: n.keyCode, chars: n.chars))
                            text += n.chars
                            prevT = n.t
                            j += 1
                        case .keyUp, .flagsChanged:
                            guard n.t - prevT < waitThreshold else { break loop }
                            prevT = n.t
                            j += 1
                        default:
                            break loop
                        }
                    }
                    blocks.append(.typeText(TypeTextBlock(text: text, keystrokes: keystrokes)))
                    lastT = prevT
                    i = j
                }

            case .keyUp:
                // 孤立 keyUp：跳过
                i += 1
            }
        }
        return blocks
    }
}

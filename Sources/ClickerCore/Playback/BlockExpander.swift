import Foundation

/// 动作块 → 回放步骤序列。纯函数。
public enum BlockExpander {
    /// 点击 down→up 的间隔。
    static let clickHold: TimeInterval = 0.03
    /// 打字每字符 down→up 的间隔与字符间步进（keystrokes 缺失时序时使用）。
    static let keyHold: TimeInterval = 0.02
    static let keyStride: TimeInterval = 0.06

    public static func expand(_ blocks: [ActionBlock]) -> [PlaybackStep] {
        var steps: [PlaybackStep] = []
        var clock: TimeInterval = 0

        for block in blocks {
            switch block {
            case .wait(let w):
                clock += w.duration

            case .move(let m):
                for p in m.points {
                    steps.append(PlaybackStep(t: clock + p.t,
                                              action: .mouseMove(x: p.x, y: p.y), blockID: m.id))
                }
                clock += m.duration

            case .click(let c):
                steps.append(PlaybackStep(t: clock,
                    action: .mouseDown(x: c.x, y: c.y, button: c.button, clickCount: c.clickCount),
                    blockID: c.id))
                steps.append(PlaybackStep(t: clock + clickHold,
                    action: .mouseUp(x: c.x, y: c.y, button: c.button), blockID: c.id))
                clock += clickHold

            case .drag(let d):
                guard let first = d.points.first, let last = d.points.last else { break }
                steps.append(PlaybackStep(t: clock + first.t,
                    action: .mouseDown(x: first.x, y: first.y, button: d.button, clickCount: 1),
                    blockID: d.id))
                for p in d.points.dropFirst().dropLast() {
                    steps.append(PlaybackStep(t: clock + p.t,
                        action: .mouseDrag(x: p.x, y: p.y, button: d.button), blockID: d.id))
                }
                steps.append(PlaybackStep(t: clock + last.t,
                    action: .mouseUp(x: last.x, y: last.y, button: d.button), blockID: d.id))
                clock += d.duration

            case .scroll(let s):
                for step in s.steps {
                    steps.append(PlaybackStep(t: clock + step.t,
                        action: .scroll(dx: step.dx, dy: step.dy), blockID: s.id))
                }
                clock += s.duration

            case .typeText(let t):
                let recordedText = t.keystrokes.map(\.chars).joined()
                if recordedText == t.text, !t.keystrokes.isEmpty {
                    // 未被编辑：按原始时序重放 keyCode
                    for k in t.keystrokes {
                        steps.append(PlaybackStep(t: clock + k.t,
                            action: .keyDown(keyCode: k.keyCode, flags: 0, chars: k.chars),
                            blockID: t.id))
                        steps.append(PlaybackStep(t: clock + k.t + keyHold,
                            action: .keyUp(keyCode: k.keyCode, flags: 0), blockID: t.id))
                    }
                    clock += (t.keystrokes.last?.t ?? 0) + keyHold
                } else {
                    // 编辑过：逐字符 unicode 注入（keyCode 0 + chars，由 EventPoster 走 unicode 路径）
                    var offset: TimeInterval = 0
                    for ch in t.text {
                        steps.append(PlaybackStep(t: clock + offset,
                            action: .keyDown(keyCode: 0, flags: 0, chars: String(ch)), blockID: t.id))
                        steps.append(PlaybackStep(t: clock + offset + keyHold,
                            action: .keyUp(keyCode: 0, flags: 0), blockID: t.id))
                        offset += keyStride
                    }
                    clock += offset
                }

            case .shortcut(let s):
                steps.append(PlaybackStep(t: clock,
                    action: .keyDown(keyCode: s.keyCode, flags: s.flags, chars: ""), blockID: s.id))
                steps.append(PlaybackStep(t: clock + keyHold,
                    action: .keyUp(keyCode: s.keyCode, flags: s.flags), blockID: s.id))
                clock += keyHold
            }
        }
        return steps
    }
}

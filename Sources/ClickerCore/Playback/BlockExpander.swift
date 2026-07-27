import Foundation

/// 动作块 → 回放时间轴。纯函数。
public enum BlockExpander {
    /// 编辑文本生成事件时，字符按下到抬起的间隔。
    static let keyHold: TimeInterval = 0.02
    /// 编辑文本生成事件时，相邻字符按下的间隔。
    static let keyStride: TimeInterval = 0.06

    private static func clampedDuration(_ duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite, duration > 0 else { return 0 }
        return duration
    }

    /// 兼容旧调用方，只返回投递步骤。
    public static func expand(_ blocks: [ActionBlock]) -> [PlaybackStep] {
        plan(blocks: blocks).steps
    }

    public static func plan(for script: Script) -> PlaybackPlan {
        plan(blocks: script.blocks, trailingDelay: script.trailingDelay)
    }

    public static func plan(
        blocks: [ActionBlock],
        trailingDelay: TimeInterval = 0
    ) -> PlaybackPlan {
        var steps: [PlaybackStep] = []
        var clock: TimeInterval = 0

        for block in blocks {
            if case .wait(let wait) = block {
                clock += clampedDuration(wait.duration)
                continue
            }

            clock += clampedDuration(block.delayBefore)
            let start = clock
            var effectiveDuration = clampedDuration(block.duration)

            switch block {
            case .wait:
                break

            case .move(let move):
                for point in move.points {
                    steps.append(PlaybackStep(
                        t: start + point.t,
                        action: .mouseMove(x: point.x, y: point.y, flags: point.flags),
                        blockID: move.id
                    ))
                }

            case .click(let click):
                steps.append(PlaybackStep(
                    t: start,
                    action: .mouseDown(
                        x: click.x,
                        y: click.y,
                        button: click.button,
                        clickCount: click.clickCount,
                        flags: click.downFlags
                    ),
                    blockID: click.id
                ))
                steps.append(PlaybackStep(
                    t: start + effectiveDuration,
                    action: .mouseUp(
                        x: click.upX,
                        y: click.upY,
                        button: click.button,
                        flags: click.upFlags
                    ),
                    blockID: click.id
                ))

            case .drag(let drag):
                if let first = drag.points.first, let last = drag.points.last {
                    steps.append(PlaybackStep(
                        t: start + first.t,
                        action: .mouseDown(
                            x: first.x,
                            y: first.y,
                            button: drag.button,
                            clickCount: 1,
                            flags: first.flags
                        ),
                        blockID: drag.id
                    ))
                    for point in drag.points.dropFirst().dropLast() {
                        steps.append(PlaybackStep(
                            t: start + point.t,
                            action: .mouseDrag(
                                x: point.x,
                                y: point.y,
                                button: drag.button,
                                flags: point.flags
                            ),
                            blockID: drag.id
                        ))
                    }
                    steps.append(PlaybackStep(
                        t: start + last.t,
                        action: .mouseUp(
                            x: last.x,
                            y: last.y,
                            button: drag.button,
                            flags: last.flags
                        ),
                        blockID: drag.id
                    ))
                }

            case .scroll(let scroll):
                for step in scroll.steps {
                    steps.append(PlaybackStep(
                        t: start + step.t,
                        action: .scroll(
                            x: scroll.x,
                            y: scroll.y,
                            dx: step.dx,
                            dy: step.dy,
                            flags: step.flags
                        ),
                        blockID: scroll.id
                    ))
                }

            case .typeText(let typeText):
                let recordedText = typeText.keystrokes.map(\.chars).joined()
                if recordedText == typeText.text, !typeText.keystrokes.isEmpty {
                    for keystroke in typeText.keystrokes {
                        steps.append(PlaybackStep(
                            t: start + keystroke.t,
                            action: .keyDown(
                                keyCode: keystroke.keyCode,
                                flags: keystroke.downFlags,
                                chars: keystroke.chars
                            ),
                            blockID: typeText.id
                        ))
                        steps.append(PlaybackStep(
                            t: start + keystroke.upT,
                            action: .keyUp(
                                keyCode: keystroke.keyCode,
                                flags: keystroke.upFlags
                            ),
                            blockID: typeText.id
                        ))
                    }
                } else {
                    var offset: TimeInterval = 0
                    var generatedDuration: TimeInterval = 0
                    for character in typeText.text {
                        steps.append(PlaybackStep(
                            t: start + offset,
                            action: .keyDown(
                                keyCode: 0,
                                flags: 0,
                                chars: String(character)
                            ),
                            blockID: typeText.id
                        ))
                        steps.append(PlaybackStep(
                            t: start + offset + keyHold,
                            action: .keyUp(keyCode: 0, flags: 0),
                            blockID: typeText.id
                        ))
                        generatedDuration = offset + keyHold
                        offset += keyStride
                    }
                    effectiveDuration = max(effectiveDuration, generatedDuration)
                }

            case .shortcut(let shortcut):
                steps.append(PlaybackStep(
                    t: start,
                    action: .keyDown(
                        keyCode: shortcut.keyCode,
                        flags: shortcut.flags,
                        chars: ""
                    ),
                    blockID: shortcut.id
                ))
                steps.append(PlaybackStep(
                    t: start + effectiveDuration,
                    action: .keyUp(
                        keyCode: shortcut.keyCode,
                        flags: shortcut.upFlags
                    ),
                    blockID: shortcut.id
                ))
            }

            clock += effectiveDuration
        }

        let orderedSteps = steps.enumerated().sorted { lhs, rhs in
            if lhs.element.t == rhs.element.t {
                return lhs.offset < rhs.offset
            }
            return lhs.element.t < rhs.element.t
        }.map(\.element)

        return PlaybackPlan(
            steps: orderedSteps,
            duration: clock + clampedDuration(trailingDelay)
        )
    }
}

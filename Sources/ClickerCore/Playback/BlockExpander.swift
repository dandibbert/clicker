import Foundation

/// 动作块 → 回放时间轴。纯函数。
public enum BlockExpander {
    /// 编辑文本生成事件时，字符按下到抬起的间隔。
    static let keyHold: TimeInterval = 0.02
    /// 编辑文本生成事件时，相邻字符按下的间隔。
    static let keyStride: TimeInterval = 0.06

    /// 时间轴上限保留 1 秒余量，确保纳秒换算可安全落在 Int64 范围内。
    static let maximumTimelineTime = Double(Int64.max) / 1_000_000_000 - 1

    private static func sanitizedTime(_ time: TimeInterval) -> TimeInterval {
        guard time.isFinite, time > 0 else { return 0 }
        return min(time, maximumTimelineTime)
    }

    private static func adding(_ lhs: TimeInterval, _ rhs: TimeInterval) -> TimeInterval {
        let left = sanitizedTime(lhs)
        let right = sanitizedTime(rhs)
        guard left < maximumTimelineTime, right < maximumTimelineTime,
              left <= maximumTimelineTime - right else {
            return maximumTimelineTime
        }
        return left + right
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
                clock = adding(clock, wait.duration)
                continue
            }

            clock = adding(clock, block.delayBefore)
            let start = clock
            var effectiveDuration = sanitizedTime(block.duration)
            var latestLocalStep: TimeInterval = 0

            func appendStep(localTime: TimeInterval, action: StepAction, blockID: UUID) {
                let time = sanitizedTime(localTime)
                latestLocalStep = max(latestLocalStep, time)
                steps.append(PlaybackStep(
                    t: adding(start, time),
                    action: action,
                    blockID: blockID
                ))
            }

            switch block {
            case .wait:
                break

            case .move(let move):
                for point in move.points {
                    appendStep(
                        localTime: point.t,
                        action: .mouseMove(x: point.x, y: point.y, flags: point.flags),
                        blockID: move.id
                    )
                }

            case .click(let click):
                appendStep(
                    localTime: 0,
                    action: .mouseDown(
                        x: click.x,
                        y: click.y,
                        button: click.button,
                        clickCount: click.clickCount,
                        flags: click.downFlags
                    ),
                    blockID: click.id
                )
                appendStep(
                    localTime: effectiveDuration,
                    action: .mouseUp(
                        x: click.upX,
                        y: click.upY,
                        button: click.button,
                        clickCount: click.upClickCount,
                        flags: click.upFlags
                    ),
                    blockID: click.id
                )

            case .drag(let drag):
                if let first = drag.points.first, let last = drag.points.last {
                    var time = sanitizedTime(first.t)
                    appendStep(
                        localTime: time,
                        action: .mouseDown(
                            x: first.x,
                            y: first.y,
                            button: drag.button,
                            clickCount: 1,
                            flags: first.flags
                        ),
                        blockID: drag.id
                    )
                    for point in drag.points.dropFirst().dropLast() {
                        time = max(time, sanitizedTime(point.t))
                        appendStep(
                            localTime: time,
                            action: .mouseDrag(
                                x: point.x,
                                y: point.y,
                                button: drag.button,
                                flags: point.flags
                            ),
                            blockID: drag.id
                        )
                    }
                    time = max(time, sanitizedTime(last.t))
                    appendStep(
                        localTime: time,
                        action: .mouseUp(
                            x: last.x,
                            y: last.y,
                            button: drag.button,
                            clickCount: 1,
                            flags: last.flags
                        ),
                        blockID: drag.id
                    )
                }

            case .scroll(let scroll):
                for step in scroll.steps {
                    appendStep(
                        localTime: step.t,
                        action: .scroll(
                            x: scroll.x,
                            y: scroll.y,
                            dx: step.dx,
                            dy: step.dy,
                            flags: step.flags
                        ),
                        blockID: scroll.id
                    )
                }

            case .typeText(let typeText):
                let recordedText = typeText.keystrokes.map(\.chars).joined()
                if recordedText == typeText.text, !typeText.keystrokes.isEmpty {
                    for keystroke in typeText.keystrokes {
                        let downTime = sanitizedTime(keystroke.t)
                        let upTime = max(downTime, sanitizedTime(keystroke.upT))
                        appendStep(
                            localTime: downTime,
                            action: .keyDown(
                                keyCode: keystroke.keyCode,
                                flags: keystroke.downFlags,
                                chars: keystroke.chars
                            ),
                            blockID: typeText.id
                        )
                        appendStep(
                            localTime: upTime,
                            action: .keyUp(
                                keyCode: keystroke.keyCode,
                                flags: keystroke.upFlags
                            ),
                            blockID: typeText.id
                        )
                    }
                } else {
                    var offset: TimeInterval = 0
                    var generatedDuration: TimeInterval = 0
                    for character in typeText.text {
                        let upTime = adding(offset, keyHold)
                        appendStep(
                            localTime: offset,
                            action: .keyDown(
                                keyCode: 0,
                                flags: 0,
                                chars: String(character)
                            ),
                            blockID: typeText.id
                        )
                        appendStep(
                            localTime: upTime,
                            action: .keyUp(keyCode: 0, flags: 0),
                            blockID: typeText.id
                        )
                        generatedDuration = max(generatedDuration, upTime)
                        offset = adding(offset, keyStride)
                    }
                    effectiveDuration = max(effectiveDuration, generatedDuration)
                }

            case .shortcut(let shortcut):
                appendStep(
                    localTime: 0,
                    action: .keyDown(
                        keyCode: shortcut.keyCode,
                        flags: shortcut.flags,
                        chars: ""
                    ),
                    blockID: shortcut.id
                )
                appendStep(
                    localTime: effectiveDuration,
                    action: .keyUp(
                        keyCode: shortcut.keyCode,
                        flags: shortcut.upFlags
                    ),
                    blockID: shortcut.id
                )
            }

            effectiveDuration = max(effectiveDuration, latestLocalStep)
            clock = adding(clock, effectiveDuration)
        }

        let orderedSteps = steps.enumerated().sorted { lhs, rhs in
            if lhs.element.t == rhs.element.t {
                return lhs.offset < rhs.offset
            }
            return lhs.element.t < rhs.element.t
        }.map(\.element)

        return PlaybackPlan(
            steps: orderedSteps,
            duration: adding(clock, trailingDelay)
        )
    }
}

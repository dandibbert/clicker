import Foundation

/// 动作块 → 绝对回放时间轴。纯函数。
public enum BlockExpander {
    private struct KeyReleaseIdentity: Hashable {
        var t: TimeInterval
        var keyCode: UInt16
        var ordinal: Int
    }

    /// 编辑文本生成事件时，字符按下到抬起的间隔。
    static let keyHold: TimeInterval = 0.02
    /// 编辑文本生成事件时，相邻字符按下的间隔。
    static let keyStride: TimeInterval = 0.06

    private static func sanitizedTime(_ time: TimeInterval) -> TimeInterval {
        TimelineValue.time(time)
    }

    private static func adding(_ lhs: TimeInterval, _ rhs: TimeInterval) -> TimeInterval {
        TimelineValue.adding(lhs, rhs)
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
        var keyReleaseWasRepeat: [KeyReleaseIdentity: Bool] = [:]
        var timelineEnd: TimeInterval = 0

        for block in blocks {
            let start = sanitizedTime(block.startOffset)
            var effectiveDuration = sanitizedTime(block.duration)
            var latestLocalStep: TimeInterval = 0

            func appendStep(
                localTime: TimeInterval,
                ordinal: Int,
                action: StepAction,
                blockID: UUID
            ) {
                let time = sanitizedTime(localTime)
                latestLocalStep = max(latestLocalStep, time)
                steps.append(PlaybackStep(
                    t: adding(start, time),
                    action: action,
                    blockID: blockID,
                    ordinal: ordinal
                ))
            }

            func appendKeyRelease(
                localTime: TimeInterval,
                keyCode: UInt16,
                flags: UInt64,
                ordinal: Int,
                isRepeat: Bool,
                blockID: UUID
            ) {
                let time = sanitizedTime(localTime)
                latestLocalStep = max(latestLocalStep, time)
                let identity = KeyReleaseIdentity(
                    t: adding(start, time),
                    keyCode: keyCode,
                    ordinal: ordinal
                )
                if let existingWasRepeat = keyReleaseWasRepeat[identity],
                   existingWasRepeat || isRepeat {
                    return
                }
                keyReleaseWasRepeat[identity] = isRepeat
                steps.append(PlaybackStep(
                    t: identity.t,
                    action: .keyUp(keyCode: keyCode, flags: flags),
                    blockID: blockID,
                    ordinal: ordinal
                ))
            }

            switch block {
            case .wait:
                break

            case .move(let move):
                for point in move.points {
                    appendStep(
                        localTime: point.t,
                        ordinal: point.ordinal,
                        action: .mouseMove(x: point.x, y: point.y, flags: point.flags),
                        blockID: move.id
                    )
                }

            case .click(let click):
                appendStep(
                    localTime: 0,
                    ordinal: click.downOrdinal,
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
                    ordinal: click.upOrdinal,
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
                        ordinal: first.ordinal,
                        action: .mouseDown(
                            x: first.x,
                            y: first.y,
                            button: drag.button,
                            clickCount: 1,
                            flags: first.flags
                        ),
                        blockID: drag.id
                    )
                    let dragPoints = drag.hasRecordedMouseUp
                        ? drag.points.dropFirst().dropLast()
                        : drag.points.dropFirst()
                    for point in dragPoints {
                        time = max(time, sanitizedTime(point.t))
                        appendStep(
                            localTime: time,
                            ordinal: point.ordinal,
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
                        ordinal: drag.upOrdinal,
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
                    let location: (x: Double, y: Double)
                    if let x = step.x, let y = step.y {
                        location = (x, y)
                    } else {
                        location = (scroll.x, scroll.y)
                    }
                    appendStep(
                        localTime: step.t,
                        ordinal: step.ordinal,
                        action: .scroll(
                            x: location.x,
                            y: location.y,
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
                            ordinal: keystroke.downOrdinal,
                            action: .keyDown(
                                keyCode: keystroke.keyCode,
                                flags: keystroke.downFlags,
                                chars: keystroke.chars
                            ),
                            blockID: typeText.id
                        )
                        appendKeyRelease(
                            localTime: upTime,
                            keyCode: keystroke.keyCode,
                            flags: keystroke.upFlags,
                            ordinal: keystroke.upOrdinal,
                            isRepeat: keystroke.isRepeat,
                            blockID: typeText.id
                        )
                    }
                } else {
                    let existingOrdinals = typeText.keystrokes.flatMap {
                        [$0.downOrdinal, $0.upOrdinal]
                    }
                    var ordinal = existingOrdinals.max().map {
                        TimelineValue.nextOrdinal(after: $0)
                    } ?? 0
                    var offset: TimeInterval = 0
                    var generatedDuration: TimeInterval = 0
                    for character in typeText.text {
                        let upTime = adding(offset, keyHold)
                        appendStep(
                            localTime: offset,
                            ordinal: ordinal,
                            action: .keyDown(
                                keyCode: 0,
                                flags: 0,
                                chars: String(character)
                            ),
                            blockID: typeText.id
                        )
                        ordinal = TimelineValue.nextOrdinal(after: ordinal)
                        appendStep(
                            localTime: upTime,
                            ordinal: ordinal,
                            action: .keyUp(keyCode: 0, flags: 0),
                            blockID: typeText.id
                        )
                        ordinal = TimelineValue.nextOrdinal(after: ordinal)
                        generatedDuration = max(generatedDuration, upTime)
                        offset = adding(offset, keyStride)
                    }
                    effectiveDuration = max(effectiveDuration, generatedDuration)
                }

            case .shortcut(let shortcut):
                appendStep(
                    localTime: 0,
                    ordinal: shortcut.downOrdinal,
                    action: .keyDown(
                        keyCode: shortcut.keyCode,
                        flags: shortcut.flags,
                        chars: ""
                    ),
                    blockID: shortcut.id
                )
                appendKeyRelease(
                    localTime: effectiveDuration,
                    keyCode: shortcut.keyCode,
                    flags: shortcut.upFlags,
                    ordinal: shortcut.upOrdinal,
                    isRepeat: shortcut.isRepeat,
                    blockID: shortcut.id
                )
            }

            effectiveDuration = max(effectiveDuration, latestLocalStep)
            timelineEnd = max(timelineEnd, adding(start, effectiveDuration))
        }

        let orderedSteps = steps.enumerated().sorted { lhs, rhs in
            if lhs.element.t != rhs.element.t {
                return lhs.element.t < rhs.element.t
            }
            if lhs.element.ordinal != rhs.element.ordinal {
                return lhs.element.ordinal < rhs.element.ordinal
            }
            return lhs.offset < rhs.offset
        }.map(\.element)

        return PlaybackPlan(
            steps: orderedSteps,
            duration: adding(timelineEnd, trailingDelay)
        )
    }
}

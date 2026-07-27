import Foundation

/// 原始事件流 → 语义化动作块。纯函数，无系统依赖。
public enum EventGrouper {
    /// 无操作间隔阈值：≥ 此值产生独立 WaitBlock。
    public static let waitThreshold: TimeInterval = 0.5

    private static let maximumTimelineTime = Double(Int64.max) / 1_000_000_000 - 1
    private static let clickFallbackDuration: TimeInterval = 0.03
    private static let keyFallbackDuration: TimeInterval = 0.02

    /// 兼容旧调用方。旧 API 无法返回短尾部等待，因此只返回 blocks。
    public static func group(_ events: [RecordedEvent]) -> [ActionBlock] {
        let duration = events.last?.t ?? 0
        return group(RecordingCapture(events: events, duration: duration)).blocks
    }

    public static func group(_ capture: RecordingCapture) -> GroupedTimeline {
        let events = capture.events
        var blocks: [ActionBlock] = []
        var previousActionEnd: TimeInterval = 0
        var index = 0

        func appendAction(_ block: ActionBlock, start: TimeInterval, end: TimeInterval) {
            let actionStart = sanitizedTime(start)
            let actionEnd = max(actionStart, sanitizedTime(end))
            let gap = elapsed(from: previousActionEnd, to: actionStart)

            if gap >= waitThreshold {
                blocks.append(.wait(WaitBlock(duration: gap)))
                blocks.append(block.withDelayBefore(0))
            } else {
                blocks.append(block.withDelayBefore(gap))
            }
            previousActionEnd = max(previousActionEnd, actionEnd)
        }

        while index < events.count {
            let event = events[index]
            let start = sanitizedTime(event.t)

            switch event.kind {
            case .flagsChanged:
                index += 1

            case .mouseMove:
                var points: [TrackPoint] = []
                var nextIndex = index
                var previousPointTime = start
                var latestPointTime = start
                var latestLocalTime: TimeInterval = 0

                while nextIndex < events.count,
                      events[nextIndex].kind == .mouseMove {
                    let pointEvent = events[nextIndex]
                    let pointTime = sanitizedTime(pointEvent.t)
                    if nextIndex != index,
                       elapsed(from: previousPointTime, to: pointTime) >= waitThreshold {
                        break
                    }

                    let localTime = elapsed(from: start, to: pointTime)
                    points.append(TrackPoint(
                        t: localTime,
                        x: pointEvent.x,
                        y: pointEvent.y,
                        flags: pointEvent.flags
                    ))
                    latestLocalTime = max(latestLocalTime, localTime)
                    latestPointTime = max(latestPointTime, pointTime)
                    previousPointTime = pointTime
                    nextIndex += 1
                }

                appendAction(
                    .move(MoveBlock(duration: latestLocalTime, points: points)),
                    start: start,
                    end: latestPointTime
                )
                index = nextIndex

            case .leftDown, .rightDown:
                let button: MouseButton = event.kind == .leftDown ? .left : .right
                let upKind: EventKind = button == .left ? .leftUp : .rightUp
                let dragKind: EventKind = button == .left ? .leftDrag : .rightDrag
                var points = [TrackPoint(
                    t: 0,
                    x: event.x,
                    y: event.y,
                    flags: event.flags
                )]
                var nextIndex = index + 1
                var sawDrag = false
                var matchedUp: RecordedEvent?
                var latestSampleTime = start
                var latestLocalTime: TimeInterval = 0

                while nextIndex < events.count {
                    let nextEvent = events[nextIndex]
                    if nextEvent.kind == .flagsChanged {
                        nextIndex += 1
                        continue
                    }
                    if nextEvent.kind == dragKind {
                        sawDrag = true
                        let localTime = elapsed(
                            from: start,
                            to: sanitizedTime(nextEvent.t)
                        )
                        points.append(TrackPoint(
                            t: localTime,
                            x: nextEvent.x,
                            y: nextEvent.y,
                            flags: nextEvent.flags
                        ))
                        latestLocalTime = max(latestLocalTime, localTime)
                        latestSampleTime = max(
                            latestSampleTime,
                            sanitizedTime(nextEvent.t)
                        )
                        nextIndex += 1
                        continue
                    }
                    if nextEvent.kind == upKind {
                        let localTime = elapsed(
                            from: start,
                            to: sanitizedTime(nextEvent.t)
                        )
                        points.append(TrackPoint(
                            t: localTime,
                            x: nextEvent.x,
                            y: nextEvent.y,
                            flags: nextEvent.flags
                        ))
                        latestLocalTime = max(latestLocalTime, localTime)
                        latestSampleTime = max(
                            latestSampleTime,
                            sanitizedTime(nextEvent.t)
                        )
                        matchedUp = nextEvent
                        nextIndex += 1
                    }
                    break
                }

                if sawDrag {
                    appendAction(
                        .drag(DragBlock(
                            button: button,
                            duration: latestLocalTime,
                            points: points
                        )),
                        start: start,
                        end: latestSampleTime
                    )
                } else if let upEvent = matchedUp {
                    let duration = elapsed(
                        from: start,
                        to: sanitizedTime(upEvent.t)
                    )
                    appendAction(
                        .click(ClickBlock(
                            x: event.x,
                            y: event.y,
                            button: button,
                            clickCount: event.clickCount,
                            duration: duration,
                            upX: upEvent.x,
                            upY: upEvent.y,
                            upClickCount: upEvent.clickCount,
                            downFlags: event.flags,
                            upFlags: upEvent.flags
                        )),
                        start: start,
                        end: sanitizedTime(upEvent.t)
                    )
                } else {
                    appendAction(
                        .click(ClickBlock(
                            x: event.x,
                            y: event.y,
                            button: button,
                            clickCount: event.clickCount,
                            duration: clickFallbackDuration,
                            upX: event.x,
                            upY: event.y,
                            upClickCount: event.clickCount,
                            downFlags: event.flags,
                            upFlags: event.flags
                        )),
                        start: start,
                        end: adding(start, clickFallbackDuration)
                    )
                }
                index = nextIndex

            case .leftUp, .rightUp, .leftDrag, .rightDrag:
                index += 1

            case .scroll:
                var steps: [ScrollStep] = []
                var nextIndex = index
                var previousStepTime = start
                var latestStepTime = start
                var latestLocalTime: TimeInterval = 0

                while nextIndex < events.count,
                      events[nextIndex].kind == .scroll {
                    let stepEvent = events[nextIndex]
                    let stepTime = sanitizedTime(stepEvent.t)
                    if nextIndex != index,
                       elapsed(from: previousStepTime, to: stepTime) >= waitThreshold {
                        break
                    }

                    let localTime = elapsed(from: start, to: stepTime)
                    steps.append(ScrollStep(
                        t: localTime,
                        dx: stepEvent.scrollDX,
                        dy: stepEvent.scrollDY,
                        flags: stepEvent.flags
                    ))
                    latestLocalTime = max(latestLocalTime, localTime)
                    latestStepTime = max(latestStepTime, stepTime)
                    previousStepTime = stepTime
                    nextIndex += 1
                }

                appendAction(
                    .scroll(ScrollBlock(
                        x: event.x,
                        y: event.y,
                        duration: latestLocalTime,
                        steps: steps
                    )),
                    start: start,
                    end: latestStepTime
                )
                index = nextIndex

            case .keyDown:
                if isShortcut(event) {
                    var nextIndex = index + 1
                    var matchedUp: RecordedEvent?

                    while nextIndex < events.count {
                        let nextEvent = events[nextIndex]
                        if nextEvent.kind == .flagsChanged {
                            nextIndex += 1
                            continue
                        }
                        if nextEvent.kind == .keyUp,
                           nextEvent.keyCode == event.keyCode {
                            matchedUp = nextEvent
                            nextIndex += 1
                        }
                        break
                    }

                    let duration: TimeInterval
                    let upFlags: UInt64
                    let actionEnd: TimeInterval
                    if let upEvent = matchedUp {
                        duration = elapsed(
                            from: start,
                            to: sanitizedTime(upEvent.t)
                        )
                        upFlags = upEvent.flags
                        actionEnd = sanitizedTime(upEvent.t)
                    } else {
                        duration = keyFallbackDuration
                        upFlags = event.flags
                        actionEnd = adding(start, duration)
                    }

                    appendAction(
                        .shortcut(ShortcutBlock(
                            keyCode: event.keyCode,
                            flags: event.flags,
                            upFlags: upFlags,
                            duration: duration
                        )),
                        start: start,
                        end: actionEnd
                    )
                    index = nextIndex
                } else {
                    var keystrokes: [Keystroke] = []
                    var text = ""
                    var pendingByKeyCode: [UInt16: [Int]] = [:]
                    var nextIndex = index
                    var lastSubstantiveTime = start
                    var latestActionEnd = start
                    var latestLocalTime: TimeInterval = 0

                    typeLoop: while nextIndex < events.count {
                        let nextEvent = events[nextIndex]
                        let nextTime = sanitizedTime(nextEvent.t)

                        switch nextEvent.kind {
                        case .flagsChanged:
                            nextIndex += 1

                        case .keyDown:
                            guard !isShortcut(nextEvent) else { break typeLoop }
                            let idleSinceLastEvent = elapsed(
                                from: lastSubstantiveTime,
                                to: nextTime
                            )
                            let hasPendingKeyUp = hasFutureMatchingKeyUp(
                                pendingByKeyCode: pendingByKeyCode,
                                events: events,
                                after: nextIndex
                            )
                            if !keystrokes.isEmpty,
                               idleSinceLastEvent >= waitThreshold,
                               !hasPendingKeyUp {
                                break typeLoop
                            }

                            let localTime = elapsed(from: start, to: nextTime)
                            let keystrokeIndex = keystrokes.count
                            keystrokes.append(Keystroke(
                                t: localTime,
                                keyCode: nextEvent.keyCode,
                                chars: nextEvent.chars,
                                upT: adding(localTime, keyFallbackDuration),
                                downFlags: nextEvent.flags,
                                upFlags: nextEvent.flags
                            ))
                            pendingByKeyCode[nextEvent.keyCode, default: []]
                                .append(keystrokeIndex)
                            text += nextEvent.chars
                            latestLocalTime = max(latestLocalTime, localTime)
                            latestActionEnd = max(latestActionEnd, nextTime)
                            lastSubstantiveTime = max(lastSubstantiveTime, nextTime)
                            nextIndex += 1

                        case .keyUp:
                            guard var pending = pendingByKeyCode[nextEvent.keyCode],
                                  !pending.isEmpty else {
                                nextIndex += 1
                                continue
                            }

                            let keystrokeIndex = pending.removeFirst()
                            if pending.isEmpty {
                                pendingByKeyCode.removeValue(forKey: nextEvent.keyCode)
                            } else {
                                pendingByKeyCode[nextEvent.keyCode] = pending
                            }

                            let localTime = max(
                                keystrokes[keystrokeIndex].t,
                                elapsed(from: start, to: nextTime)
                            )
                            keystrokes[keystrokeIndex].upT = localTime
                            keystrokes[keystrokeIndex].upFlags = nextEvent.flags
                            latestLocalTime = max(latestLocalTime, localTime)
                            latestActionEnd = max(latestActionEnd, nextTime)
                            lastSubstantiveTime = max(lastSubstantiveTime, nextTime)
                            nextIndex += 1

                        default:
                            break typeLoop
                        }
                    }

                    let duration = max(
                        latestLocalTime,
                        keystrokes.map(\.upT).max() ?? 0
                    )
                    let fallbackEnd = keystrokes
                        .map { adding(start, $0.upT) }
                        .max() ?? start
                    appendAction(
                        .typeText(TypeTextBlock(
                            text: text,
                            keystrokes: keystrokes,
                            duration: duration
                        )),
                        start: start,
                        end: max(latestActionEnd, fallbackEnd)
                    )
                    index = nextIndex
                }

            case .keyUp:
                index += 1
            }
        }

        let trailingGap = elapsed(
            from: previousActionEnd,
            to: sanitizedTime(capture.duration)
        )
        if trailingGap >= waitThreshold {
            blocks.append(.wait(WaitBlock(duration: trailingGap)))
            return GroupedTimeline(blocks: blocks, trailingDelay: 0)
        }
        return GroupedTimeline(blocks: blocks, trailingDelay: trailingGap)
    }

    private static func hasFutureMatchingKeyUp(
        pendingByKeyCode: [UInt16: [Int]],
        events: [RecordedEvent],
        after index: Int
    ) -> Bool {
        guard !pendingByKeyCode.isEmpty else { return false }

        var nextIndex = index + 1
        while nextIndex < events.count {
            let event = events[nextIndex]
            switch event.kind {
            case .flagsChanged:
                nextIndex += 1
            case .keyDown:
                if isShortcut(event) { return false }
                nextIndex += 1
            case .keyUp:
                if pendingByKeyCode[event.keyCode] != nil { return true }
                nextIndex += 1
            default:
                return false
            }
        }
        return false
    }

    private static func isShortcut(_ event: RecordedEvent) -> Bool {
        let commandOrControl = event.flags
            & (KeyCodeMap.maskCommand | KeyCodeMap.maskControl)
        return commandOrControl != 0 || event.chars.isEmpty
    }

    private static func sanitizedTime(_ time: TimeInterval) -> TimeInterval {
        guard time.isFinite, time > 0 else { return 0 }
        return min(time, maximumTimelineTime)
    }

    private static func elapsed(
        from start: TimeInterval,
        to end: TimeInterval
    ) -> TimeInterval {
        max(0, sanitizedTime(end) - sanitizedTime(start))
    }

    private static func adding(
        _ lhs: TimeInterval,
        _ rhs: TimeInterval
    ) -> TimeInterval {
        let left = sanitizedTime(lhs)
        let right = sanitizedTime(rhs)
        guard left < maximumTimelineTime,
              right < maximumTimelineTime,
              left <= maximumTimelineTime - right else {
            return maximumTimelineTime
        }
        return left + right
    }
}

import Foundation

/// 原始事件流 → 语义化动作块。纯函数，无系统依赖。
public enum EventGrouper {
    /// 无操作间隔阈值：≥ 此值产生独立 WaitBlock。
    public static let waitThreshold: TimeInterval = 0.5

    private static let clickFallbackDuration: TimeInterval = 0.03
    private static let keyFallbackDuration: TimeInterval = 0.02

    /// 兼容旧调用方。旧 API 无法返回短尾部等待，因此只返回 blocks。
    public static func group(_ events: [RecordedEvent]) -> [ActionBlock] {
        let duration = events.last?.t ?? 0
        return group(RecordingCapture(events: events, duration: duration)).blocks
    }

    public static func group(_ capture: RecordingCapture) -> GroupedTimeline {
        let events = capture.events
        let keyMatches = matchingKeys(in: events)
        var nextSyntheticOrdinal = events.count
        var fallbackReleaseByOwner: [Int: (time: TimeInterval, ordinal: Int)] = [:]
        var blocks: [ActionBlock] = []
        var previousActionEnd: TimeInterval = 0
        var index = 0

        func syntheticOrdinal() -> Int {
            defer { nextSyntheticOrdinal += 1 }
            return nextSyntheticOrdinal
        }

        func fallbackRelease(forDownIndex downIndex: Int) -> (
            time: TimeInterval,
            ordinal: Int
        ) {
            let owner = keyMatches.ownerDownIndexByDownIndex[downIndex] ?? downIndex
            if let existing = fallbackReleaseByOwner[owner] {
                return existing
            }
            let lastDownIndex = keyMatches.lastDownIndexByOwner[owner] ?? downIndex
            let release = (
                time: adding(
                    sanitizedTime(events[lastDownIndex].t),
                    keyFallbackDuration
                ),
                ordinal: syntheticOrdinal()
            )
            fallbackReleaseByOwner[owner] = release
            return release
        }

        func appendAction(_ block: ActionBlock, start: TimeInterval, end: TimeInterval) {
            let actionStart = sanitizedTime(start)
            let actionEnd = max(actionStart, sanitizedTime(end))
            let gap = elapsed(from: previousActionEnd, to: actionStart)

            if gap >= waitThreshold {
                blocks.append(.wait(WaitBlock(
                    duration: gap,
                    startOffset: previousActionEnd
                )))
            }
            blocks.append(
                block.withStartOffset(actionStart).clearingLegacyTiming()
            )
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
                        flags: pointEvent.flags,
                        ordinal: nextIndex
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
                    flags: event.flags,
                    ordinal: index
                )]
                var nextIndex = index + 1
                var sawDrag = false
                var matchedUp: (event: RecordedEvent, index: Int)?
                var latestSampleTime = start
                var latestLocalTime: TimeInterval = 0

                while nextIndex < events.count {
                    let nextEvent = events[nextIndex]
                    if nextEvent.kind == event.kind {
                        break
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
                            flags: nextEvent.flags,
                            ordinal: nextIndex
                        ))
                        latestLocalTime = max(latestLocalTime, localTime)
                        latestSampleTime = max(latestSampleTime, sanitizedTime(nextEvent.t))
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
                            flags: nextEvent.flags,
                            ordinal: nextIndex
                        ))
                        latestLocalTime = max(latestLocalTime, localTime)
                        latestSampleTime = max(latestSampleTime, sanitizedTime(nextEvent.t))
                        matchedUp = (nextEvent, nextIndex)
                        break
                    }
                    nextIndex += 1
                }

                if sawDrag {
                    appendAction(
                        .drag(DragBlock(
                            button: button,
                            duration: latestLocalTime,
                            points: points,
                            hasRecordedMouseUp: matchedUp != nil,
                            upOrdinal: matchedUp?.index ?? syntheticOrdinal()
                        )),
                        start: start,
                        end: latestSampleTime
                    )
                } else if let matchedUp {
                    let upEvent = matchedUp.event
                    let duration = elapsed(from: start, to: sanitizedTime(upEvent.t))
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
                            upFlags: upEvent.flags,
                            downOrdinal: index,
                            upOrdinal: matchedUp.index
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
                            upFlags: event.flags,
                            downOrdinal: index,
                            upOrdinal: syntheticOrdinal()
                        )),
                        start: start,
                        end: adding(start, clickFallbackDuration)
                    )
                }
                index += 1

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
                        x: stepEvent.x,
                        y: stepEvent.y,
                        dx: stepEvent.scrollDX,
                        dy: stepEvent.scrollDY,
                        flags: stepEvent.flags,
                        ordinal: nextIndex
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
                    let matchedUpIndex = keyMatches.upIndexByDownIndex[index]
                    let matchedUp = matchedUpIndex.map { events[$0] }
                    let effectiveRepeat = keyMatches.repeatDownIndexes.contains(index)
                    let duration: TimeInterval
                    let upFlags: UInt64
                    let upOrdinal: Int
                    let actionEnd: TimeInterval
                    if let upEvent = matchedUp, let matchedUpIndex {
                        duration = elapsed(from: start, to: sanitizedTime(upEvent.t))
                        upFlags = upEvent.flags
                        upOrdinal = matchedUpIndex
                        actionEnd = sanitizedTime(upEvent.t)
                    } else {
                        let fallback = fallbackRelease(forDownIndex: index)
                        duration = elapsed(from: start, to: fallback.time)
                        upFlags = event.flags
                        upOrdinal = fallback.ordinal
                        actionEnd = fallback.time
                    }

                    appendAction(
                        .shortcut(ShortcutBlock(
                            keyCode: event.keyCode,
                            flags: event.flags,
                            upFlags: upFlags,
                            duration: duration,
                            isRepeat: effectiveRepeat,
                            downOrdinal: index,
                            upOrdinal: upOrdinal
                        )),
                        start: start,
                        end: actionEnd
                    )
                    index += 1
                } else {
                    var keystrokes: [Keystroke] = []
                    var text = ""
                    var pendingOwnerDownIndexes: Set<Int> = []
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
                            if !keystrokes.isEmpty,
                               idleSinceLastEvent >= waitThreshold,
                               pendingOwnerDownIndexes.isEmpty {
                                break typeLoop
                            }

                            let localTime = elapsed(from: start, to: nextTime)
                            let matchedUpIndex = keyMatches.upIndexByDownIndex[nextIndex]
                            let matchedUpEvent = matchedUpIndex.map { events[$0] }
                            let effectiveRepeat = keyMatches.repeatDownIndexes.contains(nextIndex)
                            if !effectiveRepeat, matchedUpIndex != nil {
                                pendingOwnerDownIndexes.insert(nextIndex)
                            }
                            let releaseTime: TimeInterval
                            let upFlags: UInt64
                            let upOrdinal: Int
                            if let matchedUpEvent, let matchedUpIndex {
                                releaseTime = sanitizedTime(matchedUpEvent.t)
                                upFlags = matchedUpEvent.flags
                                upOrdinal = matchedUpIndex
                            } else {
                                let fallback = fallbackRelease(forDownIndex: nextIndex)
                                releaseTime = fallback.time
                                upFlags = nextEvent.flags
                                upOrdinal = fallback.ordinal
                            }
                            let upTime = max(
                                localTime,
                                elapsed(from: start, to: releaseTime)
                            )
                            keystrokes.append(Keystroke(
                                t: localTime,
                                keyCode: nextEvent.keyCode,
                                chars: nextEvent.chars,
                                upT: upTime,
                                downFlags: nextEvent.flags,
                                upFlags: upFlags,
                                isRepeat: effectiveRepeat,
                                downOrdinal: nextIndex,
                                upOrdinal: upOrdinal
                            ))
                            text += nextEvent.chars
                            latestLocalTime = max(latestLocalTime, localTime, upTime)
                            latestActionEnd = max(latestActionEnd, releaseTime)
                            lastSubstantiveTime = max(lastSubstantiveTime, nextTime)
                            nextIndex += 1

                        case .keyUp:
                            if let owner = keyMatches.ownerDownIndexByUpIndex[nextIndex],
                               pendingOwnerDownIndexes.remove(owner) != nil {
                                let localTime = elapsed(from: start, to: nextTime)
                                latestLocalTime = max(latestLocalTime, localTime)
                                latestActionEnd = max(latestActionEnd, nextTime)
                                lastSubstantiveTime = max(lastSubstantiveTime, nextTime)
                            }
                            nextIndex += 1

                        default:
                            break typeLoop
                        }
                    }

                    let duration = max(
                        latestLocalTime,
                        keystrokes.map { max($0.t, $0.upT) }.max() ?? 0
                    )
                    let fallbackEnd = keystrokes
                        .map { adding(start, max($0.t, $0.upT)) }
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
            blocks.append(.wait(WaitBlock(
                duration: trailingGap,
                startOffset: previousActionEnd
            )))
            return GroupedTimeline(blocks: blocks, trailingDelay: 0)
        }
        return GroupedTimeline(blocks: blocks, trailingDelay: trailingGap)
    }

    private struct KeyMatches {
        var upIndexByDownIndex: [Int: Int] = [:]
        var ownerDownIndexByUpIndex: [Int: Int] = [:]
        var ownerDownIndexByDownIndex: [Int: Int] = [:]
        var lastDownIndexByOwner: [Int: Int] = [:]
        var repeatDownIndexes: Set<Int> = []
    }

    /// 单次全流扫描；每个 down/up 只入队或出队一次。
    private static func matchingKeys(in events: [RecordedEvent]) -> KeyMatches {
        var pendingOwnersByKeyCode: [UInt16: [Int]] = [:]
        var pendingHeadByKeyCode: [UInt16: Int] = [:]
        var repeatIndexesByOwner: [Int: [Int]] = [:]
        var result = KeyMatches()

        for (index, event) in events.enumerated() {
            switch event.kind {
            case .keyDown:
                let head = pendingHeadByKeyCode[event.keyCode] ?? 0
                if event.isRepeat,
                   let pending = pendingOwnersByKeyCode[event.keyCode],
                   head < pending.count {
                    let owner = pending[head]
                    repeatIndexesByOwner[owner, default: []].append(index)
                    result.repeatDownIndexes.insert(index)
                    result.ownerDownIndexByDownIndex[index] = owner
                    result.lastDownIndexByOwner[owner] = index
                } else {
                    pendingOwnersByKeyCode[event.keyCode, default: []].append(index)
                    result.ownerDownIndexByDownIndex[index] = index
                    result.lastDownIndexByOwner[index] = index
                }

            case .keyUp:
                guard let pending = pendingOwnersByKeyCode[event.keyCode] else {
                    continue
                }
                let head = pendingHeadByKeyCode[event.keyCode] ?? 0
                guard head < pending.count else { continue }
                let owner = pending[head]
                result.upIndexByDownIndex[owner] = index
                result.ownerDownIndexByUpIndex[index] = owner
                for repeatIndex in repeatIndexesByOwner.removeValue(forKey: owner) ?? [] {
                    result.upIndexByDownIndex[repeatIndex] = index
                }

                let nextHead = head + 1
                if nextHead == pending.count {
                    pendingOwnersByKeyCode.removeValue(forKey: event.keyCode)
                    pendingHeadByKeyCode.removeValue(forKey: event.keyCode)
                } else {
                    pendingHeadByKeyCode[event.keyCode] = nextHead
                }

            default:
                continue
            }
        }

        return result
    }

    private static func isShortcut(_ event: RecordedEvent) -> Bool {
        let commandOrControl = event.flags
            & (KeyCodeMap.maskCommand | KeyCodeMap.maskControl)
        return commandOrControl != 0 || event.chars.isEmpty
    }

    private static func sanitizedTime(_ time: TimeInterval) -> TimeInterval {
        TimelineValue.time(time)
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
        TimelineValue.adding(lhs, rhs)
    }
}

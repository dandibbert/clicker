import Foundation

public struct ActionBlockEditValues: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var endX: Double
    public var endY: Double
    public var duration: TimeInterval
    public var text: String
    public var button: MouseButton
    public var clickCount: Int
    public var keyCode: UInt16
    public var shortcutFlags: UInt64
    public var scrollDeltaY: Double

    public init(
        x: Double,
        y: Double,
        endX: Double,
        endY: Double,
        duration: TimeInterval,
        text: String,
        button: MouseButton,
        clickCount: Int,
        keyCode: UInt16,
        shortcutFlags: UInt64,
        scrollDeltaY: Double
    ) {
        self.x = x
        self.y = y
        self.endX = endX
        self.endY = endY
        self.duration = duration
        self.text = text
        self.button = button
        self.clickCount = clickCount
        self.keyCode = keyCode
        self.shortcutFlags = shortcutFlags
        self.scrollDeltaY = scrollDeltaY
    }
}

/// 动作块编辑的纯值重建入口。每次编辑都返回一个完整的新 payload。
public enum ActionBlockEditor {
    public static func edit(
        _ block: ActionBlock,
        values: ActionBlockEditValues
    ) -> ActionBlock {
        switch block {
        case .move(let payload):
            .move(move(
                payload,
                endX: values.endX,
                endY: values.endY,
                duration: values.duration
            ))
        case .click(let payload):
            .click(click(
                payload,
                x: values.x,
                y: values.y,
                button: values.button,
                clickCount: values.clickCount
            ))
        case .drag(let payload):
            .drag(drag(
                payload,
                startX: values.x,
                startY: values.y,
                endX: values.endX,
                endY: values.endY,
                duration: values.duration
            ))
        case .scroll(let payload):
            .scroll(scroll(payload, totalDeltaY: values.scrollDeltaY))
        case .typeText(let payload):
            .typeText(typeText(payload, text: values.text))
        case .shortcut(let payload):
            .shortcut(shortcut(
                payload,
                keyCode: values.keyCode,
                flags: values.shortcutFlags
            ))
        case .wait(let payload):
            .wait(wait(payload, duration: values.duration))
        }
    }

    public static func move(
        _ original: MoveBlock,
        endX: Double,
        endY: Double,
        duration: TimeInterval
    ) -> MoveBlock {
        let translatedPoints: [TrackPoint]
        if let last = original.points.last {
            let deltaX = endX - last.x
            let deltaY = endY - last.y
            translatedPoints = original.points.map { point in
                TrackPoint(
                    t: point.t,
                    x: point.x + deltaX,
                    y: point.y + deltaY,
                    flags: point.flags,
                    ordinal: point.ordinal
                )
            }
        } else {
            translatedPoints = []
        }
        let newDuration = sanitizedDuration(duration)
        return MoveBlock(
            id: original.id,
            duration: newDuration,
            points: rescaledPoints(
                translatedPoints,
                fromDuration: original.duration,
                toDuration: newDuration
            ),
            delayBefore: original.delayBefore,
            startOffset: original.startOffset
        )
    }

    public static func click(
        _ original: ClickBlock,
        x: Double,
        y: Double,
        button: MouseButton,
        clickCount: Int
    ) -> ClickBlock {
        ClickBlock(
            id: original.id,
            x: x,
            y: y,
            button: button,
            clickCount: clickCount,
            delayBefore: original.delayBefore,
            startOffset: original.startOffset,
            duration: original.duration,
            upX: x,
            upY: y,
            upClickCount: clickCount,
            downFlags: original.downFlags,
            upFlags: original.upFlags,
            downOrdinal: original.downOrdinal,
            upOrdinal: original.upOrdinal
        )
    }

    public static func shortcut(
        _ original: ShortcutBlock,
        keyCode: UInt16,
        flags: UInt64
    ) -> ShortcutBlock {
        ShortcutBlock(
            id: original.id,
            keyCode: keyCode,
            flags: flags,
            delayBefore: original.delayBefore,
            startOffset: original.startOffset,
            upFlags: flags,
            duration: original.duration,
            isRepeat: original.isRepeat,
            downOrdinal: original.downOrdinal,
            upOrdinal: original.upOrdinal
        )
    }

    public static func typeText(
        _ original: TypeTextBlock,
        text: String
    ) -> TypeTextBlock {
        TypeTextBlock(
            id: original.id,
            text: text,
            keystrokes: original.keystrokes,
            delayBefore: original.delayBefore,
            startOffset: original.startOffset,
            duration: original.duration
        )
    }

    public static func scroll(
        _ original: ScrollBlock,
        totalDeltaY: Double
    ) -> ScrollBlock {
        let originalTotal = original.steps.reduce(0) { $0 + $1.dy }
        let steps: [ScrollStep]
        if original.steps.isEmpty {
            steps = [ScrollStep(
                t: 0,
                x: original.x,
                y: original.y,
                dx: 0,
                dy: totalDeltaY
            )]
        } else if originalTotal != 0 {
            let scale = totalDeltaY / originalTotal
            steps = original.steps.map { step in
                replacingDeltaY(step, with: step.dy * scale, in: original)
            }
        } else {
            let lastIndex = original.steps.index(before: original.steps.endIndex)
            steps = original.steps.enumerated().map { index, step in
                let deltaY = index == lastIndex ? step.dy + totalDeltaY : step.dy
                return replacingDeltaY(step, with: deltaY, in: original)
            }
        }

        return ScrollBlock(
            id: original.id,
            x: original.x,
            y: original.y,
            duration: original.duration,
            steps: steps,
            delayBefore: original.delayBefore,
            startOffset: original.startOffset
        )
    }

    public static func drag(
        _ original: DragBlock,
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double,
        duration: TimeInterval
    ) -> DragBlock {
        let newDuration = sanitizedDuration(duration)
        let positionedPoints: [TrackPoint]
        if let onlyPoint = original.points.first, original.points.count == 1 {
            positionedPoints = [
                TrackPoint(
                    t: 0,
                    x: startX,
                    y: startY,
                    flags: onlyPoint.flags,
                    ordinal: onlyPoint.ordinal
                ),
                TrackPoint(
                    t: newDuration,
                    x: endX,
                    y: endY,
                    flags: onlyPoint.flags,
                    ordinal: original.hasRecordedMouseUp
                        ? original.upOrdinal
                        : onlyPoint.ordinal
                ),
            ]
        } else {
            positionedPoints = remappedDragPoints(
                original.points,
                startX: startX,
                startY: startY,
                endX: endX,
                endY: endY
            )
        }
        let points = original.points.count == 1
            ? positionedPoints
            : rescaledPoints(
                positionedPoints,
                fromDuration: original.duration,
                toDuration: newDuration
            )
        return DragBlock(
            id: original.id,
            button: original.button,
            duration: newDuration,
            points: points,
            delayBefore: original.delayBefore,
            startOffset: original.startOffset,
            hasRecordedMouseUp: original.hasRecordedMouseUp,
            upOrdinal: original.upOrdinal
        )
    }

    public static func wait(
        _ original: WaitBlock,
        duration: TimeInterval
    ) -> WaitBlock {
        WaitBlock(
            id: original.id,
            duration: sanitizedDuration(duration),
            startOffset: original.startOffset
        )
    }

    private static func replacingDeltaY(
        _ step: ScrollStep,
        with deltaY: Double,
        in block: ScrollBlock
    ) -> ScrollStep {
        ScrollStep(
            t: step.t,
            x: step.x ?? block.x,
            y: step.y ?? block.y,
            dx: step.dx,
            dy: deltaY,
            flags: step.flags,
            ordinal: step.ordinal
        )
    }

    private static func sanitizedDuration(_ duration: TimeInterval) -> TimeInterval {
        TimelineValue.time(duration)
    }

    private static func rescaledPoints(
        _ points: [TrackPoint],
        fromDuration oldDuration: TimeInterval,
        toDuration newDuration: TimeInterval
    ) -> [TrackPoint] {
        let oldDuration = sanitizedDuration(oldDuration)
        if oldDuration > 0 {
            let ratio = newDuration / oldDuration
            return points.map { point in
                TrackPoint(
                    t: sanitizedDuration(point.t * ratio),
                    x: point.x,
                    y: point.y,
                    flags: point.flags,
                    ordinal: point.ordinal
                )
            }
        }
        if points.count > 1, newDuration > 0 {
            let lastIndex = Double(points.count - 1)
            return points.enumerated().map { index, point in
                TrackPoint(
                    t: newDuration * Double(index) / lastIndex,
                    x: point.x,
                    y: point.y,
                    flags: point.flags,
                    ordinal: point.ordinal
                )
            }
        }
        return points.map { point in
            TrackPoint(
                t: 0,
                x: point.x,
                y: point.y,
                flags: point.flags,
                ordinal: point.ordinal
            )
        }
    }

    private static func remappedDragPoints(
        _ points: [TrackPoint],
        startX: Double,
        startY: Double,
        endX: Double,
        endY: Double
    ) -> [TrackPoint] {
        guard let first = points.first,
              let last = points.last,
              points.count >= 2 else {
            return points
        }
        let oldSpanX = last.x - first.x
        let oldSpanY = last.y - first.y
        let newSpanX = endX - startX
        let newSpanY = endY - startY
        let timeSpan = last.t - first.t
        return points.enumerated().map { index, point in
            let fallbackProgress: Double
            if index == 0 {
                fallbackProgress = 0
            } else if index == points.count - 1 {
                fallbackProgress = 1
            } else if timeSpan.isFinite, timeSpan > 0 {
                fallbackProgress = (point.t - first.t) / timeSpan
            } else {
                fallbackProgress = Double(index) / Double(points.count - 1)
            }
            let fractionX = oldSpanX == 0
                ? fallbackProgress
                : (point.x - first.x) / oldSpanX
            let fractionY = oldSpanY == 0
                ? fallbackProgress
                : (point.y - first.y) / oldSpanY
            return TrackPoint(
                t: point.t,
                x: startX + fractionX * newSpanX,
                y: startY + fractionY * newSpanY,
                flags: point.flags,
                ordinal: point.ordinal
            )
        }
    }
}

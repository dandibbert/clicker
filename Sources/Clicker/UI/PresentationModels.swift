import Foundation
import ClickerCore

struct ActionCardPresentation: Equatable {
    let systemImage: String
    let title: String
    let summary: String
    let trailingText: String
    let accessibilityLabel: String
    let activeAccessibilityLabel: String

    init(block: ActionBlock) {
        let values: (systemImage: String, title: String, summary: String, trailingText: String)
        switch block {
        case .move(let move):
            values = (
                "arrow.up.and.down.and.arrow.left.and.right",
                "移动鼠标",
                Self.pathSummary(move.points),
                Self.durationText(block.effectiveDuration)
            )
        case .click(let click):
            let title = click.button == .right ? "右键" : (click.clickCount >= 2 ? "双击" : "单击")
            values = (
                "cursorarrow.click",
                title,
                Self.pointSummary(x: click.x, y: click.y),
                ""
            )
        case .drag(let drag):
            values = (
                "hand.draw",
                "拖拽",
                Self.pathSummary(drag.points),
                Self.durationText(block.effectiveDuration)
            )
        case .scroll(let scroll):
            let total = Self.finiteSum(scroll.steps.map(\.dy))
            let direction = total <= 0 ? "向下" : "向上"
            values = (
                "computermouse",
                "滚动",
                "\(direction) \(Self.number(abs(total))) px",
                ""
            )
        case .typeText(let typeText):
            values = (
                "keyboard",
                "输入文本",
                "\"\(Self.truncated(typeText.text))\"",
                ""
            )
        case .shortcut(let shortcut):
            values = (
                "command",
                "快捷键",
                KeyCodeMap.shortcutDisplay(keyCode: shortcut.keyCode, flags: shortcut.flags),
                ""
            )
        case .wait:
            values = ("clock", "等待", "暂停回放", Self.durationText(block.effectiveDuration))
        }

        systemImage = values.systemImage
        title = values.title
        summary = values.summary
        trailingText = values.trailingText

        let accessibleSummary: String
        if case .typeText(let typeText) = block {
            accessibleSummary = typeText.text
        } else {
            accessibleSummary = values.summary
        }
        accessibilityLabel = [values.title, accessibleSummary, values.trailingText]
            .filter { !$0.isEmpty }
            .joined(separator: "，")
        activeAccessibilityLabel = "正在回放，\(accessibilityLabel)"
    }

    private static func pointSummary(x: Double, y: Double) -> String {
        "(\(number(x)), \(number(y)))"
    }

    private static func pathSummary(_ points: [TrackPoint]) -> String {
        guard let first = points.first, let last = points.last else { return "未记录轨迹" }
        return "\(pointSummary(x: first.x, y: first.y)) → \(pointSummary(x: last.x, y: last.y))"
    }

    private static func number(_ value: Double) -> String {
        let finiteValue = value.isFinite ? value : 0
        return String(format: "%.0f", locale: posixLocale, finiteValue)
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let rounded = (duration * 10).rounded(.toNearestOrAwayFromZero) / 10
        return String(format: "%.1f 秒", locale: posixLocale, rounded)
    }

    private static func finiteSum(_ values: [Double]) -> Double {
        values.reduce(0) { total, value in
            guard value.isFinite else { return total }
            let result = total + value
            return result.isFinite ? result : 0
        }
    }

    private static func truncated(_ text: String) -> String {
        guard text.count > 28 else { return text }
        return "\(text.prefix(28))…"
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")
}

enum ActiveFeedbackStyle: Equatable {
    case staticHighlight
    case pulsingTrail

    static func resolve(isActive: Bool, reduceMotion: Bool) -> ActiveFeedbackStyle? {
        guard isActive else { return nil }
        return reduceMotion ? .staticHighlight : .pulsingTrail
    }
}

struct ScriptRowPresentation: Equatable {
    let name: String
    let actionCountText: String
    let modifiedText: String
    let metadataText: String
    let accessibilityLabel: String

    init(script: Script, now: Date = Date()) {
        name = script.name
        actionCountText = "\(script.blocks.count) 个动作"
        modifiedText = Self.modifiedText(from: script.modifiedAt, now: now)
        metadataText = "\(actionCountText) · \(modifiedText)"
        accessibilityLabel = "\(name)，\(actionCountText)，\(modifiedText)"
    }

    private static func modifiedText(from date: Date, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        switch elapsed {
        case ..<60:
            return "刚刚修改"
        case ..<3_600:
            return "\(max(1, Int(elapsed / 60))) 分钟前修改"
        case ..<86_400:
            return "\(Int(elapsed / 3_600)) 小时前修改"
        case ..<604_800:
            return "\(Int(elapsed / 86_400)) 天前修改"
        default:
            return "\(Int(elapsed / 604_800)) 周前修改"
        }
    }
}

enum ClickerEmptyStateKind: Equatable {
    case emptyLibrary
    case noSelection
    case noSearchResults
    case permissionRequired
    case emptyScript
}

struct ClickerEmptyStatePresentation: Equatable {
    let systemImage: String
    let title: String
    let description: String
    let actionTitle: String?
    let secondaryActionTitle: String?

    init(kind: ClickerEmptyStateKind) {
        switch kind {
        case .emptyLibrary:
            systemImage = "cursorarrow.click.badge.clock"
            title = "还没有脚本"
            description = "录制一段操作，或新建脚本手动添加动作。"
            actionTitle = "开始录制"
            secondaryActionTitle = "新建空白脚本"
        case .noSearchResults:
            systemImage = "magnifyingglass"
            title = "没有匹配的脚本"
            description = "换个名称搜索，或清除搜索查看全部脚本。"
            actionTitle = "清除搜索"
            secondaryActionTitle = nil
        case .noSelection:
            systemImage = "sidebar.left"
            title = "选择一个脚本"
            description = "从左侧脚本库选择一个脚本，查看和编辑它的动作。"
            actionTitle = nil
            secondaryActionTitle = nil
        case .permissionRequired:
            systemImage = "hand.raised.circle"
            title = "需要系统权限"
            description = "请在「系统设置 → 隐私与安全性」中为 Clicker 开启辅助功能和输入监控，才能完整录制、停止和回放鼠标键盘操作。授权后回到本窗口重新检测。"
            actionTitle = "打开系统设置"
            secondaryActionTitle = "重新检测"
        case .emptyScript:
            systemImage = "square.stack.3d.up.slash"
            title = "这个脚本还没有动作"
            description = "开始录制操作，或手动添加第一个动作。"
            actionTitle = "开始录制"
            secondaryActionTitle = nil
        }
    }
}

enum PrimaryActionKind: Equatable {
    case record
    case play
}

struct PrimaryActionPresentation: Equatable {
    let kind: PrimaryActionKind
    let title: String
    let systemImage: String
    let isStop: Bool
    let isEnabled: Bool
    let accessibilityLabel: String

    static func pair(
        phase: AppPhase,
        hasPlayableScript: Bool,
        canRecord: Bool = true,
        canPlay: Bool = true
    ) -> [PrimaryActionPresentation] {
        switch phase {
        case .idle:
            return [
                recordStart(isEnabled: canRecord),
                playbackStart(isEnabled: hasPlayableScript && canPlay),
            ]
        case .countdown:
            return [
                recordStop,
                playbackStart(isEnabled: false),
            ]
        case .recording:
            return [
                recordStop,
                playbackStart(isEnabled: false),
            ]
        case .playing:
            return [
                recordStart(isEnabled: false),
                playbackStop,
            ]
        }
    }

    static func usesAnimatedActiveFeedback(isReduceMotionEnabled: Bool) -> Bool {
        !isReduceMotionEnabled
    }

    private static func recordStart(isEnabled: Bool = true) -> PrimaryActionPresentation {
        PrimaryActionPresentation(
            kind: .record,
            title: "录制",
            systemImage: "record.circle",
            isStop: false,
            isEnabled: isEnabled,
            accessibilityLabel: "开始录制"
        )
    }

    private static let recordStop = PrimaryActionPresentation(
        kind: .record,
        title: "停止录制",
        systemImage: "stop.circle",
        isStop: true,
        isEnabled: true,
        accessibilityLabel: "停止录制"
    )

    private static func playbackStart(isEnabled: Bool) -> PrimaryActionPresentation {
        PrimaryActionPresentation(
            kind: .play,
            title: "回放",
            systemImage: "play.fill",
            isStop: false,
            isEnabled: isEnabled,
            accessibilityLabel: "开始回放"
        )
    }

    private static let playbackStop = PrimaryActionPresentation(
        kind: .play,
        title: "停止回放",
        systemImage: "stop.circle",
        isStop: true,
        isEnabled: true,
        accessibilityLabel: "停止回放"
    )
}


enum ScriptLibrarySearch {
    static func filter(_ scripts: [Script], query: String) -> [Script] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return scripts }
        return scripts.filter { $0.name.localizedStandardContains(query) }
    }
}

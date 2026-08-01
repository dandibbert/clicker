import Foundation
import ClickerCore

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
    case emptyScript
}

struct ClickerEmptyStatePresentation: Equatable {
    let systemImage: String
    let title: String
    let description: String
    let actionTitle: String?

    init(kind: ClickerEmptyStateKind) {
        switch kind {
        case .emptyLibrary:
            systemImage = "cursorarrow.click.badge.clock"
            title = "还没有脚本"
            description = "录制一段操作，创建你的第一个脚本。"
            actionTitle = "开始录制"
        case .noSelection:
            systemImage = "sidebar.left"
            title = "选择一个脚本"
            description = "从左侧脚本库选择一个脚本，查看和编辑它的动作。"
            actionTitle = nil
        case .emptyScript:
            systemImage = "square.stack.3d.up.slash"
            title = "这个脚本还没有动作"
            description = "开始录制操作，或手动添加第一个动作。"
            actionTitle = "开始录制"
        }
    }
}

enum PrimaryActionKind: Equatable {
    case record
    case play
}

enum ScriptPlaybackEligibility {
    static func isPlayable(_ script: Script) -> Bool {
        let plan = BlockExpander.plan(for: script)
        return !plan.steps.isEmpty || plan.duration > 0
    }
}

struct PrimaryActionPresentation: Equatable {
    let kind: PrimaryActionKind
    let title: String
    let systemImage: String
    let isStop: Bool
    let isEnabled: Bool
    let accessibilityLabel: String

    static func pair(phase: AppPhase, hasPlayableScript: Bool) -> [PrimaryActionPresentation] {
        switch phase {
        case .idle:
            return [
                recordStart(),
                playbackStart(isEnabled: hasPlayableScript),
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

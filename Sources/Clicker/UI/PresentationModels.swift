import Foundation

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

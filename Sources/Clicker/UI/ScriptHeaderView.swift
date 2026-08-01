import Foundation
import SwiftUI
import ClickerCore

struct ScriptHeaderPresentation: Equatable {
    let title: String
    let actionCountText: String
    let durationText: String

    init(script: Script) {
        title = script.name
        actionCountText = "\(script.blocks.count) 个动作"
        durationText = Self.durationText(for: BlockExpander.plan(for: script).duration)
    }

    private static func durationText(for duration: TimeInterval) -> String {
        let safeDuration = duration.isFinite ? max(0, duration) : 0
        return String(
            format: "约 %.1f 秒",
            locale: Locale(identifier: "en_US_POSIX"),
            safeDuration
        )
    }
}

struct ScriptHeaderView: View {
    @EnvironmentObject private var state: AppState

    let script: Script

    private var presentation: ScriptHeaderPresentation {
        ScriptHeaderPresentation(script: script)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing16) {
            VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing4) {
                Text(presentation.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ClickerVisualTheme.primaryText)
                    .lineLimit(1)
                Text("\(presentation.actionCountText) · \(presentation.durationText)")
                    .font(.callout)
                    .foregroundStyle(ClickerVisualTheme.secondaryText)
            }

            PrimaryActionBar(
                phase: state.phase,
                hasPlayableScript: ScriptPlaybackEligibility.isPlayable(script)
            )

            HStack(spacing: ClickerVisualTheme.spacing16) {
                repeatControls
                intervalControls
                Spacer()
                playbackProgress
            }
        }
        .padding(ClickerVisualTheme.spacing16)
        .background(ClickerVisualTheme.elevatedSurface)
    }

    private var repeatControls: some View {
        HStack(spacing: ClickerVisualTheme.spacing4) {
            Text("重复")
            TextField("次数", value: Binding(
                get: { script.repeatCount },
                set: { updateRepeatCount($0) }
            ), format: .number)
                .frame(width: 50)
                .disabled(script.repeatForever)
            Text("次")
            Toggle("无限", isOn: Binding(
                get: { script.repeatForever },
                set: { updateRepeatForever($0) }
            ))
            .toggleStyle(.checkbox)
        }
        .disabled(!state.canEditScripts)
    }

    private var intervalControls: some View {
        HStack(spacing: ClickerVisualTheme.spacing4) {
            Text("间隔")
            TextField("秒", value: Binding(
                get: { script.repeatInterval },
                set: { updateRepeatInterval($0) }
            ), format: .number)
                .frame(width: 50)
            Text("秒")
        }
        .disabled(!state.canEditScripts)
    }

    @ViewBuilder
    private var playbackProgress: some View {
        if case .playing(let iteration, _) = state.phase {
            Label(
                script.repeatForever ? "第 \(iteration) 轮" : "第 \(iteration)/\(script.repeatCount) 轮",
                systemImage: "play.fill"
            )
            .foregroundStyle(ClickerVisualTheme.playbackFill)
        }
    }

    private func updateRepeatCount(_ count: Int) {
        var updated = script
        updated.repeatCount = max(1, count)
        state.update(updated)
    }

    private func updateRepeatForever(_ repeatForever: Bool) {
        var updated = script
        updated.repeatForever = repeatForever
        state.update(updated)
    }

    private func updateRepeatInterval(_ interval: TimeInterval) {
        var updated = script
        updated.repeatInterval = max(0, interval)
        state.update(updated)
    }
}

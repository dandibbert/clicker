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

struct CompactScriptHeaderPresentation: Equatable {
    let title: String
    let metadata: String
    let playbackProgressText: String?

    var showsPlaybackProgress: Bool {
        playbackProgressText != nil
    }

    init(script: Script, phase: AppPhase) {
        let header = ScriptHeaderPresentation(script: script)
        title = header.title
        metadata = "\(header.actionCountText) · \(header.durationText)"

        if case .playing(let iteration, _) = phase {
            playbackProgressText = script.repeatForever
                ? "第 \(iteration) 轮"
                : "第 \(iteration)/\(script.repeatCount) 轮"
        } else {
            playbackProgressText = nil
        }
    }
}

struct ScriptHeaderView: View {
    @EnvironmentObject private var state: AppState

    let script: Script

    private var presentation: CompactScriptHeaderPresentation {
        CompactScriptHeaderPresentation(script: script, phase: state.phase)
    }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width < 700 {
                compactComposition
            } else {
                wideComposition
            }
        }
        .frame(height: ClickerVisualTheme.compactHeaderHeight)
        .background(ClickerVisualTheme.elevatedSurface)
    }

    private var wideComposition: some View {
        HStack(spacing: 18) {
            identity
                .frame(minWidth: 130, maxWidth: .infinity, alignment: .leading)

            PrimaryActionBar(
                phase: state.phase,
                hasPlayableScript: ScriptPlaybackEligibility.isPlayable(script)
            )
            .fixedSize(horizontal: true, vertical: false)

            repeatParameters
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: ClickerVisualTheme.compactHeaderHeight)
    }

    private var compactComposition: some View {
        VStack(spacing: ClickerVisualTheme.spacing4) {
            HStack(spacing: ClickerVisualTheme.spacing12) {
                identity
                    .frame(maxWidth: .infinity, alignment: .leading)
                playbackProgress(width: 176)
            }
            HStack(spacing: ClickerVisualTheme.spacing12) {
                PrimaryActionBar(
                    phase: state.phase,
                    hasPlayableScript: ScriptPlaybackEligibility.isPlayable(script)
                )
                .fixedSize(horizontal: true, vertical: false)
                repeatSettings
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, ClickerVisualTheme.spacing12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing4) {
            Text(presentation.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(ClickerVisualTheme.primaryText)
                .lineLimit(1)
            Text(presentation.metadata)
                .font(.caption)
                .foregroundStyle(ClickerVisualTheme.secondaryText)
                .lineLimit(1)
        }
    }

    private var repeatParameters: some View {
        HStack(spacing: ClickerVisualTheme.spacing4) {
            repeatSettings
            playbackProgress(width: 144)
        }
    }

    private var repeatSettings: some View {
        HStack(spacing: ClickerVisualTheme.spacing4) {
            repeatControls
            intervalControls
        }
    }

    private var repeatControls: some View {
        HStack(spacing: ClickerVisualTheme.spacing4) {
            Text("重复")
            TextField("次数", value: Binding(
                get: { script.repeatCount },
                set: { updateRepeatCount($0) }
            ), format: .number)
                .frame(width: ClickerVisualTheme.primaryControlHeight)
                .frame(minHeight: ClickerVisualTheme.primaryControlHeight)
                .disabled(script.repeatForever)
            Text("次")
            Toggle("无限", isOn: Binding(
                get: { script.repeatForever },
                set: { updateRepeatForever($0) }
            ))
            .toggleStyle(.checkbox)
            .frame(minHeight: ClickerVisualTheme.primaryControlHeight)
        }
        .fixedSize(horizontal: true, vertical: false)
        .disabled(!state.canEditScripts)
    }

    private var intervalControls: some View {
        HStack(spacing: ClickerVisualTheme.spacing4) {
            Text("间隔")
            TextField("秒", value: Binding(
                get: { script.repeatInterval },
                set: { updateRepeatInterval($0) }
            ), format: .number)
                .frame(width: ClickerVisualTheme.primaryControlHeight)
                .frame(minHeight: ClickerVisualTheme.primaryControlHeight)
            Text("秒")
        }
        .fixedSize(horizontal: true, vertical: false)
        .disabled(!state.canEditScripts)
    }

    @ViewBuilder
    private func playbackProgress(width: CGFloat) -> some View {
        if let playbackProgressText = presentation.playbackProgressText {
            Text(playbackProgressText)
                .foregroundStyle(ClickerVisualTheme.playbackFill)
                .lineLimit(4)
                .frame(width: width, alignment: .leading)
                .accessibilityLabel(playbackProgressText)
                .help(playbackProgressText)
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

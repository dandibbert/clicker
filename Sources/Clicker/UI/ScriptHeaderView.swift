import AppKit
import Foundation
import SwiftUI
import ClickerCore

struct ScriptHeaderPresentation: Equatable {
    let title: String
    let actionCountText: String
    let durationText: String
    let repeatSummaryText: String
    let estimatedDurationText: String

    init(script: Script) {
        title = script.name
        actionCountText = "\(script.blocks.count) 个动作"
        let duration = BlockExpander.plan(for: script).duration
        durationText = Self.durationText(for: duration)
        if script.repeatForever {
            repeatSummaryText = "无限轮"
            estimatedDurationText = "单轮\(durationText)"
        } else {
            let count = max(1, script.repeatCount)
            repeatSummaryText = "\(count) 轮"
            let interval = script.repeatInterval.isFinite ? max(0, script.repeatInterval) : 0
            let total = max(0, duration) * Double(count) + interval * Double(count - 1)
            estimatedDurationText = total.isFinite && total < 31_536_000
                ? Self.durationText(for: total)
                : "预计超过 1 年"
        }
    }

    private static func durationText(for duration: TimeInterval) -> String {
        let safeDuration = duration.isFinite ? max(0, duration) : 0
        if safeDuration >= 3_600 {
            return String(format: "约 %.1f 小时", locale: Locale(identifier: "en_US_POSIX"), safeDuration / 3_600)
        }
        if safeDuration >= 60 {
            return String(format: "约 %.1f 分钟", locale: Locale(identifier: "en_US_POSIX"), safeDuration / 60)
        }
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

    init(script: Script, phase: AppPhase, activePlaybackScript: Script? = nil) {
        let header = ScriptHeaderPresentation(script: script)
        title = header.title
        metadata = "\(header.actionCountText) · \(header.repeatSummaryText) · \(header.estimatedDurationText)"

        if case .playing(let iteration, _) = phase {
            let playing = activePlaybackScript ?? script
            let progress = playing.repeatForever
                ? "第 \(iteration) 轮"
                : "第 \(iteration)/\(playing.repeatCount) 轮"
            playbackProgressText = playing.id == script.id ? progress : nil
        } else {
            playbackProgressText = nil
        }
    }
}

struct ScriptHeaderView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let script: Script
    @State private var showsStartApplicationSettings = false

    private var presentation: CompactScriptHeaderPresentation {
        CompactScriptHeaderPresentation(
            script: script, phase: state.phase, activePlaybackScript: state.activePlaybackScript
        )
    }

    private var layoutPolicy: ClickerPresentationLayoutPolicy {
        ClickerPresentationLayoutPolicy(dynamicTypeSize: dynamicTypeSize)
    }

    var body: some View {
        Group {
            if layoutPolicy.usesAccessibilityLayout {
                accessibilityComposition
            } else {
                compactComposition
            }
        }
        .frame(height: layoutPolicy.headerHeight)
        .background(ClickerVisualTheme.controlSurface)
    }

    private var accessibilityComposition: some View {
        VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing8) {
            HStack(alignment: .top, spacing: ClickerVisualTheme.spacing12) {
                identity
                    .frame(maxWidth: .infinity, alignment: .leading)
                playbackProgress(width: 200)
            }
            PrimaryActionBar(
                phase: state.phase,
                hasPlayableScript: ScriptPlaybackEligibility.isPlayable(script),
                canRecord: state.canStartRecording && state.hasPermission,
                canPlay: state.hasPermission
            )
            .fixedSize(horizontal: true, vertical: false)
            repeatControls
                .fixedSize(horizontal: true, vertical: false)
            intervalControls
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, ClickerVisualTheme.spacing12)
        .padding(.vertical, ClickerVisualTheme.spacing12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var compactComposition: some View {
        VStack(spacing: ClickerVisualTheme.spacing4) {
            HStack(spacing: ClickerVisualTheme.spacing16) {
                identity
                    .frame(maxWidth: .infinity, alignment: .leading)
                PrimaryActionBar(
                    phase: state.phase,
                    hasPlayableScript: ScriptPlaybackEligibility.isPlayable(script),
                    canRecord: state.canStartRecording && state.hasPermission,
                    canPlay: state.hasPermission
                )
                .fixedSize(horizontal: true, vertical: false)
            }
            HStack(spacing: ClickerVisualTheme.spacing16) {
                repeatControls
                intervalControls
                Spacer(minLength: 0)
                playbackProgress(width: 200)
            }
        }
        .padding(.horizontal, ClickerVisualTheme.spacing12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing4) {
            HStack(spacing: ClickerVisualTheme.spacing8) {
                Text(presentation.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(ClickerVisualTheme.primaryText)
                    .lineLimit(1)
                    .help(presentation.title)
                Button { showsStartApplicationSettings = true } label: {
                    Text(script.startApplicationBeforePlayback ? "START ONLY" : "FREE · 跨应用")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
                .fixedSize()
                .foregroundStyle(ClickerVisualTheme.secondaryText)
                .help(script.startApplicationBeforePlayback
                      ? "仅在回放开始时切换到所选应用，之后允许跨应用操作"
                      : "自由跨应用回放；不会强制切换或锁定应用")
                .popover(isPresented: $showsStartApplicationSettings) {
                    StartApplicationSettingsView(scriptID: script.id)
                        .environmentObject(state)
                }
            }
            Text(presentation.metadata)
            .font(.caption)
            .foregroundStyle(ClickerVisualTheme.secondaryText)
            .lineLimit(1)
            .help(presentation.metadata)
        }
    }

    private var repeatControls: some View {
        HStack(spacing: layoutPolicy.compactControlSpacing) {
            Text("重复")
            TextField("次数", value: Binding(
                get: { script.repeatCount },
                set: { updateRepeatCount($0) }
            ), format: .number)
                .frame(width: layoutPolicy.compactFieldWidth)
                .frame(minHeight: layoutPolicy.compactControlHeight)
                .disabled(script.repeatForever)
            Text("次")
            Toggle("无限", isOn: Binding(
                get: { script.repeatForever },
                set: { updateRepeatForever($0) }
            ))
            .toggleStyle(.checkbox)
            .frame(minHeight: layoutPolicy.compactControlHeight)
        }
        .fixedSize(horizontal: true, vertical: false)
        .disabled(!state.canEditScripts)
    }

    private var intervalControls: some View {
        HStack(spacing: layoutPolicy.compactControlSpacing) {
            Text("间隔")
            TextField("秒", value: Binding(
                get: { script.repeatInterval },
                set: { updateRepeatInterval($0) }
            ), format: .number)
                .frame(width: layoutPolicy.compactFieldWidth)
                .frame(minHeight: layoutPolicy.compactControlHeight)
            Text("秒")
        }
        .fixedSize(horizontal: true, vertical: false)
        .disabled(!state.canEditScripts)
    }

    @ViewBuilder
    private func playbackProgress(width: CGFloat) -> some View {
        if let playbackProgressText = presentation.playbackProgressText {
            // Label long current/total values on separate complete lines. This
            // avoids both clipping and an ambiguous separator at a line ending.
            let parts = playbackProgressText.split(separator: "/", maxSplits: 1)
            let displayText = playbackProgressText.count > 26 && parts.count == 2
                ? "\(parts[0]) 轮\n共 \(parts[1])"
                : playbackProgressText
            Text(displayText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(ClickerVisualTheme.primaryText)
                .lineLimit(layoutPolicy.usesAccessibilityLayout ? 4 : 2)
                .fixedSize(horizontal: false, vertical: true)
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

private struct RunningStartApplication: Identifiable {
    let id: String
    let name: String
}

/// Selecting a start application is deliberately opt-in. It does not constrain
/// the destinations of subsequent recorded mouse and keyboard events.
struct StartApplicationSettingsView: View {
    @EnvironmentObject private var state: AppState
    let scriptID: UUID
    @State private var applications: [RunningStartApplication] = []

    private var script: Script? { state.scripts.first { $0.id == scriptID } }

    var body: some View {
        VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing12) {
            Text("回放起始应用").font(.headline)
            Text("默认 FREE：自由跨应用，不自动切换或锁定应用。")
                .font(.callout)
                .foregroundStyle(ClickerVisualTheme.secondaryText)
            Toggle("开始前切换到应用（START ONLY）", isOn: Binding(
                get: { script?.startApplicationBeforePlayback ?? false },
                set: setStartApplicationEnabled
            ))
            .disabled(!state.canEditScripts || (!hasRunningTarget && script?.startApplicationBeforePlayback != true))
            Group {
                Picker("起始应用", selection: Binding(
                    get: { script?.targetBundleIdentifier ?? "" },
                    set: setTargetApplication
                )) {
                    Text("选择正在运行的应用").tag("")
                    if let selected = script?.targetBundleIdentifier,
                       !applications.contains(where: { $0.id == selected }) {
                        Text("\(selected)（未运行）").tag(selected)
                    }
                    ForEach(applications) { application in
                        Text(application.name).tag(application.id)
                    }
                }
                .disabled(!state.canEditScripts)
                Text(script?.startApplicationBeforePlayback == true
                     ? "只在开始时切换一次，之后可继续跨应用操作；切换失败时会先询问你。"
                     : "选择正在运行的应用，再开启上方选项。选择应用不会自动开启切换。")
                    .font(.caption)
                    .foregroundStyle(ClickerVisualTheme.secondaryText)
            }
            HStack {
                if applications.isEmpty {
                    Text("请先打开要切换的应用").font(.caption)
                }
                Spacer()
                Button("刷新应用列表", action: refreshApplications)
            }
        }
        .foregroundStyle(ClickerVisualTheme.primaryText)
        .padding(ClickerVisualTheme.spacing16)
        .frame(width: 350)
        .background(ClickerVisualTheme.canvas)
        .onAppear(perform: refreshApplications)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshApplications()
        }
    }

    private func refreshApplications() {
        applications = NSWorkspace.shared.runningApplications.compactMap { application -> RunningStartApplication? in
            guard application.activationPolicy == .regular,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let identifier = application.bundleIdentifier else { return nil }
            return RunningStartApplication(id: identifier, name: application.localizedName ?? identifier)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // Multiple processes may have the same bundle ID; keep Picker tags unique.
        var seen = Set<String>()
        applications = applications.filter { seen.insert($0.id).inserted }
    }

    private var hasRunningTarget: Bool {
        applications.contains { $0.id == script?.targetBundleIdentifier }
    }

    private func setStartApplicationEnabled(_ enabled: Bool) {
        guard var script else { return }
        script.startApplicationBeforePlayback = enabled && hasRunningTarget
        state.update(script)
    }

    private func setTargetApplication(_ identifier: String) {
        guard var script else { return }
        script.targetBundleIdentifier = identifier.isEmpty ? nil : identifier
        if identifier.isEmpty { script.startApplicationBeforePlayback = false }
        state.update(script)
    }
}

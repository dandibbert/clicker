import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ClickerCore

/// Persistent recovery controls remain available after an error alert is dismissed.
struct RecordingRecoveryView: View {
    @EnvironmentObject private var state: AppState
    @State private var confirmsDiscard = false

    var body: some View {
        if let draft = state.unsavedRecording {
            VStack(alignment: .leading, spacing: 8) {
                Label("未保存的录制：\(draft.name)", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                if let interruption = draft.recordingInterruption {
                    Text("部分录制：\(interruption)").font(.caption)
                }
                Text("录制仍保留在内存中。请保存或另存；强制退出或系统崩溃仍可能丢失内容。")
                    .font(.caption)
                HStack {
                    Button("重试保存") { state.retrySavingRecording() }
                    Button("另存为…") { saveElsewhere(draft) }
                    Button("丢弃…", role: .destructive) { confirmsDiscard = true }
                }
                .disabled(state.phase != .idle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(ClickerVisualTheme.controlSurface)
            .confirmationDialog("丢弃这段未保存的录制？", isPresented: $confirmsDiscard) {
                Button("丢弃录制", role: .destructive) { state.discardUnsavedRecording() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作会删除仅保存在内存中的录制，无法撤销。")
            }
        }
    }

    private func saveElsewhere(_ script: Script) {
        let panel = NSSavePanel()
        panel.title = "另存录制"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(script.id.uuidString).json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.exportUnsavedRecording(to: url)
    }
}

/// A separate banner makes cross-script shortcut playback visible without changing selection.
struct PlaybackSessionBanner: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let playing = state.activePlaybackScript,
           playing.id != state.selectedScriptID,
           case .playing(let iteration, _) = state.phase {
            HStack {
                Label("正在回放：\(playing.name)", systemImage: "play.fill")
                Text(playing.repeatForever
                     ? "第 \(iteration) 轮"
                     : "第 \(iteration)/\(playing.repeatCount) 轮")
                Spacer()
                Button("查看回放脚本") { state.selectedScriptID = playing.id }
                Button("停止回放") { state.togglePlay() }
            }
            .padding(12)
            .background(ClickerVisualTheme.controlSurface)
        }
    }
}

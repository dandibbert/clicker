import AppKit
import ClickerCore
import SwiftUI
import UniformTypeIdentifiers

struct ScriptImportCandidate: Identifiable {
    let id = UUID()
    let script: Script
    let sourceName: String
}

struct ScriptImportPresentation: Equatable {
    let name: String
    let metadata: String
    let matchingIdentityName: String?
    let hasNameConflict: Bool
    let clearsShortcut: Bool

    init(script: Script, existingScripts: [Script]) {
        name = script.name
        let header = ScriptHeaderPresentation(script: script)
        metadata = "\(header.actionCountText) · \(header.durationText)"
        matchingIdentityName = existingScripts.first { $0.id == script.id }?.name
        hasNameConflict = existingScripts.contains {
            $0.name.compare(script.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        clearsShortcut = script.playbackShortcut != nil
    }
}

struct ScriptImportPreview: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let candidate: ScriptImportCandidate
    @State private var replaceExisting = false
    @State private var importFailure: String?

    private var presentation: ScriptImportPresentation {
        ScriptImportPresentation(script: candidate.script, existingScripts: state.scripts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing16) {
            Text("导入脚本")
                .font(.title2.weight(.semibold))
                .foregroundStyle(ClickerVisualTheme.primaryText)
            VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing4) {
                Text(presentation.name)
                    .font(.headline)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(presentation.metadata)
                    .font(.caption)
                    .foregroundStyle(ClickerVisualTheme.secondaryText)
                Text(candidate.sourceName)
                    .font(.caption)
                    .foregroundStyle(ClickerVisualTheme.secondaryText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ClickerVisualTheme.spacing12)
            .background(ClickerVisualTheme.controlSurface,
                        in: RoundedRectangle(cornerRadius: ClickerVisualTheme.cardCornerRadius))

            if let existingName = presentation.matchingIdentityName {
                Text("脚本库中已有「\(existingName)」。默认保留两份。")
                Picker("导入方式", selection: $replaceExisting) {
                    Text("保留两份（推荐）").tag(false)
                    Text("替换已有脚本").tag(true)
                }
                .pickerStyle(.radioGroup)
                if replaceExisting {
                    Text("将替换已有脚本的动作与设置；可使用撤销恢复。")
                        .font(.caption)
                        .foregroundStyle(ClickerVisualTheme.secondaryText)
                }
            } else if presentation.hasNameConflict {
                Text("脚本库中已有同名脚本。导入后会保留两份，不会覆盖。")
            }

            Label("导入只会保存脚本，不会回放", systemImage: "doc.badge.plus")
                .font(.callout)
            Text("全局快捷键和启动时切换应用均默认关闭。请先检查动作中的坐标、文本和快捷键，再手动回放。")
                .font(.caption)
                .foregroundStyle(ClickerVisualTheme.secondaryText)
            if let interruption = candidate.script.recordingInterruption {
                Label("部分录制：\(interruption)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
            }
            if let importFailure {
                Label("导入尚未保存：\(importFailure)", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(ClickerVisualTheme.primaryText)
            }
            HStack {
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(replaceExisting ? "替换并导入" : "导入") {
                    if state.importScript(candidate.script, replaceExisting: replaceExisting) {
                        dismiss()
                    } else {
                        importFailure = state.persistenceIssue?.message ?? "当前无法编辑脚本，请稍后重试。"
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!state.canEditScripts)
            }
        }
        .foregroundStyle(ClickerVisualTheme.primaryText)
        .padding(ClickerVisualTheme.spacing24)
        .frame(width: 460)
        .background(ClickerVisualTheme.canvas)
    }
}

/// Native panels only collect paths. Import remains a separate explicit action
/// after decoding and previewing the document.
@MainActor
enum ScriptTransferPanels {
    static func chooseImport() throws -> ScriptImportCandidate? {
        let panel = NSOpenPanel()
        panel.title = "导入脚本或另存的录制"
        panel.message = "选择 Clicker JSON 文件，下一步将显示导入预览。"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let script = try ScriptTransfer.decode(data: Data(contentsOf: url))
        return ScriptImportCandidate(script: script, sourceName: url.lastPathComponent)
    }

    static func export(_ script: Script, state: AppState) {
        let panel = NSSavePanel()
        panel.title = "导出脚本"
        panel.message = "文件包含动作中的输入文本，请只与可信任的人分享。"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = exportFileName(for: script.name)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        state.exportScript(id: script.id, to: url)
    }

    static func exportFileName(for name: String) -> String {
        let sanitized = name.components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(sanitized.isEmpty ? "Clicker 脚本" : sanitized).json"
    }
}

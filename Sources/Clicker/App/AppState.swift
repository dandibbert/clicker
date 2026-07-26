import SwiftUI
import AppKit
import ClickerCore

/// App 全局阶段。
enum AppPhase: Equatable {
    case idle
    case countdown(Int)   // 3, 2, 1
    case recording
    case playing(iteration: Int, currentBlockID: UUID?)
}

/// 全局可观察状态。所有 UI 与引擎通过它交互。
@MainActor
final class AppState: ObservableObject {
    @Published var phase: AppPhase = .idle
    @Published var scripts: [Script] = []
    @Published var selectedScriptID: UUID?
    @Published var hasPermission = Permissions.hasAccessibility
    @Published var corruptFileNames: [String] = []

    let store: ScriptStore

    init(store: ScriptStore = ScriptStore(directory: ScriptStore.defaultDirectory())) {
        self.store = store
        reload()
    }

    func reload() {
        scripts = store.loadAll()
        corruptFileNames = store.corruptFiles
        if selectedScriptID == nil { selectedScriptID = scripts.first?.id }
    }

    var selectedScript: Script? {
        scripts.first { $0.id == selectedScriptID }
    }

    /// 修改并自动保存。
    func update(_ script: Script) {
        var s = script
        s.modifiedAt = Date()
        if let idx = scripts.firstIndex(where: { $0.id == s.id }) {
            scripts[idx] = s
        } else {
            scripts.append(s)
        }
        try? store.save(s)
    }

    func deleteScript(id: UUID) {
        scripts.removeAll { $0.id == id }
        try? store.delete(id: id)
        if selectedScriptID == id { selectedScriptID = scripts.first?.id }
    }

    func duplicateScript(id: UUID) {
        guard var s = scripts.first(where: { $0.id == id }) else { return }
        s.id = UUID()
        s.name += " 副本"
        s.createdAt = Date()
        s.modifiedAt = Date()
        // 块 ID 需要重新生成，避免与原脚本冲突
        s.blocks = s.blocks.map { block in
            switch block {
            case .move(var b): b.id = UUID(); return .move(b)
            case .click(var b): b.id = UUID(); return .click(b)
            case .drag(var b): b.id = UUID(); return .drag(b)
            case .scroll(var b): b.id = UUID(); return .scroll(b)
            case .typeText(var b): b.id = UUID(); return .typeText(b)
            case .shortcut(var b): b.id = UUID(); return .shortcut(b)
            case .wait(var b): b.id = UUID(); return .wait(b)
            }
        }
        update(s)
        selectedScriptID = s.id
    }

    func refreshPermission() {
        hasPermission = Permissions.hasAccessibility
    }

    // MARK: - Recording

    private let recorder = EventRecorder()
    private let countdown = CountdownWindow()
    private var observers: [NSObjectProtocol] = []

    /// ClickerApp 启动时调用一次。
    func setUp() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .toggleRecord, object: nil, queue: .main) { [weak self] note in
            let source = (note.object as? [String: String])?["source"] ?? "ui"
            Task { @MainActor in self?.toggleRecord(source: source) }
        })
        observers.append(center.addObserver(forName: .togglePlay, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
        })
        recorder.onTapFailure = { [weak self] in
            Task { @MainActor in
                self?.finishRecording(source: "failure")
            }
        }
    }

    func toggleRecord(source: String) {
        switch phase {
        case .idle:
            startCountdown()
        case .countdown:
            countdown.close()
            phase = .idle
        case .recording:
            finishRecording(source: source)
        case .playing:
            break  // 回放中忽略录制开关
        }
    }

    private func startCountdown() {
        guard hasPermission else {
            Permissions.requestAccessibility()
            refreshPermission()
            return
        }
        // 隐藏主窗口，避免录到自己
        NSApp.hide(nil)
        phase = .countdown(3)
        countdown.show(seconds: 3) { [weak self] remaining in
            Task { @MainActor in self?.phase = .countdown(remaining) }
        } onFinish: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.recorder.start() {
                    self.phase = .recording
                } else {
                    self.phase = .idle
                    self.refreshPermission()
                }
            }
        }
    }

    private func finishRecording(source: String) {
        var events = recorder.stop()
        phase = .idle

        // 尾部清理：按停止来源裁剪
        switch source {
        case "hotkey":
            events = TailTrimmer.trimHotKeyStop(
                events,
                stopKeyCode: UInt16(HotKeyCenter.recordKeyCode),
                stopFlags: KeyCodeMap.maskOption | KeyCodeMap.maskCommand)
        case "menubar":
            events = TailTrimmer.trimMenuBarStop(events)
        default:
            break
        }

        let blocks = EventGrouper.group(events)
        guard !blocks.isEmpty else {
            NSApp.unhide(nil)
            return
        }
        let name = "录制 \(scripts.count + 1)"
        let script = Script(name: name, blocks: blocks)
        update(script)
        selectedScriptID = script.id
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Task 11 实现回放，这里先占位。
    func togglePlay() {}
}

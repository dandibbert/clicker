import SwiftUI
import AppKit
import CoreGraphics
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
    private let recorder: EventRecording
    private let countdown: CountdownPresenting
    private let application: RecordingApplicationControlling

    init(
        store: ScriptStore = ScriptStore(directory: ScriptStore.defaultDirectory()),
        recorder: EventRecording = EventRecorder(),
        countdown: CountdownPresenting = CountdownWindow(),
        application: RecordingApplicationControlling = SystemRecordingApplicationController()
    ) {
        self.store = store
        self.recorder = recorder
        self.countdown = countdown
        self.application = application
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
        // 块 ID 需要重新生成，避免与原脚本冲突；绝对时间轴保持不变。
        s.blocks = s.blocks.map { $0.duplicated() }
        update(s)
        selectedScriptID = s.id
    }

    func refreshPermission() {
        hasPermission = Permissions.hasAccessibility
    }

    // MARK: - Recording

    private var observers: [NSObjectProtocol] = []
    private var recordingTargetBundleIdentifier: String?

    /// ClickerApp 启动时调用一次。
    func setUp() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .toggleRecord, object: nil, queue: .main) { [weak self] note in
            let source: RecordingStopSource =
                (note.object as? [String: String])?["source"] == "hotkey"
                ? .hotkey
                : .ui
            Task { @MainActor in self?.toggleRecord(source: source) }
        })
        observers.append(center.addObserver(forName: .togglePlay, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
        })
        recorder.onTapFailure = { [weak self] in
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                self.finishRecording(source: .failure)
            }
        }
    }

    func toggleRecord(source: RecordingStopSource) {
        switch phase {
        case .idle:
            startCountdown()
        case .countdown:
            countdown.close()
            phase = .idle
            application.restoreClicker()
        case .recording:
            finishRecording(source: source)
        case .playing:
            break  // 回放中忽略录制开关
        }
    }

    func establishMenuBarCutoff(at timestamp: CGEventTimestamp) -> RecordingCutoff? {
        guard phase == .recording else { return nil }
        return recorder.cutoff(at: timestamp)
    }

    func stopRecordingFromMenuBar(cutoff: RecordingCutoff) {
        guard phase == .recording else { return }
        finishRecording(source: .menubar(cutoff: cutoff))
    }

    private func startCountdown() {
        guard hasPermission else {
            Permissions.requestAccessibility()
            refreshPermission()
            return
        }
        recordingTargetBundleIdentifier = application.frontmostApplicationBundleIdentifier()
        application.hideClicker()
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
                    self.application.restoreClicker()
                }
            }
        }
    }

    private func finishRecording(source: RecordingStopSource) {
        let capture = recorder.stop()
        phase = .idle
        let script = RecordingScriptFactory.makeScript(
            name: "录制 \(scripts.count + 1)",
            capture: capture,
            stopSource: source,
            targetBundleIdentifier: recordingTargetBundleIdentifier
        )
        recordingTargetBundleIdentifier = nil
        guard !script.blocks.isEmpty || script.trailingDelay > 0 else {
            application.restoreClicker()
            return
        }
        update(script)
        selectedScriptID = script.id
        application.restoreClicker()
    }

    // MARK: - Playback

    private let playbackEngine = PlaybackEngine()

    func togglePlay() {
        switch phase {
        case .playing:
            playbackEngine.stop()
            phase = .idle
        case .idle:
            guard hasPermission else {
                Permissions.requestAccessibility()
                refreshPermission()
                return
            }
            guard let script = selectedScript, !script.blocks.isEmpty else { return }
            phase = .playing(iteration: 1, currentBlockID: nil)
            playbackEngine.play(script: script) { [weak self] iteration in
                Task { @MainActor in
                    guard let self, case .playing = self.phase else { return }
                    self.phase = .playing(iteration: iteration, currentBlockID: nil)
                }
            } onBlock: { [weak self] blockID in
                Task { @MainActor in
                    guard let self, case .playing(let it, _) = self.phase else { return }
                    self.phase = .playing(iteration: it, currentBlockID: blockID)
                }
            } onFinish: { [weak self] in
                Task { @MainActor in self?.phase = .idle }
            }
        case .countdown, .recording:
            break
        }
    }
}

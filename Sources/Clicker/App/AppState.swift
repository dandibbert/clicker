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
    @Published var persistenceIssue: ScriptStoreIssue?
    @Published var hotKeyRegistrationIssues: [HotKeyRegistrationIssue] = []
    @Published var appearancePreference: AppAppearancePreference {
        didSet { appearancePreferenceStore.preference = appearancePreference }
    }

    let store: ScriptPersisting
    private let recorder: EventRecording
    private let countdown: CountdownPresenting
    private let application: ApplicationControlling
    let externalApplicationTracker: ExternalApplicationTracking
    private let playbackEngine: PlaybackControlling
    private let stopShortcutStore: RecordingStopShortcutProviding
    private let recordingIndicator: RecordingIndicatorPresenting
    private let appearancePreferenceStore: AppAppearancePreferenceProviding

    init(
        store: ScriptPersisting = ScriptStore(directory: ScriptStore.defaultDirectory()),
        recorder: EventRecording = EventRecorder(),
        countdown: CountdownPresenting = CountdownWindow(),
        application: ApplicationControlling? = nil,
        externalApplicationTracker: ExternalApplicationTracking = SystemExternalApplicationTracker(),
        stopShortcutStore: RecordingStopShortcutProviding = RecordingStopShortcutStore(),
        appearancePreferenceStore: AppAppearancePreferenceProviding = AppAppearancePreferenceStore(),
        recordingIndicator: RecordingIndicatorPresenting? = nil,
        playbackEngine: PlaybackControlling? = nil
    ) {
        self.store = store
        self.recorder = recorder
        self.countdown = countdown
        self.application = application ?? SystemApplicationController()
        self.externalApplicationTracker = externalApplicationTracker
        self.stopShortcutStore = stopShortcutStore
        self.appearancePreferenceStore = appearancePreferenceStore
        self.appearancePreference = appearancePreferenceStore.preference
        self.recordingIndicator = recordingIndicator ?? RecordingIndicatorController()
        self.playbackEngine = playbackEngine ?? PlaybackEngine()
        reload()
    }

    func reload() {
        let result = store.loadAll()
        scripts = result.scripts
        corruptFileNames = result.issues.compactMap(\.fileName)
        persistenceIssue = result.issues.first
        if selectedScriptID == nil { selectedScriptID = scripts.first?.id }
    }

    var selectedScript: Script? {
        scripts.first { $0.id == selectedScriptID }
    }

    var canEditScripts: Bool {
        phase == .idle
    }

    var canStartRecording: Bool {
        phase == .idle
    }

    var recordingStopShortcut: RecordingStopShortcut {
        get { stopShortcutStore.shortcut }
        set { stopShortcutStore.shortcut = newValue }
    }

    @discardableResult
    func create(_ script: Script) -> Bool {
        guard canEditScripts else { return false }
        guard !scripts.contains(where: { $0.id == script.id }) else { return false }
        do {
            try store.save(script)
        } catch {
            persistenceIssue = makePersistenceIssue(from: error, fallback: .replace)
            return false
        }
        scripts.append(script)
        persistenceIssue = nil
        return true
    }

    /// 只修改仍存在的脚本，并在持久化成功后提交到内存。
    @discardableResult
    func update(_ script: Script) -> Bool {
        guard canEditScripts else { return false }
        guard scripts.contains(where: { $0.id == script.id }) else { return false }
        var s = script
        s.modifiedAt = Date()
        do {
            try store.save(s)
        } catch {
            persistenceIssue = makePersistenceIssue(from: error, fallback: .replace)
            return false
        }
        guard let index = scripts.firstIndex(where: { $0.id == s.id }) else { return false }
        scripts[index] = s
        persistenceIssue = nil
        return true
    }

    func deleteScript(id: UUID) {
        guard canEditScripts else { return }
        guard scripts.contains(where: { $0.id == id }) else { return }
        do {
            try store.delete(id: id)
        } catch {
            persistenceIssue = makePersistenceIssue(from: error, fallback: .delete)
            return
        }
        scripts.removeAll { $0.id == id }
        if selectedScriptID == id { selectedScriptID = scripts.first?.id }
        persistenceIssue = nil
    }

    func duplicateScript(id: UUID) {
        guard canEditScripts else { return }
        guard var s = scripts.first(where: { $0.id == id }) else { return }
        s.id = UUID()
        s.name += " 副本"
        s.createdAt = Date()
        s.modifiedAt = Date()
        // 块 ID 需要重新生成，避免与原脚本冲突；绝对时间轴保持不变。
        s.blocks = s.blocks.map { $0.duplicated() }
        if create(s) {
            selectedScriptID = s.id
        }
    }

    func refreshPermission() {
        hasPermission = Permissions.hasAccessibility
    }

    func reportHotKeyRegistrationIssues(_ issues: [HotKeyRegistrationIssue]) {
        hotKeyRegistrationIssues = issues
    }

    // MARK: - Recording

    private var observers: [NSObjectProtocol] = []
    private var recordingTargetBundleIdentifier: String?
    private var activeStopShortcut: RecordingStopShortcut?
    private var recordingCountdownGeneration = 0

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
        observers.append(center.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopPlaybackIfNeeded()
            }
        })
        recorder.onTapFailure = { [weak self] in
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                self.finishRecording(source: .failure)
            }
        }
        recorder.onStopRequest = { [weak self] in
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                self.finishRecording(source: .ui)
            }
        }
    }

    func toggleRecord(source: RecordingStopSource) {
        switch phase {
        case .idle:
            startCountdown()
        case .countdown:
            recordingCountdownGeneration += 1
            closeRecordingIndicator()
            countdown.close()
            phase = .idle
            recordingTargetBundleIdentifier = nil
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
        recordingCountdownGeneration += 1
        let generation = recordingCountdownGeneration
        let target = externalApplicationTracker.mostRecentExternalBundleIdentifier
        recordingTargetBundleIdentifier = target
        activeStopShortcut = stopShortcutStore.shortcut
        phase = .countdown(3)
        countdown.show(seconds: 3) { [weak self] remaining in
            Task { @MainActor in
                guard let self,
                      self.recordingCountdownGeneration == generation,
                      case .countdown = self.phase else { return }
                self.phase = .countdown(remaining)
            }
        } onFinish: { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.recordingCountdownGeneration == generation,
                      case .countdown = self.phase,
                      let stopShortcut = self.activeStopShortcut else { return }
                if self.recorder.start(stopShortcut: stopShortcut) {
                    self.phase = .recording
                    self.recordingIndicator.show(shortcut: stopShortcut)
                } else {
                    self.closeRecordingIndicator()
                    self.phase = .idle
                    self.recordingTargetBundleIdentifier = nil
                    self.refreshPermission()
                    self.application.restoreClicker()
                }
            }
        }
        application.hideClicker()
        if let target {
            _ = application.activateExternalApplication(bundleIdentifier: target)
        }
    }

    private func finishRecording(source: RecordingStopSource) {
        closeRecordingIndicator()
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
        if create(script) {
            selectedScriptID = script.id
        }
        application.restoreClicker()
    }

    private func closeRecordingIndicator() {
        recordingIndicator.close()
        activeStopShortcut = nil
    }

    // MARK: - Playback

    private var playbackGeneration = 0
    private var playbackFocusGeneration: Int?

    func togglePlay() {
        switch phase {
        case .playing:
            stopPlaybackIfNeeded()
        case .idle:
            guard hasPermission else {
                Permissions.requestAccessibility()
                refreshPermission()
                return
            }
            guard let script = selectedScript else { return }
            guard ScriptPlaybackEligibility.isPlayable(script) else { return }
            let fallback = externalApplicationTracker.mostRecentExternalBundleIdentifier
            application.hideClicker()
            activatePlaybackTarget(
                saved: script.targetBundleIdentifier,
                fallback: fallback
            )
            playbackGeneration += 1
            let generation = playbackGeneration
            playbackFocusGeneration = generation
            phase = .playing(iteration: 1, currentBlockID: nil)
            playbackEngine.play(script: script) { [weak self] iteration in
                Task { @MainActor in
                    guard let self,
                          self.playbackGeneration == generation,
                          case .playing = self.phase else { return }
                    self.phase = .playing(iteration: iteration, currentBlockID: nil)
                }
            } onBlock: { [weak self] blockID in
                Task { @MainActor in
                    guard let self,
                          self.playbackGeneration == generation,
                          case .playing(let it, _) = self.phase else { return }
                    self.phase = .playing(iteration: it, currentBlockID: blockID)
                }
            } onFinish: { [weak self] in
                Task { @MainActor in
                    guard let self,
                          self.playbackGeneration == generation,
                          case .playing = self.phase else { return }
                    self.playbackGeneration += 1
                    self.phase = .idle
                    self.restorePlaybackFocus(ownedBy: generation)
                }
            }
        case .countdown, .recording:
            break
        }
    }

    private func stopPlaybackIfNeeded() {
        guard case .playing = phase else { return }
        let generation = playbackGeneration
        playbackGeneration += 1
        playbackEngine.stop()
        phase = .idle
        restorePlaybackFocus(ownedBy: generation)
    }

    private func activatePlaybackTarget(saved: String?, fallback: String?) {
        var attemptedIdentifiers: Set<String> = []
        for identifier in [saved, fallback] {
            guard let identifier,
                  !identifier.isEmpty,
                  identifier != "local.rayscripts.clicker",
                  attemptedIdentifiers.insert(identifier).inserted else { continue }
            if application.activateExternalApplication(bundleIdentifier: identifier) {
                return
            }
        }
    }

    private func restorePlaybackFocus(ownedBy generation: Int) {
        guard playbackFocusGeneration == generation else { return }
        playbackFocusGeneration = nil
        application.restoreClicker()
    }

    private func makePersistenceIssue(
        from error: Error,
        fallback operation: ScriptStoreIssue.Operation
    ) -> ScriptStoreIssue {
        if let issue = error as? ScriptStoreIssue { return issue }
        return ScriptStoreIssue(operation: operation, message: String(describing: error))
    }
}

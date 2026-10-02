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
    @Published var hasPermission = Permissions.hasRequiredAccess
    @Published var hasAccessibilityPermission = Permissions.hasAccessibility
    @Published var hasInputMonitoringPermission = Permissions.hasInputMonitoring
    @Published var recentlyDeletedScripts: [Script] = []
    @Published var pendingPlaybackStart: PlaybackStartRequest?
    @Published private(set) var isPreparingPlayback = false
    @Published var playbackNotice: String?
    @Published var actionClipboard: ActionClipboard?
    @Published var undoEntries: [ScriptLibraryEdit] = []
    @Published var redoEntries: [ScriptLibraryEdit] = []
    var isApplyingHistory = false
    @Published var corruptFileNames: [String] = []
    @Published var persistenceIssue: ScriptStoreIssue?
    @Published private(set) var unsavedRecording: Script?
    @Published var recordingNotice: RecordingNotice?
    /// Immutable session snapshot, independent of the selection in the sidebar.
    @Published private(set) var activePlaybackScript: Script?
    @Published var hotKeyRegistrationIssues: [HotKeyRegistrationIssue] = []
    @Published var scriptHotKeyRegistrationIssues: [ScriptHotKeyRegistrationIssue] = []
    @Published var appearancePreference: AppAppearancePreference {
        didSet { appearancePreferenceStore.preference = appearancePreference }
    }

    let store: ScriptPersisting
    private let recorder: EventRecording
    private let countdown: CountdownPresenting
    private let application: ApplicationControlling
    let externalApplicationTracker: ExternalApplicationTracking
    private let playbackEngine: PlaybackControlling
    private let playbackIndicator: PlaybackIndicatorPresenting
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
        playbackEngine: PlaybackControlling? = nil,
        playbackIndicator: PlaybackIndicatorPresenting? = nil
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
        self.playbackIndicator = playbackIndicator ?? PlaybackIndicatorController()
        reload()
    }

    func reload() {
        let result = store.loadAll()
        scripts = result.scripts
        corruptFileNames = result.issues.compactMap(\.fileName)
        persistenceIssue = result.issues.first
        if selectedScriptID == nil { selectedScriptID = scripts.first?.id }
        refreshRecentlyDeleted()
    }

    var selectedScript: Script? {
        scripts.first { $0.id == selectedScriptID }
    }

    var canEditScripts: Bool {
        phase == .idle && !isPreparingPlayback && pendingPlaybackStart == nil
    }

    var canStartRecording: Bool {
        canEditScripts && unsavedRecording == nil
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
        recordEdit(before: nil, after: script)
        persistenceIssue = nil
        return true
    }

    /// 只修改仍存在的脚本，并在持久化成功后提交到内存。
    @discardableResult
    func update(_ script: Script) -> Bool {
        guard canEditScripts else { return false }
        guard let previous = scripts.first(where: { $0.id == script.id }) else { return false }
        if previous == script { return true }
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
        recordEdit(before: previous, after: s)
        persistenceIssue = nil
        return true
    }

    func deleteScript(id: UUID) {
        guard canEditScripts else { return }
        guard let previous = scripts.first(where: { $0.id == id }) else { return }
        do {
            try store.delete(id: id)
        } catch {
            persistenceIssue = makePersistenceIssue(from: error, fallback: .delete)
            return
        }
        scripts.removeAll { $0.id == id }
        recordEdit(before: previous, after: nil)
        if selectedScriptID == id { selectedScriptID = scripts.first?.id }
        persistenceIssue = nil
        refreshRecentlyDeleted()
    }

    func duplicateScript(id: UUID) {
        guard canEditScripts, let original = scripts.first(where: { $0.id == id }) else { return }
        let copy = ScriptReuse.duplicate(original, name: original.name + " 副本")
        if create(copy) { selectedScriptID = copy.id }
    }

    func refreshPermission() {
        hasAccessibilityPermission = Permissions.hasAccessibility
        hasInputMonitoringPermission = Permissions.hasInputMonitoring
        hasPermission = hasAccessibilityPermission && hasInputMonitoringPermission
    }

    func reportHotKeyRegistrationIssues(_ issues: [HotKeyRegistrationIssue]) {
        hotKeyRegistrationIssues = issues
    }

    func reportScriptHotKeyRegistrationIssues(_ issues: [ScriptHotKeyRegistrationIssue]) {
        scriptHotKeyRegistrationIssues = issues
    }

    // MARK: - Recording

    private var observers: [NSObjectProtocol] = []
    private var recordingTargetBundleIdentifier: String?
    private var activeStopShortcut: RecordingStopShortcut?
    private var recordingCountdownGeneration = 0

    /// ClickerApp 启动时调用一次。
    func setUp() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshPermission() }
        })
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
            guard !isPreparingPlayback, pendingPlaybackStart == nil else { return }
            guard unsavedRecording == nil else {
                recordingNotice = RecordingNotice(
                    title: "有尚未保存的录制",
                    message: "请先重试保存、另存或明确丢弃当前录制，再开始新的录制。"
                )
                application.restoreClicker()
                return
            }
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
            Permissions.requestRequiredAccess()
            refreshPermission()
            return
        }
        recordingNotice = nil
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
                    self.recordingNotice = RecordingNotice(
                        title: "无法开始录制",
                        message: "无法建立输入监听。请检查辅助功能和输入监控权限，然后重试；本次没有开始录制。"
                    )
                    self.application.restoreClicker()
                }
            }
        }
        application.hideClicker()
        if let target {
            _ = application.activateExternalApplication(bundleIdentifier: target)
        }
    }

    private func finishRecording(source: RecordingStopSource, saveImmediately: Bool = true) {
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
        if let interruption = script.recordingInterruption {
            recordingNotice = RecordingNotice(title: "录制意外中断", message: interruption)
        }
        guard !script.blocks.isEmpty || script.trailingDelay > 0 else {
            application.restoreClicker()
            return
        }
        // Retain the only copy before attempting persistence. Dismissing an error cannot lose it.
        unsavedRecording = script
        if saveImmediately { retrySavingRecording() }
        application.restoreClicker()
    }

    @discardableResult
    func retrySavingRecording() -> Bool {
        guard let script = unsavedRecording, phase == .idle else { return false }
        guard create(script) else { return false }
        selectedScriptID = script.id
        unsavedRecording = nil
        return true
    }

    @discardableResult
    func exportUnsavedRecording(to url: URL) -> Bool {
        guard let script = unsavedRecording, phase == .idle else { return false }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .millisecondsSince1970
            try encoder.encode(script).write(to: url, options: .atomic)
            unsavedRecording = nil
            persistenceIssue = nil
            return true
        } catch {
            persistenceIssue = makePersistenceIssue(from: error, fallback: .temporaryWrite)
            return false
        }
    }

    /// Called only after an explicit discard decision in the recovery UI or termination dialog.
    func discardUnsavedRecording() {
        guard phase == .idle else { return }
        unsavedRecording = nil
        persistenceIssue = nil
    }

    /// Freeze capture before presenting a quit dialog, so the dialog itself is not recorded.
    func stageRecordingForTermination(cutoff: RecordingCutoff? = nil) {
        stopPlaybackIfNeeded()
        if phase == .recording {
            let source = cutoff.map { RecordingStopSource.menubar(cutoff: $0) } ?? .ui
            finishRecording(source: source, saveImmediately: false)
        }
    }

    /// A failed save always cancels termination and preserves the exact draft for retry/export.
    func prepareForTermination(_ decision: RecordingTerminationDecision = .save) -> Bool {
        stageRecordingForTermination()
        if unsavedRecording != nil {
            switch decision {
            case .cancel: return false
            case .save:
                guard retrySavingRecording() else { return false }
            case .discard: discardUnsavedRecording()
            }
        }
        if case .countdown = phase { toggleRecord(source: .ui) }
        stopPlaybackIfNeeded()
        return true
    }

    private func closeRecordingIndicator() {
        recordingIndicator.close()
        activeStopShortcut = nil
    }

    // MARK: - Playback

    private var playbackGeneration = 0
    private var playbackFocusGeneration: Int?

    func togglePlay() {
        if isPreparingPlayback {
            cancelPreparingPlayback()
            return
        }
        switch phase {
        case .playing:
            stopPlaybackIfNeeded()
        case .idle:
            guard pendingPlaybackStart == nil else { return }
            guard hasPermission else {
                Permissions.requestRequiredAccess()
                refreshPermission()
                return
            }
            guard let script = selectedScript, ScriptPlaybackEligibility.isPlayable(script) else { return }
            requestPlayback(script: script, restoresClicker: true)
        case .countdown, .recording:
            break
        }
    }

    /// Global shortcuts keep the selected script and do not reclaim focus after successful playback.
    func playScriptFromShortcut(id: UUID) {
        guard canEditScripts, hasPermission,
              let script = scripts.first(where: { $0.id == id }),
              ScriptPlaybackEligibility.isPlayable(script) else { return }
        requestPlayback(script: script, restoresClicker: false)
    }

    func trialActions(scriptID: UUID, blockIDs: Set<UUID>) {
        guard canEditScripts, hasPermission,
              let source = scripts.first(where: { $0.id == scriptID }),
              let trial = ScriptReuse.trial(source, selectedBlockIDs: blockIDs),
              ScriptPlaybackEligibility.isPlayable(trial) else { return }
        requestPlayback(script: trial, restoresClicker: true)
    }

    private func requestPlayback(script: Script, restoresClicker: Bool) {
        playbackNotice = nil
        if restoresClicker { application.hideClicker() }
        // Free playback never silently binds to the recording app or a remembered fallback.
        guard script.startApplicationBeforePlayback else {
            if restoresClicker {
                playbackGeneration += 1
                let generation = playbackGeneration
                isPreparingPlayback = true
                application.verifyClickerDeactivation { [weak self] succeeded in
                    guard let self, self.playbackGeneration == generation, self.isPreparingPlayback else { return }
                    self.isPreparingPlayback = false
                    guard succeeded, self.hasPermission else {
                        self.playbackNotice = "未开始回放：请确认系统权限，并让需要操作的应用处于前台后重试。"
                        self.application.restoreClicker()
                        return
                    }
                    self.startPlayback(script: script, restoresClicker: restoresClicker)
                }
            } else {
                startPlayback(script: script, restoresClicker: false)
            }
            return
        }
        let identifier = script.targetBundleIdentifier ?? ""
        playbackGeneration += 1
        let generation = playbackGeneration
        isPreparingPlayback = true
        guard !identifier.isEmpty, identifier != "local.rayscripts.clicker",
              application.activateExternalApplication(bundleIdentifier: identifier) else {
            offerFreePlayback(script: script, appIdentifier: identifier, restoresClicker: restoresClicker)
            return
        }
        application.verifyExternalApplicationActivation(bundleIdentifier: identifier) { [weak self] succeeded in
            guard let self, self.playbackGeneration == generation, self.isPreparingPlayback else { return }
            self.isPreparingPlayback = false
            guard self.hasPermission else {
                self.playbackNotice = "权限发生变化，未开始回放。"
                self.application.restoreClicker()
                return
            }
            if succeeded {
                self.startPlayback(script: script, restoresClicker: restoresClicker)
            } else {
                self.offerFreePlayback(script: script, appIdentifier: identifier, restoresClicker: restoresClicker)
            }
        }
    }

    private func offerFreePlayback(script: Script, appIdentifier: String, restoresClicker: Bool) {
        isPreparingPlayback = false
        pendingPlaybackStart = PlaybackStartRequest(script: script, appIdentifier: appIdentifier, restoresClicker: restoresClicker)
        application.restoreClicker()
    }

    func continuePendingPlayback() {
        guard phase == .idle, let pending = pendingPlaybackStart else { return }
        pendingPlaybackStart = nil
        guard hasPermission else { playbackNotice = "权限发生变化，未开始回放。"; return }
        var freeScript = pending.script
        freeScript.startApplicationBeforePlayback = false
        requestPlayback(script: freeScript, restoresClicker: true)
    }

    func cancelPendingPlayback() {
        pendingPlaybackStart = nil
        playbackGeneration += 1
        playbackNotice = "已取消开始回放，没有发送输入。"
    }

    private func cancelPreparingPlayback() {
        guard isPreparingPlayback else { return }
        isPreparingPlayback = false
        playbackGeneration += 1
        application.restoreClicker()
        playbackNotice = "已取消开始回放，没有发送输入。"
    }

    private func startPlayback(script: Script, restoresClicker: Bool) {
        playbackGeneration += 1
        let generation = playbackGeneration
        playbackFocusGeneration = restoresClicker ? generation : nil
        activePlaybackScript = script
        phase = .playing(iteration: 1, currentBlockID: nil)
        playbackIndicator.prepare(script: script)
        playbackIndicator.show(progress: PlaybackProgress(script: script)) { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            self.stopPlaybackIfNeeded()
        }
        playbackEngine.onProgress = { [weak self] progress in
            guard let self, self.playbackGeneration == generation, case .playing = self.phase else { return }
            self.playbackIndicator.update(progress: progress)
        }
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
                      case .playing(let iteration, _) = self.phase else { return }
                self.phase = .playing(iteration: iteration, currentBlockID: blockID)
            }
        } onFinish: { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.playbackGeneration == generation,
                      case .playing = self.phase else { return }
                self.playbackGeneration += 1
                self.phase = .idle
                self.activePlaybackScript = nil
                self.playbackIndicator.close()
                switch self.playbackEngine.completionReason {
                case .userStopped: self.playbackNotice = "已停止回放，按住的键与鼠标已释放。"
                case .preparationFailed(let message): self.playbackNotice = "未开始回放：" + message
                case .interrupted(let message): self.playbackNotice = "回放中断：" + message
                case .completed, nil: self.playbackNotice = "回放输入已发送完毕。"
                }
                self.restorePlaybackFocus(ownedBy: generation)
            }
        }
    }

    private func stopPlaybackIfNeeded() {
        if isPreparingPlayback { cancelPreparingPlayback() }
        pendingPlaybackStart = nil
        guard case .playing = phase else { return }
        let generation = playbackGeneration
        playbackGeneration += 1
        playbackEngine.stop()
        playbackIndicator.close()
        playbackEngine.onProgress = nil
        phase = .idle
        activePlaybackScript = nil
        playbackNotice = "已停止回放，按住的键与鼠标已释放。"
        restorePlaybackFocus(ownedBy: generation)
    }

    private func restorePlaybackFocus(ownedBy generation: Int) {
        guard playbackFocusGeneration == generation else { return }
        playbackFocusGeneration = nil
        application.restoreClicker()
    }

    func makePersistenceIssue(
        from error: Error,
        fallback operation: ScriptStoreIssue.Operation
    ) -> ScriptStoreIssue {
        if let issue = error as? ScriptStoreIssue { return issue }
        return ScriptStoreIssue(operation: operation, message: String(describing: error))
    }
}

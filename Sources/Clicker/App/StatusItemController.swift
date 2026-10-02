import AppKit
import Combine
import CoreGraphics

@MainActor
final class StatusItemController: NSObject {
    private let state: AppState
    private let statusItem: NSStatusItem
    private var phaseObservation: AnyCancellable?
    private var isPresentingMenu = false
    private var trackingArea: NSTrackingArea?

    private lazy var recordingCutoff = MenuBarRecordingCutoffController(
        establishCutoff: { [weak state] timestamp in
            state?.establishMenuBarCutoff(at: timestamp)
        },
        stopRecording: { [weak state] cutoff in
            state?.stopRecordingFromMenuBar(cutoff: cutoff)
        }
    )

    init(state: AppState) {
        self.state = state
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(openMenu(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            let trackingArea = NSTrackingArea(
                rect: button.bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )
            button.addTrackingArea(trackingArea)
            self.trackingArea = trackingArea
        }
        phaseObservation = state.$phase.sink { [weak self] phase in
            self?.updateIcon(for: phase)
        }
    }

    @objc private func openMenu(_ sender: NSStatusBarButton) {
        guard !isPresentingMenu else { return }
        let timestamp = NSApp.currentEvent?.cgEvent?.timestamp
            ?? clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        recordingCutoff.menuWillOpen(at: timestamp)

        isPresentingMenu = true
        statusItem.menu = makeMenu()
        sender.performClick(nil)
        statusItem.menu = nil
        isPresentingMenu = false
        recordingCutoff.interactionCancelled()
    }

    @objc func mouseEntered(with event: NSEvent) {
        recordingCutoff.interactionBegan(at: timestamp(for: event))
    }

    @objc func mouseExited(with _: NSEvent) {
        if !isPresentingMenu {
            recordingCutoff.interactionCancelled()
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        switch state.phase {
        case .idle:
            let recordItem = item(title: "开始录制", action: #selector(toggleRecording))
            recordItem.isEnabled = state.canStartRecording
            menu.addItem(recordItem)
            menu.addItem(item(title: "回放", action: #selector(togglePlayback)))
        case .countdown:
            menu.addItem(item(title: "取消录制", action: #selector(toggleRecording)))
        case .recording:
            menu.addItem(item(title: "停止录制", action: #selector(stopRecording)))
        case .playing:
            menu.addItem(item(title: "停止回放", action: #selector(togglePlayback)))
        }
        menu.addItem(.separator())
        menu.addItem(item(title: "退出 Clicker", action: #selector(terminate)))
        return menu
    }

    private func item(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func timestamp(for event: NSEvent) -> CGEventTimestamp {
        event.cgEvent?.timestamp ?? clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }

    private func updateIcon(for phase: AppPhase) {
        let symbolName: String
        switch phase {
        case .idle: symbolName = "cursorarrow.click.2"
        case .countdown: symbolName = "timer"
        case .recording: symbolName = "record.circle.fill"
        case .playing: symbolName = "play.circle.fill"
        }
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Clicker"
        )
    }

    @objc private func toggleRecording() {
        state.toggleRecord(source: .ui)
    }

    @objc private func stopRecording() {
        recordingCutoff.stopSelected()
    }

    @objc private func togglePlayback() {
        state.togglePlay()
    }

    @objc private func terminate() {
        // Exclude the status menu interaction just as the normal Stop item does.
        if let cutoff = recordingCutoff.takePendingCutoff() {
            state.stageRecordingForTermination(cutoff: cutoff)
        }
        NSApp.terminate(nil)
    }
}

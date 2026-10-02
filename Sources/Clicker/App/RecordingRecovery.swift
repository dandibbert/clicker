import AppKit
import ClickerCore

struct RecordingNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

enum RecordingTerminationDecision {
    case save, cancel, discard
}

/// NSApplication's cancellable termination point covers Cmd-Q, the Dock, and the status menu.
@MainActor
final class ClickerApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state else { return .terminateNow }
        // currentEvent can be stale during Dock/Apple-event termination. Only the
        // status-menu action supplies its explicit cutoff before reaching here.
        state.stageRecordingForTermination()
        var decision = RecordingTerminationDecision.save
        if let draft = state.unsavedRecording {
            let alert = NSAlert()
            alert.messageText = "退出前保存录制？"
            alert.informativeText = "「\(draft.name)」尚未保存。录制已停止；取消退出后仍可重试保存或另存。"
            alert.addButton(withTitle: "保存并退出")
            alert.addButton(withTitle: "取消退出")
            alert.addButton(withTitle: "丢弃并退出")
            alert.buttons[1].keyEquivalent = "\u{1b}"
            switch alert.runModal() {
            case .alertFirstButtonReturn: decision = .save
            case .alertThirdButtonReturn: decision = .discard
            default: decision = .cancel
            }
        }
        return state.prepareForTermination(decision) ? .terminateNow : .terminateCancel
    }
}

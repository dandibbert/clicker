import ClickerCore

enum RecordingStopSource: Equatable, Sendable {
    case ui
    case menubar(cutoff: RecordingCutoff)
    case hotkey
    case failure
}

enum RecordingScriptFactory {
    static func makeScript(
        name: String,
        capture: RecordingCapture,
        stopSource: RecordingStopSource,
        targetBundleIdentifier: String?
    ) -> Script {
        let processedCapture: RecordingCapture
        switch stopSource {
        case .ui, .failure:
            processedCapture = capture
        case .menubar(let cutoff):
            processedCapture = TailTrimmer.trim(capture, at: cutoff)
        case .hotkey:
            processedCapture = TailTrimmer.trimHotKeyStop(
                capture,
                stopKeyCode: UInt16(HotKeyCenter.recordKeyCode),
                stopFlags: KeyCodeMap.maskOption | KeyCodeMap.maskCommand
            )
        }

        let timeline = EventGrouper.group(processedCapture)
        return Script(
            name: name,
            blocks: timeline.blocks,
            trailingDelay: timeline.trailingDelay,
            targetBundleIdentifier: targetBundleIdentifier
        )
    }
}

import AppKit
import SwiftUI

struct ShortcutCaptureController {
    func candidate(keyCode: UInt16, flags: UInt64) -> RecordingStopShortcut? {
        guard !(54...63).contains(keyCode) else { return nil }
        return RecordingStopShortcut(keyCode: keyCode, modifierFlags: flags)
    }
}

struct ShortcutCaptureView: NSViewRepresentable {
    let onCandidate: (RecordingStopShortcut) -> Void

    func makeNSView(context: Context) -> CaptureKeyView {
        CaptureKeyView(onCandidate: onCandidate)
    }

    func updateNSView(_ nsView: CaptureKeyView, context: Context) {
        nsView.onCandidate = onCandidate
        DispatchQueue.main.async { [weak nsView] in
            nsView?.requestCaptureFocus()
        }
    }

    static func dismantleNSView(_ nsView: CaptureKeyView, coordinator: ()) {
        nsView.stopCapturing()
    }
}

final class CaptureKeyView: NSView {
    var onCandidate: (RecordingStopShortcut) -> Void
    private let controller = ShortcutCaptureController()
    private var isCaptureActive = true

    init(onCandidate: @escaping (RecordingStopShortcut) -> Void) {
        self.onCandidate = onCandidate
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { isCaptureActive }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestCaptureFocus()
    }

    func requestCaptureFocus() {
        guard isCaptureActive, let window else { return }
        window.makeFirstResponder(self)
    }

    func stopCapturing() {
        isCaptureActive = false
        if let window, window.firstResponder === self {
            window.makeFirstResponder(nil)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, window != nil { stopCapturing() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func keyDown(with event: NSEvent) {
        guard isCaptureActive, let candidate = controller.candidate(
            keyCode: event.keyCode,
            flags: UInt64(event.modifierFlags.rawValue)
        ) else { return }
        onCandidate(candidate)
    }
}

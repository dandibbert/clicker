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
            guard let nsView else { return }
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class CaptureKeyView: NSView {
    var onCandidate: (RecordingStopShortcut) -> Void
    private let controller = ShortcutCaptureController()

    init(onCandidate: @escaping (RecordingStopShortcut) -> Void) {
        self.onCandidate = onCandidate
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard let candidate = controller.candidate(
            keyCode: event.keyCode,
            flags: UInt64(event.modifierFlags.rawValue)
        ) else { return }
        onCandidate(candidate)
    }
}

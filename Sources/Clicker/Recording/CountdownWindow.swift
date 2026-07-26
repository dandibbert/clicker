import AppKit
import SwiftUI

/// 屏幕中央 3-2-1 倒数浮层。无边框、置顶、不抢焦点。
final class CountdownWindow {
    private var window: NSPanel?
    private var timer: Timer?

    /// 显示倒数，每秒回调 onTick(剩余秒数)，结束后回调 onFinish。
    func show(seconds: Int, onTick: @escaping (Int) -> Void, onFinish: @escaping () -> Void) {
        let size: CGFloat = 160
        guard let screen = NSScreen.main else { onFinish(); return }
        let frame = NSRect(
            x: screen.frame.midX - size / 2, y: screen.frame.midY - size / 2,
            width: size, height: size)

        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: CountdownLabel(value: seconds))
        panel.orderFrontRegardless()
        window = panel

        var remaining = seconds
        onTick(remaining)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            remaining -= 1
            if remaining <= 0 {
                t.invalidate()
                self?.timer = nil
                self?.close()
                onFinish()
            } else {
                onTick(remaining)
                self?.window?.contentView = NSHostingView(rootView: CountdownLabel(value: remaining))
            }
        }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
    }
}

private struct CountdownLabel: View {
    let value: Int

    var body: some View {
        Text("\(value)")
            .font(.system(size: 96, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 160, height: 160)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 24))
    }
}

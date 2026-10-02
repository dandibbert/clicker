import AppKit
import SwiftUI

/// AppKit uses an upward Y axis; recorded Quartz events use the primary
/// display's top-left origin. NSScreen.main is the focused display, not primary.
enum DesktopCoordinateSpace {
    static func quartzPoint(_ point: CGPoint, primaryFrame: CGRect) -> CGPoint {
        CGPoint(x: point.x - primaryFrame.minX, y: primaryFrame.maxY - point.y)
    }

    static func quartzFrame(_ frame: CGRect, primaryFrame: CGRect) -> CGRect {
        CGRect(x: frame.minX - primaryFrame.minX, y: primaryFrame.maxY - frame.maxY,
               width: frame.width, height: frame.height)
    }
}

/// Local windows consume the click instead of forwarding it to the target app.
/// This does not capture screen pixels or install any global event monitor.
@MainActor
final class CoordinatePickerController: ObservableObject {
    @Published private(set) var isPicking = false
    private var panels: [NSPanel] = []
    private var hiddenWindows: [NSWindow] = []
    private weak var previousKeyWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var completion: ((CGPoint?) -> Void)?

    func pick(completion: @escaping (CGPoint?) -> Void) {
        guard !isPicking, let primary = NSScreen.screens.first else { return }
        self.completion = completion
        isPicking = true
        previousKeyWindow = NSApp.keyWindow
        hiddenWindows = NSApp.windows.filter { $0.isVisible }
        hiddenWindows.forEach { $0.orderOut(nil) }
        for screen in NSScreen.screens {
            let panel = CoordinatePickerPanel(contentRect: screen.frame, styleMask: [.borderless],
                                               backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.acceptsMouseMovedEvents = true
            let overlay = CoordinatePickerOverlay(frame: CGRect(origin: .zero, size: screen.frame.size))
            overlay.onPick = { [weak self] appKitPoint in
                self?.finish(DesktopCoordinateSpace.quartzPoint(appKitPoint, primaryFrame: primary.frame))
            }
            overlay.onCancel = { [weak self] in self?.cancel() }
            panel.contentView = overlay
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        // Key events, including Escape, stay local to the picker.
        let pointer = NSEvent.mouseLocation
        let activePanel = panels.first { $0.frame.contains(pointer) } ?? panels.first
        activePanel?.makeKey()
        activePanel?.makeFirstResponder(activePanel?.contentView)
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSApplication.didChangeScreenParametersNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            })
        }
        NSCursor.crosshair.set()
    }

    func cancel() { finish(nil) }

    private func finish(_ point: CGPoint?) {
        guard isPicking else { return }
        let callback = completion
        completion = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        panels.forEach { $0.orderOut(nil); $0.close() }
        panels.removeAll()
        hiddenWindows.reversed().forEach { $0.orderFront(nil) }
        hiddenWindows.removeAll()
        if NSApp.isActive { previousKeyWindow?.makeKeyAndOrderFront(nil) }
        previousKeyWindow = nil
        NSCursor.arrow.set()
        isPicking = false
        callback?(point)
    }
}

private final class CoordinatePickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CoordinatePickerOverlay: NSView {
    var onPick: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?
    private var pendingPoint: CGPoint?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.08).setFill()
        bounds.fill()
        let message = "单击选择位置 · Esc 取消 · 不会点击下方应用"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (message as NSString).size(withAttributes: attributes)
        let box = CGRect(x: (bounds.width - size.width) / 2 - 18, y: bounds.height - 96,
                         width: size.width + 36, height: size.height + 24)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        (message as NSString).draw(at: CGPoint(x: box.minX + 18, y: box.minY + 12), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        pendingPoint = window.convertPoint(toScreen: event.locationInWindow)
    }
    override func mouseUp(with event: NSEvent) {
        guard let point = pendingPoint else { return }
        pendingPoint = nil
        onPick?(point)
    }
    override func rightMouseDown(with event: NSEvent) { }
    override func rightMouseUp(with event: NSEvent) { onCancel?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
        // All other input is swallowed while picking, including Return/Space.
    }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

struct CoordinatePreview: View {
    let points: [CGPoint]

    var body: some View {
        Canvas { context, size in
            guard let primary = NSScreen.screens.first else { return }
            let screens = NSScreen.screens.map {
                DesktopCoordinateSpace.quartzFrame($0.frame, primaryFrame: primary.frame)
            }
            guard let first = screens.first else { return }
            let desktop = screens.dropFirst().reduce(first) { $0.union($1) }
            let scale = min((size.width - 12) / max(1, desktop.width),
                            (size.height - 12) / max(1, desktop.height))
            let origin = CGPoint(x: (size.width - desktop.width * scale) / 2,
                                 y: (size.height - desktop.height * scale) / 2)
            func map(_ p: CGPoint) -> CGPoint {
                CGPoint(x: origin.x + (p.x - desktop.minX) * scale,
                        y: origin.y + (p.y - desktop.minY) * scale)
            }
            for screen in screens {
                let rect = CGRect(origin: map(screen.origin),
                                  size: CGSize(width: screen.width * scale, height: screen.height * scale))
                context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(ClickerVisualTheme.elevatedSurface))
                context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(ClickerVisualTheme.separator), lineWidth: 1)
            }
            for (index, point) in points.enumerated() where screens.contains(where: { $0.contains(point) }) {
                let p = map(point)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                             with: .color(ClickerVisualTheme.primaryText))
                context.draw(Text("\(index + 1)").font(.caption2).foregroundColor(ClickerVisualTheme.primaryText),
                             at: CGPoint(x: p.x + 9, y: p.y), anchor: .leading)
            }
        }
        .accessibilityLabel("屏幕位置示意图")
        .accessibilityValue(points.map { "X \($0.x), Y \($0.y)" }.joined(separator: "；"))
    }
}

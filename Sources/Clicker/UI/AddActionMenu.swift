import AppKit
import ClickerCore
import SwiftUI

struct AddActionMenu: NSViewRepresentable {
    let isEnabled: Bool
    let onSelect: (ActionBlock) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = AddActionPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.setAccessibilityLabel("添加动作")
        button.toolTip = "添加动作"

        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "添加动作", action: nil, keyEquivalent: "")
        title.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        menu.addItem(title)
        for choice in Choice.allCases {
            let item = NSMenuItem(
                title: choice.title,
                action: #selector(Coordinator.select(_:)),
                keyEquivalent: ""
            )
            item.target = context.coordinator
            item.representedObject = choice.rawValue
            menu.addItem(item)
        }
        button.menu = menu
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        button.isEnabled = isEnabled
    }

    final class Coordinator: NSObject {
        var onSelect: (ActionBlock) -> Void

        init(onSelect: @escaping (ActionBlock) -> Void) {
            self.onSelect = onSelect
        }

        @objc func select(_ sender: NSMenuItem) {
            guard let rawValue = sender.representedObject as? Int,
                  let choice = Choice(rawValue: rawValue) else { return }
            onSelect(choice.block)
        }
    }

    private enum Choice: Int, CaseIterable {
        case click
        case typeText
        case shortcut
        case wait
        case move

        var title: String {
            switch self {
            case .click: "点击"
            case .typeText: "输入文本"
            case .shortcut: "快捷键"
            case .wait: "等待"
            case .move: "移动鼠标"
            }
        }

        var block: ActionBlock {
            switch self {
            case .click:
                .click(ClickBlock(x: 500, y: 400, button: .left, clickCount: 1))
            case .typeText:
                .typeText(TypeTextBlock(text: "文本", keystrokes: []))
            case .shortcut:
                .shortcut(ShortcutBlock(keyCode: 8, flags: KeyCodeMap.maskCommand))
            case .wait:
                .wait(WaitBlock(duration: 1))
            case .move:
                .move(MoveBlock(duration: 0.5, points: [
                    TrackPoint(t: 0, x: 400, y: 300),
                    TrackPoint(t: 0.5, x: 600, y: 400),
                ]))
            }
        }
    }
}

private final class AddActionPopUpButton: NSPopUpButton {
    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: max(32, size.width), height: max(32, size.height))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, isEnabled, bounds.contains(point) else { return nil }
        return self
    }
}

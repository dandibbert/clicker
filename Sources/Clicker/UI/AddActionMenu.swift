import AppKit
import ClickerCore
import SwiftUI

/// A menu choice is only an editor kind. It never creates or persists an action.
enum AddActionKind: Int, CaseIterable {
    case click, typeText, shortcut, wait, move, drag, scroll

    var title: String {
        switch self {
        case .click: "点击"
        case .typeText: "输入文本"
        case .shortcut: "快捷键"
        case .wait: "等待"
        case .move: "移动鼠标"
        case .drag: "拖拽"
        case .scroll: "滚动"
        }
    }

    init(block: ActionBlock) {
        switch block {
        case .click: self = .click
        case .typeText: self = .typeText
        case .shortcut: self = .shortcut
        case .wait: self = .wait
        case .move: self = .move
        case .drag: self = .drag
        case .scroll: self = .scroll
        }
    }
}

struct AddActionMenu: NSViewRepresentable {
    let isEnabled: Bool
    let onSelect: (AddActionKind) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

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
        for choice in AddActionKind.allCases {
            let item = NSMenuItem(title: choice.title, action: #selector(Coordinator.select(_:)), keyEquivalent: "")
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
        var onSelect: (AddActionKind) -> Void
        init(onSelect: @escaping (AddActionKind) -> Void) { self.onSelect = onSelect }
        @objc func select(_ sender: NSMenuItem) {
            guard let rawValue = sender.representedObject as? Int,
                  let choice = AddActionKind(rawValue: rawValue) else { return }
            onSelect(choice)
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

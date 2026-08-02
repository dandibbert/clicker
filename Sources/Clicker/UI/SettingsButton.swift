import AppKit
import SwiftUI

struct SettingsButton: NSViewRepresentable {
    let openSettings: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(openSettings: openSettings)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = SettingsNSButton(
            image: NSImage(
                systemSymbolName: "gearshape",
                accessibilityDescription: "设置"
            ) ?? NSImage(),
            target: context.coordinator,
            action: #selector(Coordinator.performOpenSettings)
        )
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.setAccessibilityLabel("设置")
        button.toolTip = "设置"
        button.isEnabled = context.environment.isEnabled
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.openSettings = openSettings
        button.isEnabled = context.environment.isEnabled
    }

    final class Coordinator: NSObject {
        var openSettings: () -> Void

        init(openSettings: @escaping () -> Void) {
            self.openSettings = openSettings
        }

        @objc func performOpenSettings() {
            openSettings()
        }
    }
}

private final class SettingsNSButton: NSButton {
    override var intrinsicContentSize: NSSize {
        NSSize(width: 32, height: 32)
    }
}

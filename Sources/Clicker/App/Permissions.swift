import AppKit
import ApplicationServices

enum Permissions {
    /// 是否已授予辅助功能权限。
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统授权提示（把 app 加入辅助功能列表）。
    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    /// 打开系统设置的辅助功能面板。
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

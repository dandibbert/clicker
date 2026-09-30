import AppKit
import ApplicationServices
import CoreGraphics

enum Permissions {
    static var hasRequiredAccess: Bool {
        hasAccessibility && hasInputMonitoring
    }

    /// 是否已授予辅助功能权限。
    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// 监听键盘事件需要输入监控授权；仅有辅助功能权限并不总是足够。
    static var hasInputMonitoring: Bool {
        CGPreflightListenEventAccess()
    }

    /// 弹出系统授权提示（把 app 加入辅助功能列表）。
    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    static func requestRequiredAccess() {
        requestAccessibility()
        _ = CGRequestListenEventAccess()
    }

    /// 打开系统设置的辅助功能面板。
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func openRelevantSettings() {
        let pane = hasAccessibility ? "Privacy_ListenEvent" : "Privacy_Accessibility"
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

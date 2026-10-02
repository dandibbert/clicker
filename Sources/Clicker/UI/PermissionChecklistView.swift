import AppKit
import CoreGraphics
import SwiftUI

struct PermissionChecklistPresentation: Equatable {
    let hasAccessibility: Bool
    let hasInputMonitoring: Bool

    var grantedCount: Int { (hasAccessibility ? 1 : 0) + (hasInputMonitoring ? 1 : 0) }
    var isReady: Bool { grantedCount == 2 }
    var summary: String { isReady ? "录制与回放权限已就绪" : "录制与回放需要系统权限" }
}

struct PermissionChecklistView: View {
    @EnvironmentObject private var state: AppState

    private var presentation: PermissionChecklistPresentation {
        PermissionChecklistPresentation(
            hasAccessibility: state.hasAccessibilityPermission,
            hasInputMonitoring: state.hasInputMonitoringPermission
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing16) {
            Text("系统权限")
                .font(.headline)
            Text("未授权时仍可新建、编辑、导入和导出脚本。录制与回放需要以下两项权限，以捕获输入并可靠停止。")
                .font(.callout)
                .foregroundStyle(ClickerVisualTheme.secondaryText)
            permissionRow(
                title: "辅助功能",
                detail: "发送鼠标与键盘操作",
                granted: presentation.hasAccessibility,
                action: {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            )
            permissionRow(
                title: "输入监控",
                detail: "录制输入，并监听停止操作",
                granted: presentation.hasInputMonitoring,
                action: openInputMonitoringSettings
            )
            Divider()
            HStack {
                Text("返回 Clicker 时自动重新检测")
                    .font(.caption)
                    .foregroundStyle(ClickerVisualTheme.secondaryText)
                Spacer()
                Button("重新检测") { state.refreshPermission() }
                    .buttonStyle(.bordered)
            }
        }
        .foregroundStyle(ClickerVisualTheme.primaryText)
        .tint(ClickerVisualTheme.focusRing)
        .padding(ClickerVisualTheme.spacing16)
        .frame(width: 370)
        .background(ClickerVisualTheme.canvas)
    }

    private func permissionRow(
        title: String,
        detail: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: ClickerVisualTheme.spacing8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ClickerVisualTheme.spacing4) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(ClickerVisualTheme.secondaryText)
            }
            Spacer()
            if granted {
                Text("已授权").font(.caption)
            } else {
                Button("授予权限…", action: action)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("请求\(title)权限并打开系统设置")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title)，\(granted ? "已授权" : "未授权")")
    }

    private func openInputMonitoringSettings() {
        _ = CGRequestListenEventAccess()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else { return }
        NSWorkspace.shared.open(url)
    }
}

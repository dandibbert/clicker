import AppKit
import SwiftUI

enum ClickerVisualTheme {
    static let canvas = dynamicColor(light: "F1EADC", dark: "151418", name: "clicker.canvas")
    static let cardSurface = dynamicColor(light: "FAF4E8", dark: "232126", name: "clicker.cardSurface")
    static let elevatedSurface = dynamicColor(light: "FFFFFF", dark: "2C292E", name: "clicker.elevatedSurface")
    static let primaryText = dynamicColor(light: "171619", dark: "F1EADC", name: "clicker.primaryText")
    static let secondaryText = dynamicColor(light: "8B847A", dark: "B8B1A8", name: "clicker.secondaryText")
    static let separator = dynamicColor(light: "D2CBC0", dark: "403C42", name: "clicker.separator")
    static let selection = dynamicColor(light: "E7DDD0", dark: "302D32", name: "clicker.selection")
    static let accent = dynamicColor(light: "E73836", dark: "E73836", name: "clicker.accent")
    static let recordFill = dynamicColor(light: "E73836", dark: "E73836", name: "clicker.recordFill")
    static let playbackFill = dynamicColor(light: "171619", dark: "F1EADC", name: "clicker.playbackFill")
    static let activeTrail = dynamicColor(light: "E73836", dark: "E73836", name: "clicker.activeTrail")

    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24
    static let cardCornerRadius: CGFloat = 10
    static let panelCornerRadius: CGFloat = 14
    static let primaryControlHeight: CGFloat = 34

    private static func dynamicColor(light: String, dark: String, name: String) -> Color {
        let lightColor = nsColor(hex: light)
        let darkColor = nsColor(hex: dark)
        let dynamicColor = NSColor(name: NSColor.Name(name)) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        }
        return Color(nsColor: dynamicColor)
    }

    private static func nsColor(hex: String) -> NSColor {
        let value = UInt64(hex, radix: 16) ?? 0
        return NSColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

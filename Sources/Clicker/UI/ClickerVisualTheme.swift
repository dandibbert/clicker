import AppKit
import SwiftUI

enum ClickerVisualTheme {
    enum ColorRole: String, CaseIterable {
        case canvas
        case cardSurface
        case elevatedSurface
        case primaryText
        case secondaryText
        case separator
        case selection
        case accent
        case recordFill
        case playbackFill
        case activeTrail
    }

    static let canvas = color(for: .canvas)
    static let cardSurface = color(for: .cardSurface)
    static let elevatedSurface = color(for: .elevatedSurface)
    static let primaryText = color(for: .primaryText)
    static let secondaryText = color(for: .secondaryText)
    static let separator = color(for: .separator)
    static let selection = color(for: .selection)
    static let accent = color(for: .accent)
    static let recordFill = color(for: .recordFill)
    static let playbackFill = color(for: .playbackFill)
    static let activeTrail = color(for: .activeTrail)

    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24
    static let cardCornerRadius: CGFloat = 10
    static let panelCornerRadius: CGFloat = 14
    static let primaryControlHeight: CGFloat = 34

    static func resolvedColor(for role: ColorRole, appearance: NSAppearance) -> NSColor {
        let palette = palette(for: role)
        return (isDarkAppearance(appearance) ? palette.dark : palette.light).nsColor
    }

    private static func color(for role: ColorRole) -> Color {
        let dynamicColor = NSColor(name: NSColor.Name("clicker.\(role.rawValue)")) { appearance in
            resolvedColor(for: role, appearance: appearance)
        }
        return Color(nsColor: dynamicColor)
    }

    private static func palette(for role: ColorRole) -> (light: RGB, dark: RGB) {
        switch role {
        case .canvas:
            (.warmWhite, .darkCanvas)
        case .cardSurface, .elevatedSurface, .selection:
            (.warmWhite, .darkCard)
        case .primaryText:
            (.inkBlack, .warmWhite)
        case .secondaryText, .separator:
            (.warmGray, .warmGray)
        case .accent, .recordFill, .activeTrail:
            (.trailRed, .trailRed)
        case .playbackFill:
            (.inkBlack, .warmWhite)
        }
    }

    private static func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
        switch appearance.name {
        case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua:
            true
        default:
            false
        }
    }

    private struct RGB {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        var nsColor: NSColor {
            NSColor(red: red, green: green, blue: blue, alpha: 1)
        }

        static let warmWhite = RGB(red: 0xF1 / 255, green: 0xEA / 255, blue: 0xDC / 255)
        static let inkBlack = RGB(red: 0x17 / 255, green: 0x16 / 255, blue: 0x19 / 255)
        static let trailRed = RGB(red: 0xE7 / 255, green: 0x38 / 255, blue: 0x36 / 255)
        static let warmGray = RGB(red: 0x8B / 255, green: 0x84 / 255, blue: 0x7A / 255)
        static let darkCanvas = RGB(red: 0x15 / 255, green: 0x14 / 255, blue: 0x18 / 255)
        static let darkCard = RGB(red: 0x23 / 255, green: 0x21 / 255, blue: 0x26 / 255)
    }
}

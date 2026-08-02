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
        case recordFill
        case playbackFill
        case prominentForeground
        case activeTrail
    }

    static let canvas = color(for: .canvas)
    static let cardSurface = color(for: .cardSurface)
    static let elevatedSurface = color(for: .elevatedSurface)
    static let primaryText = color(for: .primaryText)
    static let secondaryText = color(for: .secondaryText)
    static let separator = color(for: .separator)
    static let selection = color(for: .selection)
    static let recordFill = color(for: .recordFill)
    static let playbackFill = color(for: .playbackFill)
    static let prominentForeground = color(for: .prominentForeground)
    static let activeTrail = color(for: .activeTrail)

    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24
    static let cardCornerRadius: CGFloat = 10
    static let panelCornerRadius: CGFloat = 14
    static let cardBorderWidth: CGFloat = 1
    static let primaryControlHeight: CGFloat = 44
    static let compactHeaderHeight: CGFloat = 96

    static func resolvedColor(for role: ColorRole, appearance: NSAppearance) -> NSColor {
        let palette = palette(for: role)
        return (appearanceIsDark(appearance) ? palette.dark : palette.light).nsColor
    }

    static func dynamicNSColor(for role: ColorRole) -> NSColor {
        NSColor(name: NSColor.Name("clicker.\(role.rawValue)")) { appearance in
            resolvedColor(for: role, appearance: appearance)
        }
    }

    static func color(for role: ColorRole) -> Color {
        Color(nsColor: dynamicNSColor(for: role))
    }

    private static func palette(for role: ColorRole) -> (light: RGB, dark: RGB) {
        switch role {
        case .canvas:
            (.warmWhite, .darkCanvas)
        case .cardSurface, .elevatedSurface, .selection:
            (.warmWhite, .darkCard)
        case .primaryText:
            (.inkBlack, .warmWhite)
        case .secondaryText:
            (.inkBlack, .warmWhite)
        case .separator:
            (.warmGray, .warmGray)
        case .recordFill, .activeTrail:
            (.trailRed, .trailRed)
        case .playbackFill:
            (.inkBlack, .warmWhite)
        case .prominentForeground:
            (.warmWhite, .inkBlack)
        }
    }

    static func appearanceIsDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
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

import AppKit
import SwiftUI

enum ClickerVisualTheme {
    enum ColorRole: String, CaseIterable {
        case windowBackground
        case sidebarBackground
        case controlSurface
        case focusRing
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

    static let windowBackground = color(for: .windowBackground)
    static let sidebarBackground = color(for: .sidebarBackground)
    static let controlSurface = color(for: .controlSurface)
    static let focusRing = color(for: .focusRing)
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
    static let sidebarIdealWidth: CGFloat = 230
    static let compactHeaderHeight: CGFloat = 100
    static let primaryControlHeight: CGFloat = 38
    static let controlCornerRadius: CGFloat = 8

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
        case .windowBackground, .canvas:
            (.windowLight, .windowDark)
        case .sidebarBackground:
            (.sidebarLight, .sidebarDark)
        case .selection:
            (.selectionLight, .selectionDark)
        case .controlSurface, .cardSurface, .elevatedSurface:
            (.controlLight, .controlDark)
        case .focusRing:
            (.focusLight, .focusDark)
        case .primaryText:
            (.primaryLight, .primaryDark)
        case .secondaryText:
            (.secondaryLight, .secondaryDark)
        case .separator:
            (.separatorLight, .separatorDark)
        case .recordFill, .activeTrail:
            (.recordRedLight, .recordRedDark)
        case .playbackFill:
            (.playbackLight, .playbackDark)
        case .prominentForeground:
            (.primaryDark, .primaryLight)
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

        static let windowLight = RGB(red: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF8 / 255)
        static let windowDark = RGB(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
        static let sidebarLight = RGB(red: 0xF0 / 255, green: 0xF0 / 255, blue: 0xF2 / 255)
        static let sidebarDark = RGB(red: 0x24 / 255, green: 0x24 / 255, blue: 0x26 / 255)
        static let selectionLight = RGB(red: 0xE1 / 255, green: 0xE1 / 255, blue: 0xE5 / 255)
        static let selectionDark = RGB(red: 0x38 / 255, green: 0x38 / 255, blue: 0x3C / 255)
        static let controlLight = RGB(red: 0xF1 / 255, green: 0xF1 / 255, blue: 0xF3 / 255)
        static let controlDark = RGB(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255)
        static let focusLight = RGB(red: 0x74 / 255, green: 0x74 / 255, blue: 0x7A / 255)
        static let focusDark = RGB(red: 0xA1 / 255, green: 0xA1 / 255, blue: 0xA6 / 255)
        static let recordRedLight = RGB(red: 0xE5 / 255, green: 0x39 / 255, blue: 0x35 / 255)
        static let recordRedDark = RGB(red: 0xF0 / 255, green: 0x4A / 255, blue: 0x45 / 255)
        static let playbackLight = RGB(red: 0x30 / 255, green: 0x30 / 255, blue: 0x33 / 255)
        static let playbackDark = RGB(red: 0xFF / 255, green: 0xFF / 255, blue: 0xFF / 255)
        static let primaryLight = RGB(red: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255)
        static let primaryDark = RGB(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF7 / 255)
        static let secondaryLight = RGB(red: 0x3D / 255, green: 0x3D / 255, blue: 0x43 / 255)
        static let secondaryDark = RGB(red: 0xD3 / 255, green: 0xD3 / 255, blue: 0xD6 / 255)
        static let separatorLight = RGB(red: 0x74 / 255, green: 0x74 / 255, blue: 0x7A / 255)
        static let separatorDark = RGB(red: 0xA1 / 255, green: 0xA1 / 255, blue: 0xA6 / 255)
    }
}

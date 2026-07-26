import Foundation

/// macOS 虚拟键码 → 显示名。键码为 ANSI 标准布局（Carbon kVK_* 常量值）。
public enum KeyCodeMap {
    // CGEventFlags 位（与 CoreGraphics 常量一致，放这里避免 Core 依赖 CG）
    public static let maskShift: UInt64 = 1 << 17
    public static let maskControl: UInt64 = 1 << 18
    public static let maskOption: UInt64 = 1 << 19
    public static let maskCommand: UInt64 = 1 << 20

    static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Delete", 53: "Esc", 55: "⌘", 56: "⇧", 57: "CapsLock",
        58: "⌥", 59: "⌃", 60: "⇧", 61: "⌥", 62: "⌃",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1",
        115: "Home", 116: "PageUp", 117: "FwdDelete", 119: "End", 121: "PageDown",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    public static func name(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key\(keyCode)"
    }

    /// 快捷键显示串，修饰键顺序遵循 macOS 惯例：⌃⌥⇧⌘。
    public static func shortcutDisplay(keyCode: UInt16, flags: UInt64) -> String {
        var s = ""
        if flags & maskControl != 0 { s += "⌃" }
        if flags & maskOption != 0 { s += "⌥" }
        if flags & maskShift != 0 { s += "⇧" }
        if flags & maskCommand != 0 { s += "⌘" }
        return s + name(for: keyCode)
    }
}

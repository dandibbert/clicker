import Foundation
import ClickerCore

struct RecordingStopShortcut: Codable, Equatable, Sendable {
    enum Validation: Equatable {
        case valid
        case riskyTextKey
        case conflict(String)
        case modifierOnly
    }

    static let supportedModifierMask = KeyCodeMap.maskControl
        | KeyCodeMap.maskOption
        | KeyCodeMap.maskShift
        | KeyCodeMap.maskCommand
    static let defaultValue = RecordingStopShortcut(keyCode: 53, modifierFlags: 0)

    let keyCode: UInt16
    let modifierFlags: UInt64

    init(keyCode: UInt16, modifierFlags: UInt64) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags & Self.supportedModifierMask
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            keyCode: try container.decode(UInt16.self, forKey: .keyCode),
            modifierFlags: try container.decode(UInt64.self, forKey: .modifierFlags)
        )
    }

    var displayName: String {
        KeyCodeMap.shortcutDisplay(keyCode: keyCode, flags: modifierFlags)
    }

    func matches(keyCode: UInt16, flags: UInt64) -> Bool {
        self.keyCode == keyCode && modifierFlags == (flags & Self.supportedModifierMask)
    }

    func validation(
        globalRecord: RecordingStopShortcut,
        globalPlay: RecordingStopShortcut
    ) -> Validation {
        if Self.isModifierKey(keyCode) {
            return .modifierOnly
        }
        if isSameShortcut(as: globalRecord) {
            return .conflict("开始/停止录制")
        }
        if isSameShortcut(as: globalPlay) {
            return .conflict("开始/停止播放")
        }
        if modifierFlags == 0 && Self.isTextKey(keyCode) {
            return .riskyTextKey
        }
        return .valid
    }

    fileprivate static func isModifierKey(_ keyCode: UInt16) -> Bool {
        (54...63).contains(keyCode)
    }

    private static func isTextKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 0...9, 11...50:
            return true
        default:
            return false
        }
    }

    private func isSameShortcut(as other: RecordingStopShortcut) -> Bool {
        keyCode == other.keyCode && modifierFlags == other.modifierFlags
    }
}

final class RecordingStopShortcutStore {
    static let storageKey = "Clicker.RecordingStopShortcut"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shortcut: RecordingStopShortcut {
        get {
            guard
                let data = defaults.data(forKey: Self.storageKey),
                let shortcut = try? JSONDecoder().decode(RecordingStopShortcut.self, from: data),
                !RecordingStopShortcut.isModifierKey(shortcut.keyCode)
            else {
                return .defaultValue
            }
            return shortcut
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

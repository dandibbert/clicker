import Carbon.HIToolbox
import AppKit

struct HotKeyRegistrationResult {
    let status: OSStatus
    let reference: EventHotKeyRef?
}

struct HotKeyRegistrationIssue: Identifiable, Equatable {
    enum Shortcut: String, Equatable {
        case recording
        case playback

        var displayName: String {
            switch self {
            case .recording: "⌥⌘R（录制）"
            case .playback: "⌥⌘P（回放）"
            }
        }
    }

    let shortcut: Shortcut
    let status: OSStatus

    var id: Shortcut { shortcut }
}

/// Carbon 全局快捷键。⌥⌘R = 录制开关，⌥⌘P = 回放开关。
final class HotKeyCenter {
    typealias Registration = (
        _ keyCode: UInt32,
        _ modifiers: UInt32,
        _ hotKeyID: EventHotKeyID
    ) -> HotKeyRegistrationResult

    static let recordKeyCode = UInt32(kVK_ANSI_R)   // 15
    static let playKeyCode = UInt32(kVK_ANSI_P)     // 35
    static let modifiers = UInt32(optionKey | cmdKey)
    static let signature = OSType(0x434C4B52) // "CLKR"

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?
    private let registerHotKey: Registration

    init(registerHotKey: @escaping Registration = HotKeyCenter.systemRegister) {
        self.registerHotKey = registerHotKey
    }

    @discardableResult
    func register() -> [HotKeyRegistrationIssue] {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard hotKeyID.signature == HotKeyCenter.signature else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async {
                switch hotKeyID.id {
                case 1: NotificationCenter.default.post(name: .toggleRecord, object: ["source": "hotkey"])
                case 2: NotificationCenter.default.post(name: .togglePlay, object: ["source": "hotkey"])
                default: break
                }
            }
            return noErr
        }, 1, &eventType, nil, &handlerRef)

        return registerHotKeys()
    }

    func registerHotKeys() -> [HotKeyRegistrationIssue] {
        let registrations: [(HotKeyRegistrationIssue.Shortcut, UInt32, UInt32)] = [
            (.recording, Self.recordKeyCode, 1),
            (.playback, Self.playKeyCode, 2),
        ]
        var references: [EventHotKeyRef?] = []
        var issues: [HotKeyRegistrationIssue] = []
        for (shortcut, keyCode, id) in registrations {
            let result = registerHotKey(
                keyCode,
                Self.modifiers,
                EventHotKeyID(signature: Self.signature, id: id)
            )
            if result.status == noErr {
                references.append(result.reference)
            } else {
                issues.append(HotKeyRegistrationIssue(
                    shortcut: shortcut,
                    status: result.status
                ))
            }
        }
        hotKeyRefs = references
        return issues
    }

    private static func systemRegister(
        keyCode: UInt32,
        modifiers: UInt32,
        hotKeyID: EventHotKeyID
    ) -> HotKeyRegistrationResult {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        return HotKeyRegistrationResult(status: status, reference: reference)
    }
}

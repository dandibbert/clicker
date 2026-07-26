import Carbon.HIToolbox
import AppKit

/// Carbon 全局快捷键。⌥⌘R = 录制开关，⌥⌘P = 回放开关。
final class HotKeyCenter {
    static let recordKeyCode = UInt32(kVK_ANSI_R)   // 15
    static let playKeyCode = UInt32(kVK_ANSI_P)     // 35
    static let modifiers = UInt32(optionKey | cmdKey)

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?

    func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            DispatchQueue.main.async {
                switch hotKeyID.id {
                case 1: NotificationCenter.default.post(name: .toggleRecord, object: ["source": "hotkey"])
                case 2: NotificationCenter.default.post(name: .togglePlay, object: ["source": "hotkey"])
                default: break
                }
            }
            return noErr
        }, 1, &eventType, nil, &handlerRef)

        var ref1: EventHotKeyRef?
        RegisterEventHotKey(Self.recordKeyCode, Self.modifiers,
                            EventHotKeyID(signature: OSType(0x434C4B52), id: 1),
                            GetApplicationEventTarget(), 0, &ref1)
        var ref2: EventHotKeyRef?
        RegisterEventHotKey(Self.playKeyCode, Self.modifiers,
                            EventHotKeyID(signature: OSType(0x434C4B52), id: 2),
                            GetApplicationEventTarget(), 0, &ref2)
        hotKeyRefs = [ref1, ref2]
    }
}

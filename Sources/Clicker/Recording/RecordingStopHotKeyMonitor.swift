import Carbon.HIToolbox
import ClickerCore

protocol RecordingStopHotKeyMonitoring: AnyObject {
    @discardableResult
    func start(shortcut: RecordingStopShortcut, onStop: @escaping () -> Void) -> Bool
    func stop()
}

/// 独立于 CGEventTap 的停止通道。输入监控授权变化时，录制也不会失去退出手段。
final class CarbonRecordingStopHotKeyMonitor: RecordingStopHotKeyMonitoring {
    private static let signature = OSType(0x43535450) // "CSTP"
    private static let hotKeyID = UInt32(1)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onStop: (() -> Void)?

    deinit {
        stop()
    }

    @discardableResult
    func start(shortcut: RecordingStopShortcut, onStop: @escaping () -> Void) -> Bool {
        stop()
        self.onStop = onStop

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      hotKeyID.signature == CarbonRecordingStopHotKeyMonitor.signature,
                      hotKeyID.id == CarbonRecordingStopHotKeyMonitor.hotKeyID else {
                    return OSStatus(eventNotHandledErr)
                }
                let monitor = Unmanaged<CarbonRecordingStopHotKeyMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                DispatchQueue.main.async { [weak monitor] in monitor?.onStop?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installStatus == noErr else {
            stop()
            return false
        }

        let registrationStatus = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(for: shortcut.modifierFlags),
            EventHotKeyID(signature: Self.signature, id: Self.hotKeyID),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registrationStatus == noErr else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        onStop = nil
    }

    static func carbonModifiers(for flags: UInt64) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags & KeyCodeMap.maskControl != 0 { modifiers |= UInt32(controlKey) }
        if flags & KeyCodeMap.maskOption != 0 { modifiers |= UInt32(optionKey) }
        if flags & KeyCodeMap.maskShift != 0 { modifiers |= UInt32(shiftKey) }
        if flags & KeyCodeMap.maskCommand != 0 { modifiers |= UInt32(cmdKey) }
        return modifiers
    }
}

import Carbon.HIToolbox
import ClickerCore

struct ScriptHotKeyRegistrationIssue: Equatable, Identifiable {
    let scriptID: UUID
    let scriptName: String
    let shortcut: ScriptShortcut
    let status: OSStatus

    var id: UUID { scriptID }
}

/// 根据脚本库动态维护全局回放快捷键。
final class ScriptHotKeyCenter {
    typealias Registration = HotKeyCenter.Registration
    typealias Unregistration = (EventHotKeyRef) -> Void

    private static let signature = OSType(0x43535042) // "CSPB"

    private let registerHotKey: Registration
    private let unregisterHotKey: Unregistration
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var scriptIDsByHotKeyID: [UInt32: UUID] = [:]
    private var handlerRef: EventHandlerRef?
    var onTrigger: ((UUID) -> Void)?

    init(
        registerHotKey: @escaping Registration = ScriptHotKeyCenter.systemRegister,
        unregisterHotKey: @escaping Unregistration = { UnregisterEventHotKey($0) }
    ) {
        self.registerHotKey = registerHotKey
        self.unregisterHotKey = unregisterHotKey
    }

    deinit {
        removeRegistrations()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    func start() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
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
                      hotKeyID.signature == ScriptHotKeyCenter.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let center = Unmanaged<ScriptHotKeyCenter>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                guard let scriptID = center.scriptIDsByHotKeyID[hotKeyID.id] else {
                    return OSStatus(eventNotHandledErr)
                }
                DispatchQueue.main.async { [weak center] in center?.onTrigger?(scriptID) }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    @discardableResult
    func refresh(scripts: [Script]) -> [ScriptHotKeyRegistrationIssue] {
        removeRegistrations()
        var issues: [ScriptHotKeyRegistrationIssue] = []
        var claimedShortcuts: Set<ScriptShortcut> = []
        var nextHotKeyID: UInt32 = 1

        for script in scripts {
            guard let shortcut = script.playbackShortcut else { continue }
            guard shortcut.modifierFlags != 0,
                  !(54...63).contains(shortcut.keyCode) else {
                issues.append(issue(
                    for: script,
                    shortcut: shortcut,
                    status: OSStatus(paramErr)
                ))
                continue
            }
            guard claimedShortcuts.insert(shortcut).inserted else {
                issues.append(issue(
                    for: script,
                    shortcut: shortcut,
                    status: OSStatus(eventHotKeyExistsErr)
                ))
                continue
            }
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: nextHotKeyID)
            let result = registerHotKey(
                UInt32(shortcut.keyCode),
                Self.carbonModifiers(for: shortcut.modifierFlags),
                hotKeyID
            )
            if result.status == noErr {
                if let reference = result.reference { hotKeyRefs.append(reference) }
                scriptIDsByHotKeyID[nextHotKeyID] = script.id
                nextHotKeyID += 1
            } else {
                issues.append(issue(for: script, shortcut: shortcut, status: result.status))
            }
        }
        return issues
    }

    private func removeRegistrations() {
        hotKeyRefs.forEach(unregisterHotKey)
        hotKeyRefs = []
        scriptIDsByHotKeyID = [:]
    }

    private func issue(
        for script: Script,
        shortcut: ScriptShortcut,
        status: OSStatus
    ) -> ScriptHotKeyRegistrationIssue {
        ScriptHotKeyRegistrationIssue(
            scriptID: script.id,
            scriptName: script.name,
            shortcut: shortcut,
            status: status
        )
    }

    static func carbonModifiers(for flags: UInt64) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags & KeyCodeMap.maskControl != 0 { modifiers |= UInt32(controlKey) }
        if flags & KeyCodeMap.maskOption != 0 { modifiers |= UInt32(optionKey) }
        if flags & KeyCodeMap.maskShift != 0 { modifiers |= UInt32(shiftKey) }
        if flags & KeyCodeMap.maskCommand != 0 { modifiers |= UInt32(cmdKey) }
        return modifiers
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

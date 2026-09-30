import CoreGraphics

protocol EventTapSession: AnyObject {
    var isRunning: Bool { get }
    var requiresListenAccess: Bool { get }

    func start(handler: @escaping (CGEventType, CGEvent) -> Void) -> Bool
    func reenable() -> Bool
    func stop()
}

extension EventTapSession {
    var requiresListenAccess: Bool { false }
    func reenable() -> Bool { true }
}

final class CoreGraphicsEventTapSession: EventTapSession {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: ((CGEventType, CGEvent) -> Void)?

    var isRunning: Bool { tap != nil }
    var requiresListenAccess: Bool { true }

    func start(handler: @escaping (CGEventType, CGEvent) -> Void) -> Bool {
        stop()
        self.handler = handler

        let maskTypes: [CGEventType] = [
            .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .scrollWheel,
            .keyDown, .keyUp, .flagsChanged,
        ]
        let mask = maskTypes.reduce(CGEventMask(0)) { result, type in
            result | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
        let callback: CGEventTapCallBack = { _, type, event, context in
            let session = Unmanaged<CoreGraphicsEventTapSession>
                .fromOpaque(context!)
                .takeUnretainedValue()
            session.handler?(type, event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            self.handler = nil
            return false
        }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func reenable() -> Bool {
        guard let tap else { return false }
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tap = nil
        runLoopSource = nil
        handler = nil
    }
}

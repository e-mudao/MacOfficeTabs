import Carbon

enum ShortcutDisplayState: Equatable {
    case off, inactive, handlerUnavailable, registrationFailed(OSStatus), registered
}

/// Registers only the two declared combinations. No keyboard monitoring or
/// synthetic events. A failed pair registration rolls back the whole pair.
final class ShortcutController {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var attempted = false
    private var failure: OSStatus?
    private var handlerFailed = false
    private(set) var state: ShortcutDisplayState = .off
    var invoke: ((Bool) -> Void)?
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr,id.signature == 0x4D4F5442 else { return OSStatus(eventNotHandledErr) }
            Unmanaged<ShortcutController>.fromOpaque(context).takeUnretainedValue().invoke?(id.id == 2)
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func update(eligible:Bool) {
        if let failure { unregister(); state = .registrationFailed(failure); return }
        if handlerFailed { unregister(); state = .handlerUnavailable; return }
        guard eligible else { unregister(); state = .inactive; return }
        guard !attempted else { return }
        attempted = true
        guard handler != nil else { handlerFailed = true; state = .handlerUnavailable; return }
        for (id,key) in [(UInt32(1),UInt32(kVK_LeftArrow)),(UInt32(2),UInt32(kVK_RightArrow))] {
            var ref:EventHotKeyRef?
            let result = RegisterEventHotKey(key,UInt32(controlKey | optionKey | cmdKey),EventHotKeyID(signature:0x4D4F5442,id:id),
                                            GetApplicationEventTarget(),UInt32(kEventHotKeyExclusive),&ref)
            guard result == noErr,let ref else {
                if let ref { UnregisterEventHotKey(ref) }
                for ref in refs { UnregisterEventHotKey(ref) }; refs = []
                failure = result
                state = .registrationFailed(result)
                return
            }
            refs.append(ref)
        }
        state = .registered
    }
    func unregister() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs = []; attempted = false
    }
    func resetFailure() { failure = nil; handlerFailed = false; unregister(); state = .off }
    deinit { unregister(); if let handler { RemoveEventHandler(handler) } }
}

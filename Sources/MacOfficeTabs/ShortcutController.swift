import Carbon

/// Registers only the two declared combinations. No keyboard monitoring or
/// synthetic events. A failed pair registration rolls back the whole pair.
final class ShortcutController {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var attempted = false
    private var failure: String?
    var invoke: ((Bool) -> Void)?
    private(set) var status = "快捷键关闭"
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
        if let failure { unregister(); status = failure; return }
        guard eligible else { unregister(); status = "快捷键未注册（关闭或当前状态不安全）"; return }
        guard !attempted else { return }
        attempted = true
        guard handler != nil else { failure = "快捷键事件处理器不可用"; status = failure!; return }
        for (id,key) in [(UInt32(1),UInt32(kVK_LeftArrow)),(UInt32(2),UInt32(kVK_RightArrow))] {
            var ref:EventHotKeyRef?
            let result = RegisterEventHotKey(key,UInt32(controlKey | optionKey | cmdKey),EventHotKeyID(signature:0x4D4F5442,id:id),
                                            GetApplicationEventTarget(),UInt32(kEventHotKeyExclusive),&ref)
            guard result == noErr,let ref else {
                if let ref { UnregisterEventHotKey(ref) }
                for ref in refs { UnregisterEventHotKey(ref) }; refs = []
                failure = "快捷键注册失败或冲突（\(result)）；两项均未占用。关闭后重新开启可重试。"
                status = failure!
                return
            }
            refs.append(ref)
        }
        status = "⌃⌥⌘←/→ 已注册（当前 Office 安全状态）"
    }
    func unregister() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs = []; attempted = false
    }
    func resetFailure() { failure = nil; unregister() }
    deinit { unregister(); if let handler { RemoveEventHandler(handler) } }
}

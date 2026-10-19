import AppKit
import Carbon

// Separate-process test fixture. Occupies only the declared right combination;
// no input synthesis, document access, preference writes, or event handler.
_ = NSApplication.shared
var ref: EventHotKeyRef?
let status = RegisterEventHotKey(UInt32(kVK_RightArrow), UInt32(controlKey | optionKey | cmdKey),
    EventHotKeyID(signature: 0x4F434350, id: 1), GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &ref)
guard status == noErr, let registered = ref else {
    print("INCONCLUSIVE: RegisterEventHotKey returned \(status)")
    exit(2)
}
print("READY: right combination occupied; press Return to release and exit")
fflush(stdout)
_ = readLine()
let released = UnregisterEventHotKey(registered)
print("RELEASE: \(released)")
exit(released == noErr ? 0 : 1)

import AppKit
import Carbon

// Integration probe for the production ShortcutController. No input injection,
// document access, or preferences. All temporary registrations are released.
_ = NSApplication.shared
let modifiers = UInt32(controlKey | optionKey | cmdKey)
func register(_ key: UInt32, _ id: UInt32) -> (OSStatus, EventHotKeyRef?) {
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(key, modifiers,
        EventHotKeyID(signature: 0x50524F42, id: id), GetApplicationEventTarget(), 0, &ref)
    return (status, ref)
}
func runProbe() -> Int32 {
    let (occupiedStatus, occupied) = register(UInt32(kVK_RightArrow), 100)
    guard occupiedStatus == noErr, let occupied else {
        print("INCONCLUSIVE: could not occupy right combination: \(occupiedStatus)")
        return 2
    }
    var right: EventHotKeyRef? = occupied
    defer { if let right { UnregisterEventHotKey(right) } }
    let controller = ShortcutController()
    defer { controller.unregister() }
    controller.update(eligible: true)
    print("collision status: \(controller.status)")
    guard controller.status.contains("注册失败或冲突") else {
        print("FAIL: collision was not reported")
        return 1
    }
    let (leftStatus, left) = register(UInt32(kVK_LeftArrow), 101)
    guard leftStatus == noErr, let left else {
        print("FAIL: left combination was not rolled back: \(leftStatus)")
        return 1
    }
    UnregisterEventHotKey(left)
    UnregisterEventHotKey(occupied); right = nil
    controller.update(eligible: true)
    guard controller.status.contains("注册失败或冲突") else {
        print("FAIL: failure was retried without explicit reset")
        return 1
    }
    // Both combinations must remain free after conflict, even when eligibility
    // changes again. This checks actual OS resources rather than private state.
    for (key,id) in [(UInt32(kVK_LeftArrow),UInt32(102)), (UInt32(kVK_RightArrow),UInt32(103))] {
        let (status,ref) = register(key,id)
        guard status == noErr,let ref else { print("FAIL: combination retained: \(status)"); return 1 }
        UnregisterEventHotKey(ref)
    }
    controller.resetFailure(); controller.update(eligible: true)
    guard controller.status.contains("已注册") else { print("FAIL: explicit reset did not recover"); return 1 }
    controller.update(eligible: false)
    for (key,id) in [(UInt32(kVK_LeftArrow),UInt32(104)), (UInt32(kVK_RightArrow),UInt32(105))] {
        let (status,ref) = register(key,id)
        guard status == noErr,let ref else { print("FAIL: disable retained combination: \(status)"); return 1 }
        UnregisterEventHotKey(ref)
    }
    print("PASS: actual Carbon collision, pair rollback, no retry, reset recovery, disable cleanup")
    return 0
}
func runCrossProcessProbe() -> Int32 {
    guard CommandLine.arguments.count == 2 else { return 0 }
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let input = Pipe(), output = Pipe()
    child.standardInput = input; child.standardOutput = output
    do { try child.run() } catch { print("INCONCLUSIVE: occupier launch failed: \(error)"); return 2 }
    var released = false
    func release() {
        guard !released else { return }
        released = true
        input.fileHandleForWriting.write(Data("\n".utf8))
        child.waitUntilExit()
    }
    defer { release() }
    let ready = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self)
    print(ready.trimmingCharacters(in: .whitespacesAndNewlines))
    guard ready.contains("READY:") else {
        released = true
        child.waitUntilExit()
        return 2
    }
    let controller = ShortcutController()
    defer { controller.unregister() }
    controller.update(eligible: true)
    print("cross-process status: \(controller.status)")
    guard controller.status.contains("注册失败或冲突") else {
        print("FAIL: external occupation was silently shared")
        return 1
    }
    var left: EventHotKeyRef?
    let leftStatus = RegisterEventHotKey(UInt32(kVK_LeftArrow), modifiers,
        EventHotKeyID(signature: 0x50524F42, id: 201), GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &left)
    guard leftStatus == noErr, let left else { print("FAIL: external conflict retained left: \(leftStatus)"); return 1 }
    UnregisterEventHotKey(left)
    release()
    guard child.terminationStatus == 0 else { print("FAIL: occupier release failed"); return 1 }
    controller.update(eligible: true)
    guard controller.status.contains("注册失败或冲突") else { print("FAIL: external failure automatically retried"); return 1 }
    controller.resetFailure(); controller.update(eligible: true)
    guard controller.status.contains("已注册") else { print("FAIL: recovery after external release failed"); return 1 }
    controller.update(eligible: false)
    print("PASS: cross-process conflict, rollback, no retry, explicit recovery and cleanup")
    return 0
}
let localResult = runProbe()
exit(localResult == 0 ? runCrossProcessProbe() : localResult)

import AppKit
import CoreServices

/// Explicit research entry point, separate from the product's AX scan/control path.
/// This static script only reads window metadata; it never activates, edits, closes or saves.
private let wordWindowProbeSource = """
with timeout of 3 seconds
    tell application id "com.microsoft.Word"
        set probeRows to {}
        set probeWindows to get every window
        repeat with probeWindow in probeWindows
            try
                set probeID to (id of probeWindow) as text
                set probeName to name of probeWindow
                set probeActive to active of probeWindow
                set end of probeRows to {probeID, probeName, probeActive, 0, contents of probeWindow}
            on error probeMessage number probeError
                set end of probeRows to {"", "", false, probeError, missing value}
            end try
        end repeat
        return probeRows
    end tell
end timeout
"""

func wordAutomationProbe(mode: String) -> Int32 {
    var report: [String:Any] = ["mode":mode,"readOnly":true,"bodyRead":false,"windowControl":false]
    var code: Int32 = 0
    if mode == "compile" {
        var error: NSDictionary?
        let script = NSAppleScript(source:wordWindowProbeSource)
        let compiled = script?.compileAndReturnError(&error) == true
        report["compiled"] = compiled
        if !compiled { code = 3 }
        if let error { report["error"] = error.description }
    } else if !NSRunningApplication.runningApplications(withBundleIdentifier:AXClient.wordBundleID).isEmpty {
        let target = NSAppleEventDescriptor(bundleIdentifier:AXClient.wordBundleID)
        let permission = AEDeterminePermissionToAutomateTarget(target.aeDesc,typeWildCard,typeWildCard,mode == "request-and-read")
        report["permissionStatus"] = permission
        if mode == "permission" { report["requestSent"] = false }
        else if permission != noErr { report["status"] = "permissionRequired"; code = 2 }
        else {
            var error: NSDictionary?
            let result = NSAppleScript(source:wordWindowProbeSource)?.executeAndReturnError(&error)
            if let error { report["status"] = "scriptFailed"; report["error"] = error.description; code = 3 }
            else if let result {
                var rows: [[String:Any]] = []
                if result.numberOfItems > 0 {
                    for index in 1...result.numberOfItems {
                        guard let row = result.atIndex(index), row.numberOfItems == 5 else { code = 3; break }
                        rows.append(["windowID":row.atIndex(1)?.stringValue ?? "",
                                     "title":row.atIndex(2)?.stringValue ?? "",
                                     "active":row.atIndex(3)?.booleanValue ?? false,
                                     "propertyError":row.atIndex(4)?.int32Value ?? -1,
                                     "objectSpecifier":row.atIndex(5)?.description ?? "missing"])
                    }
                }
                report["windows"] = rows; report["windowCount"] = rows.count
                if rows.contains(where: {
                    ($0["propertyError"] as? Int32) != 0 ||
                    ($0["windowID"] as? String)?.isEmpty != false ||
                    ($0["windowID"] as? String) == "missing value"
                }) || Set(rows.compactMap { $0["windowID"] as? String }).count != rows.count {
                    code = 5
                }
                report["status"] = code == 0 ? "ok" : "metadataUnavailable"
            } else { report["status"] = "missingReply"; code = 3 }
        }
    } else { report["status"] = "wordNotRunning"; code = 4 }
    if let data = try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {
        print(String(decoding:data,as:UTF8.self))
    }
    return code
}

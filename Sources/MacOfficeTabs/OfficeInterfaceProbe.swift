import AppKit
import ApplicationServices
import OfficeTabsCore

/// Explicit research entry: read window roles and native menu identifiers only.
/// Does not activate apps, request permissions, open files or read document bodies.
func officeInterfaceProbe(_ profile:OfficeApp) -> Int32 {
    guard AXIsProcessTrusted() else { print("{\"status\":\"permissionRequired\"}"); return 2 }
    guard let running = NSRunningApplication.runningApplications(withBundleIdentifier:profile.rawValue).first else {
        print("{\"status\":\"notRunning\"}"); return 0
    }
    func raw(_ item:AXUIElement,_ key:String) -> CFTypeRef? {
        var result:CFTypeRef?
        return AXUIElementCopyAttributeValue(item,key as CFString,&result) == .success ? result : nil
    }
    func str(_ item:AXUIElement,_ key:String) -> String? { raw(item,key) as? String }
    let app = AXUIElementCreateApplication(running.processIdentifier)
    AXUIElementSetMessagingTimeout(app,0.25)
    var output:[String:Any] = ["status":"ok","bundleID":profile.rawValue,"pid":running.processIdentifier]
    var menus:[[String:Any]] = []
    if let bar = raw(app,"AXMenuBar"),CFGetTypeID(bar) == AXUIElementGetTypeID(),
       let roots = raw(bar as! AXUIElement,kAXChildrenAttribute) as? [AXUIElement] {
        for root in roots {
            var nodes:[[String:Any]] = []
            var count = 0
            func visit(_ item:AXUIElement,depth:Int) {
                guard depth <= 3,count < 250 else { return }
                count += 1; AXUIElementSetMessagingTimeout(item,0.25)
                var row:[String:Any] = ["depth":depth,"role":str(item,kAXRoleAttribute) ?? "unknown"]
                if let id = str(item,"AXIdentifier") { row["identifier"] = id }
                if let mark = str(item,"AXMenuItemMarkChar") { row["mark"] = mark }
                if let enabled = raw(item,kAXEnabledAttribute) as? Bool { row["enabled"] = enabled }
                if let command = str(item,"AXMenuItemCmdChar"),!command.isEmpty { row["commandChar"] = command }
                var actions:CFArray?
                if AXUIElementCopyActionNames(item,&actions) == .success { row["actions"] = actions as? [String] ?? [] }
                nodes.append(row)
                let role = str(item,kAXRoleAttribute)
                if role == kAXMenuBarItemRole || role == kAXMenuRole,
                   let children = raw(item,kAXChildrenAttribute) as? [AXUIElement] {
                    for child in children { visit(child,depth:depth+1) }
                }
            }
            visit(root,depth:0); menus.append(["rootIdentifier":str(root,"AXIdentifier") ?? "unknown","nodes":nodes])
        }
    }
    output["menus"] = menus
    if let windows = raw(app,kAXWindowsAttribute) as? [AXUIElement] {
        output["windows"] = windows.map { item in
            ["role":str(item,kAXRoleAttribute) ?? "unknown","subrole":str(item,kAXSubroleAttribute) ?? "unknown",
             "fullScreen":String(describing:raw(item,"AXFullScreen") as? Bool)]
        }
    }
    let data = try! JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys])
    print(String(decoding:data,as:UTF8.self)); return 0
}

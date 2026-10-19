import AppKit
import ApplicationServices
import OfficeTabsCore

if let index = CommandLine.arguments.firstIndex(of:"--probe-office-interface") {
    guard CommandLine.arguments.count == index+2,let profile = OfficeApp(bundleID:CommandLine.arguments[index+1]) else { exit(64) }
    _ = NSApplication.shared
    exit(officeInterfaceProbe(profile))
}

if let index = CommandLine.arguments.firstIndex(of:"--probe-word-automation") {
    guard CommandLine.arguments.count == index + 2,
          ["compile","permission","read","request-and-read"].contains(CommandLine.arguments[index+1]) else {
        fputs("Usage: MacOfficeTabs --probe-word-automation compile|permission|read|request-and-read\n",stderr); exit(64)
    }
    _ = NSApplication.shared
    exit(wordAutomationProbe(mode:CommandLine.arguments[index+1]))
}

if let index = CommandLine.arguments.firstIndex(of: "--exercise-fixtures") {
    guard CommandLine.arguments.count == index + 2 else {
        fputs("Usage: MacOfficeTabs --exercise-fixtures ABSOLUTE_TEST_DIRECTORY\n", stderr); exit(64)
    }
    _ = NSApplication.shared
    exit(exerciseFixtures(root: CommandLine.arguments[index + 1]))
}
if let index = CommandLine.arguments.firstIndex(of:"--diagnose") {
    let profile: OfficeApp
    if CommandLine.arguments.count == index + 1 { profile = .word }
    else if CommandLine.arguments.count == index + 2,let selected = OfficeApp(bundleID:CommandLine.arguments[index+1]) { profile = selected }
    else { exit(64) }
    let client = AXClient(profile:profile)
    _ = NSApplication.shared
    let result = client.scan()
    var status = "ok"
    var exitCode: Int32 = 0
    switch result.outcome {
    case .denied: status = "permissionRequired"; exitCode = 2
    case .failure: status = "scanFailed"; exitCode = 3
    case .success: break
    }
    let object: [String: Any] = ["stage": "P2", "status": status,"bundleID":profile.rawValue,
                               "version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development",
                               "build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown",
                               "accessibilityTrusted": AXIsProcessTrusted(), "windowCount": result.details.count,
                               "officeRunning": !NSRunningApplication.runningApplications(withBundleIdentifier: profile.rawValue).isEmpty,
                               "message": result.message,
                               "frontmostBundleID":NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown",
                               "screens":NSScreen.screens.map { ["frame":NSStringFromRect($0.frame),"visibleFrame":NSStringFromRect($0.visibleFrame),"safeTop":$0.safeAreaInsets.top] as [String:Any] },
                               "windowGeometry":result.details.map { ["id":$0.record.id.uuidString,"frame":$0.frame.map { NSStringFromRect($0) } ?? "unknown","focused":$0.focused,"safeForPanel":$0.safeForPanel,"minimized":$0.minimized.map(String.init) ?? "unknown","fullScreen":$0.fullScreen.map(String.init) ?? "unknown"] as [String:Any] },
                               "tabs":result.tabs.map { ["id":$0.id.uuidString,"title":$0.title,"windowID":$0.windowID?.uuidString ?? "unassociated","canClose":$0.canClose,"focused":$0.focused] as [String:Any] },
                               "nativeCloseCommandProbe":client.nativeCloseCommandDiagnostics(),
                               "windowMenuProbe":client.windowMenuDiagnostics()]
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    client.stopObserving()
    exit(exitCode)
}
let app = NSApplication.shared
let coordinator = Coordinator()
app.setActivationPolicy(.regular)
app.delegate = coordinator
app.run()

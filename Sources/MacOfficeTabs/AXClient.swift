import AppKit
import ApplicationServices
import OfficeTabsCore

struct AXToken: Equatable {
    let element: AXUIElement
    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
}
struct WindowDetails {
    let record: WindowRecord
    let frame: CGRect?
    let minimized: Bool?
    let focused: Bool
    let fullScreen: Bool?
    let safeForPanel: Bool
}
struct TabTarget {
    let id: UUID
    let title: String
    let windowID: UUID?
    let menuCandidate: Bool
    let focused: Bool
    var canClose: Bool { windowID != nil }
}
enum ActivationResult {
    case confirmed(UUID, UUID, pid_t)
    case failed(String)
    var message: String {
        switch self {
        case .confirmed(let target, _, _): return T("activation.confirmed", String(target.uuidString.prefix(8)))
        case .failed(let message): return message
        }
    }
}
struct ScanResult {
    let outcome: ScanOutcome
    let details: [WindowDetails]
    let message: String
    let processID: pid_t?
    var tabs: [TabTarget] = []
}

/// Access exclusively from Coordinator's serial AX queue.
final class AXClient {
    static let wordBundleID = OfficeApp.word.rawValue
    let profile: OfficeApp
    init(profile: OfficeApp = .word) { self.profile = profile }
    private let identities = IdentityStore<AXToken>()
    private var elements: [UUID: AXUIElement] = [:]
    private let inventory = WindowInventory<AXToken>()
    private let menuCandidates = MenuCandidates<AXToken>()
    private var activePID: pid_t?
    private var observer: AXObserver?
    private var watched: [AXUIElement] = []
    private var observedApp: AXUIElement?
    var onEvent: ((String) -> Void)?
    var onDiscoveredWindow: ((AXUIElement) -> Void)?
    var onDestroyedWindow: ((AXUIElement) -> Void)?

    /// Read-only feasibility probe: can Word's complete Window menu link to AX windows?
    /// No menu actions, document content, titles, or file paths are read here.
    func windowMenuDiagnostics() -> [String: Any] {
        guard AXIsProcessTrusted(), let pid = activePID else { return ["available":false] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app,0.25)
        guard let bar = elementValue(app,"AXMenuBar"),
              let top = try? value(bar,kAXChildrenAttribute) as? [AXUIElement],
              let windowMenu = top.first(where: { string($0,"AXIdentifier") == "WindowMenu_MenuItem" }) else {
            return ["available":false,"reason":"windowMenuNotExposed"]
        }
        var entries: [[String:Any]] = []
        func inspect(_ element: AXUIElement, depth: Int) {
            guard depth <= 3 else { return }
            AXUIElementSetMessagingTimeout(element,0.25)
            if string(element,"AXIdentifier") == "makeKeyAndOrderFront:" {
                var actionNames: CFArray?
                let actionStatus = AXUIElementCopyActionNames(element,&actionNames)
                var names: CFArray?
                let result = AXUIElementCopyAttributeNames(element,&names)
                var entry: [String:Any] = ["actions":actionNames as? [String] ?? [],"actionStatus":actionStatus.rawValue,"mark":string(element,"AXMenuItemMarkChar") ?? "unsupported","selected":String(describing:bool(element,"AXSelected")),"attributes":names as? [String] ?? [],"attributeNamesStatus":result.rawValue]
                for key in ["AXMenuItemPrimaryUIElement","AXServesAsTitleForUIElements","AXLinkedUIElements","AXWindow"] {
                    do {
                        let raw = try value(element,key)
                        let links: [AXUIElement]
                        if let array = raw as? [AXUIElement] { links = array }
                        else if CFGetTypeID(raw) == AXUIElementGetTypeID() { links = [raw as! AXUIElement] }
                        else { links = [] }
                        entry[key] = links.map { ["role":string($0,kAXRoleAttribute) ?? "unknown",
                                                 "subrole":string($0,kAXSubroleAttribute) ?? "unknown"] }
                    } catch { entry[key] = String(describing:error) }
                }
                entries.append(entry)
            }
            if let children = try? value(element,kAXChildrenAttribute) as? [AXUIElement] {
                for child in children { inspect(child,depth:depth+1) }
            }
        }
        inspect(windowMenu,depth:0)
        return ["available":true,"entryCount":entries.count,"entries":entries]
    }

    private func value(_ element: AXUIElement, _ key: String) throws -> CFTypeRef {
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, key as CFString, &result)
        guard error == .success, let result else { throw AXFailure(error: error, attribute: key) }
        return result
    }
    private func windowList(_ app: AXUIElement) throws -> [AXUIElement] {
        guard let result = try value(app, kAXWindowsAttribute) as? [AXUIElement] else {
            throw AXFailure(error: .failure, attribute: kAXWindowsAttribute)
        }
        return result
    }
    func rememberDiscoveredWindow(_ window: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(window,&pid) == .success, pid == activePID,
              string(window,kAXRoleAttribute) == kAXWindowRole else { return }
        inventory.remember(processID:pid,token:AXToken(element:window))
    }
    func forgetDestroyedWindow(_ window:AXUIElement) {
        guard let pid = activePID else { return }
        let token = AXToken(element:window)
        inventory.invalidate(processID:pid,token:token)
        identities.invalidate(processID:pid,tokens:[token])
        elements = elements.filter { !CFEqual($0.value,window) }
    }
    private func liveWindowList(_ app: AXUIElement, pid: pid_t) throws -> [AXUIElement] {
        var discovered = try windowList(app)
        guard let children = try value(app,kAXChildrenAttribute) as? [AXUIElement] else {
            throw AXFailure(error:.failure,attribute:kAXChildrenAttribute)
        }
        for child in children {
            guard let role = try value(child,kAXRoleAttribute) as? String else {
                throw AXFailure(error:.failure,attribute:kAXRoleAttribute)
            }
            if role == kAXWindowRole || role == kAXSheetRole { discovered.append(child) }
        }
        if let focus = elementValue(app,kAXFocusedWindowAttribute) { discovered.append(focus) }
        return try inventory.resolve(processID:pid,discovered:discovered.map(AXToken.init),
            retainAcrossAbsence: { token in try self.requiredStandardWindow(token.element) }) { token in
            AXUIElementSetMessagingTimeout(token.element,0.25)
            do {
                let role = try value(token.element,kAXRoleAttribute) as? String
                guard let role else { throw AXFailure(error:.failure,attribute:kAXRoleAttribute) }
                // Preserve freshly readable nonstandard/modal entries from AXWindows;
                // downstream safety checks must see them rather than filter them away.
                return !role.isEmpty
            } catch let failure as AXFailure where failure.error == .invalidUIElement {
                identities.invalidate(processID:pid,tokens:[token])
                return false
            }
        }.map(\.element)
    }
    private func elementValue(_ element: AXUIElement, _ key: String) -> AXUIElement? {
        guard let result = try? value(element, key), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }
    private func string(_ element: AXUIElement, _ key: String) -> String? { (try? value(element, key)) as? String }
    private func bool(_ element: AXUIElement, _ key: String) -> Bool? { (try? value(element, key)) as? Bool }
    private func geometry(_ element: AXUIElement) -> CGRect? {
        guard let position = try? value(element, kAXPositionAttribute),
              let size = try? value(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        let frame = CGRect(origin: point, size: dimensions)
        return ControlSafety.validFrame(frame) ? frame : nil
    }
    private func isStandardWindow(_ element: AXUIElement) -> Bool {
        string(element, kAXRoleAttribute) == kAXWindowRole && string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole
    }
    private func requiredStandardWindow(_ element: AXUIElement) throws -> Bool {
        guard let role = try value(element, kAXRoleAttribute) as? String else {
            throw AXFailure(error: .failure, attribute: kAXRoleAttribute)
        }
        guard role == kAXWindowRole else { return false }
        guard let subrole = try value(element, kAXSubroleAttribute) as? String else {
            throw AXFailure(error: .failure, attribute: kAXSubroleAttribute)
        }
        return subrole == kAXStandardWindowSubrole
    }
    func processTerminated(_ pid: pid_t) { if activePID == pid { clear() } }
    private func clear() {
        stopObserving()
        if let pid = activePID { identities.remove(processID: pid) }
        activePID = nil; elements = [:]; inventory.clear(); menuCandidates.clear()
    }
    func scan() -> ScanResult {
        guard AXIsProcessTrusted() else {
            clear()
            return ScanResult(outcome: .denied, details: [], message: T("scan.permissionDenied"), processID: nil)
        }
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: profile.rawValue).first else {
            clear()
            return ScanResult(outcome: .success([]), details: [], message: T("scan.officeNotRunning", profile.name), processID: nil)
        }
        let pid = running.processIdentifier
        if activePID != pid { clear(); activePID = pid }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        do {
            let all = try liveWindowList(app,pid:pid)
            let windows = try all.filter { try requiredStandardWindow($0) }
            let focus = elementValue(app, kAXFocusedWindowAttribute)
            var safeForPanel = focus.map(isStandardWindow) ?? false
            var safetyReasons: [String] = safeForPanel ? [] : ["focusNotStandard"]
            for (index,candidate) in all.enumerated() {
                if ControlSafety.blocksWindow(isStandard:windows.contains(where: { CFEqual($0,candidate) }),
                                              isModal:bool(candidate,kAXModalAttribute),isSheet:string(candidate,kAXRoleAttribute) == kAXSheetRole) {
                    safeForPanel = false
                    safetyReasons.append("window\(index):role=\(string(candidate,kAXRoleAttribute) ?? "unknown"),subrole=\(string(candidate,kAXSubroleAttribute) ?? "unknown"),modal=\(String(describing:bool(candidate,kAXModalAttribute)))")
                }
                guard let children = try? value(candidate,kAXChildrenAttribute) as? [AXUIElement] else {
                    safeForPanel = false; safetyReasons.append("window\(index):childrenUnknown"); continue
                }
                for child in children {
                    guard let role = string(child,kAXRoleAttribute) else {
                        safeForPanel = false; safetyReasons.append("window\(index):childRoleUnknown"); continue
                    }
                    if role == kAXSheetRole { safeForPanel = false; safetyReasons.append("window\(index):childSheet") }
                }
            }
            var newElements: [UUID: AXUIElement] = [:]
            let details = windows.map { window -> WindowDetails in
                AXUIElementSetMessagingTimeout(window, 0.25)
                let id = identities.identity(processID: pid, token: AXToken(element: window))
                newElements[id] = window
                let document = string(window, kAXDocumentAttribute).flatMap(URL.init(string:))
                let record = WindowRecord(id: id, processID: pid,
                                          title: string(window, kAXTitleAttribute) ?? T("scan.unknownWindow"),
                                          fileURL: document)
                return WindowDetails(record: record, frame: geometry(window), minimized: bool(window, kAXMinimizedAttribute),
                                     focused: focus.map { CFEqual($0, window) } ?? false,
                                     fullScreen:bool(window,"AXFullScreen"),safeForPanel:safeForPanel)
            }
            elements = newElements
            let sources = try documentMenuItems(app)
            guard !sources.isEmpty || windows.isEmpty else {
                throw AXFailure(error:.failure,attribute:"documentMenuEmptyWithWindows")
            }
            menuCandidates.reconcile(processID:pid,sources:sources.map { (AXToken(element:$0),string($0,kAXTitleAttribute) ?? T("scan.unknownDocument")) })
            let targets = menuCandidates.entries.map { entry in
                TabTarget(id:entry.id,title:entry.title,windowID:entry.windowID,menuCandidate:true,
                          focused:menuCandidates.isFocused(entry.id,focusedWindowID:details.first(where:{ $0.focused })?.record.id))
            }
            observe(pid: pid, app: app, windows: all)
            return ScanResult(outcome: .success(details.map(\.record)), details: details,
                              message: T("scan.summary", profile.name, targets.count, sources.count, details.count, all.count, details.filter { $0.fullScreen == true }.count, String(safeForPanel), safetyReasons.isEmpty ? T("scan.noBlocker") : safetyReasons.joined(separator:";")), processID: pid,tabs:targets)
        } catch {
            return ScanResult(outcome: .failure(String(describing: error)), details: [],
                              message: T("scan.failed", String(describing:error)), processID: pid)
        }
    }


    /// Enumerate native menu objects without opening the menu or switching Spaces.
    private func documentMenuItems(_ app: AXUIElement) throws -> [AXUIElement] {
        guard let bar = elementValue(app,"AXMenuBar"),
              let top = try value(bar,kAXChildrenAttribute) as? [AXUIElement],
              let menu = top.first(where:{ string($0,"AXIdentifier") == "WindowMenu_MenuItem" }) else {
            throw AXFailure(error:.failure,attribute:"WindowMenu_MenuItem")
        }
        var result: [AXUIElement] = []
        func visit(_ item: AXUIElement, depth: Int) throws {
            guard depth <= 3 else { return }
            AXUIElementSetMessagingTimeout(item,0.25)
            if string(item,"AXIdentifier") == "makeKeyAndOrderFront:" {
                guard string(item,kAXRoleAttribute) == kAXMenuItemRole,
                      bool(item,kAXEnabledAttribute) != nil,
                      string(item,kAXTitleAttribute) != nil else {
                    throw AXFailure(error:.failure,attribute:"documentMenuItem")
                }
                if !result.contains(where:{ CFEqual($0,item) }) { result.append(item) }
                return
            }
            guard let children = try value(item,kAXChildrenAttribute) as? [AXUIElement] else {
                throw AXFailure(error:.failure,attribute:kAXChildrenAttribute)
            }
            for child in children {
                guard let role = try value(child,kAXRoleAttribute) as? String else {
                    throw AXFailure(error:.failure,attribute:kAXRoleAttribute)
                }
                if role == kAXMenuRole { try visit(child,depth:depth+1) }
                else if role == kAXMenuItemRole && string(child,"AXIdentifier") == "makeKeyAndOrderFront:" {
                    try visit(child,depth:depth+1)
                }
            }
        }
        try visit(menu,depth:0)
        return result
    }
    private func selectedMenuIDs() -> [UUID] {
        // AXSelected is menu highlighting, not document selection. Only a native
        // checkmark is accepted; unexpected mark values never prove an association.
        menuCandidates.entries.filter { string($0.token.element,"AXMenuItemMarkChar") == "✓" }.map(\.id)
    }
    func activateTab(_ id: UUID) -> ActivationResult {
        guard menuCandidates.entries.contains(where:{ $0.id == id }) else { return activate(id) }
        return activateMenuCandidate(id)
    }
    func closeTab(_ id: UUID) -> String {
        guard let entry = menuCandidates.entries.first(where:{ $0.id == id }) else { return close(id) }
        guard let expected = entry.windowID else { return T("close.verifyFirst") }
        switch activateMenuCandidate(id) {
        case .confirmed(_,let actual,_):
            guard actual == expected else { return T("close.targetChanged") }
            // The native candidate action already established this exact focus.
            // Do not mutate AXFocusedWindow/AXMain a second time before closing.
            return closeFocusedWindow(actual)
        case .failed(let message): return T("close.activationFailed", message)
        }
    }
    private func activateMenuCandidate(_ id: UUID) -> ActivationResult {
        guard AXIsProcessTrusted(),let pid = activePID,
              let running = NSRunningApplication(processIdentifier:pid),!running.isTerminated else {
            return .failed(T("activate.stalePermission"))
        }
        let before = scan()
        guard case .success = before.outcome,
              before.details.first(where:{ $0.focused })?.safeForPanel == true,
              let entry = menuCandidates.entries.first(where:{ $0.id == id }),
              bool(entry.token.element,kAXEnabledAttribute) == true else {
            return .failed(T("activate.menuUnavailable"))
        }
        let previousFocus = before.details.first(where:{ $0.focused })?.record.id
        let previouslyAssociated = entry.windowID
        var actions: CFArray?
        let actionRead = AXUIElementCopyActionNames(entry.token.element,&actions)
        guard actionRead == .success, (actions as? [String])?.contains(kAXPressAction) == true else {
            return .failed(T("activate.menuNoPress", actionRead.rawValue, String(describing: actions as? [String] ?? [])))
        }
        guard requestApplicationActivation(running) else { return .failed(T("activate.appRejected", profile.name)) }
        let press = AXUIElementPerformAction(entry.token.element,kAXPressAction as CFString)
        guard press == .success else { return .failed(T("activate.pressRejected", press.rawValue)) }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app,0.25)
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard AXIsProcessTrusted(),!running.isTerminated else { return .failed(T("activate.stalePermission")) }
            do {
                let sources = try documentMenuItems(app)
                menuCandidates.reconcile(processID:pid,sources:sources.map { (AXToken(element:$0),string($0,kAXTitleAttribute) ?? T("scan.unknownDocument")) })
                guard menuCandidates.entries.contains(where:{ $0.id == id }) else { return .failed(T("activate.menuChanged")) }
                if selectedMenuIDs() == [id],NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                   let focus = elementValue(app,kAXFocusedWindowAttribute),try requiredStandardWindow(focus) {
                    let actual = identities.identity(processID:pid,token:AXToken(element:focus))
                    let after = scan()
                    // A stable singleton in the complete native menu and the
                    // fresh AX window list is the only first-association exception
                    // without a focus transition. Never infer it from titles.
                    guard CandidateAssociationPolicy.permits(previousFocus:previousFocus,actualFocus:actual,associated:previouslyAssociated,
                        soleCandidateBefore:before.tabs.map(\.id) == [id],soleCandidateAfter:after.tabs.map(\.id) == [id],
                        windowsBefore:before.details.map { $0.record.id },windowsAfter:after.details.map { $0.record.id }) else {
                        return .failed(T("activate.unconfirmedAssociation"))
                    }
                    guard case .success = after.outcome,
                          after.details.contains(where:{ $0.record.id == actual && $0.focused && $0.safeForPanel }),
                          selectedMenuIDs() == [id],
                          menuCandidates.associate(id,windowID:actual,selectedIDs:[id],frontmost:true,standardFocus:true) else {
                        return .failed(T("activate.finalFocusFailed"))
                    }
                    return .confirmed(id,actual,pid)
                }
            } catch { return .failed(T("activate.menuCheckFailed", String(describing:error))) }
            usleep(50_000)
        }
        return .failed(T("activate.menuTimeout", profile.name))
    }

    func close(_ id: UUID) -> String {
        switch activate(id) {
        case .failed(let message): return T("close.activationFailed", message)
        case .confirmed: break
        }
        return closeFocusedWindow(id)
    }
    private func closeFocusedWindow(_ id:UUID) -> String {
        guard AXIsProcessTrusted(), let target = elements[id], let pid = activePID else { return T("close.staleTarget") }
        let app = AXUIElementCreateApplication(pid)
        guard let focus = elementValue(app,kAXFocusedWindowAttribute), CFEqual(focus,target),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            return T("close.focusUnknown")
        }
        guard bool(target,kAXModalAttribute) != true,
              let children = try? value(target,kAXChildrenAttribute) as? [AXUIElement],
              children.allSatisfy({ child in
                  guard let role = string(child,kAXRoleAttribute) else { return false }
                  return role != kAXSheetRole
              }) else { return T("close.modalChildren") }
        do {
            // A modal window can appear elsewhere while activation was being verified.
            for candidate in try liveWindowList(app,pid:pid) {
                if ControlSafety.blocksWindow(isStandard:try requiredStandardWindow(candidate),
                                              isModal:bool(candidate,kAXModalAttribute),
                                              isSheet:string(candidate,kAXRoleAttribute) == kAXSheetRole) {
                    return T("close.unknownAuxiliary")
                }
                guard let children = try value(candidate,kAXChildrenAttribute) as? [AXUIElement] else {
                    return T("close.childrenUnknown")
                }
                for child in children {
                    guard let role = try value(child,kAXRoleAttribute) as? String, role != kAXSheetRole else {
                        return T("close.savePrompt")
                    }
                }
            }
        } catch { return T("close.windowCheckFailed", String(describing:error)) }
        do {
            let command = try nativeCloseCommand(app)
            let finalScan = scan()
            guard case .success = finalScan.outcome,
                  finalScan.details.contains(where:{ $0.record.id == id && $0.focused && $0.safeForPanel }) else {
                return T("close.commandStateUnknown")
            }
            // Native application commands act on current focus. Verify it again
            // after menu reads, immediately before the only destructive request.
            guard AXIsProcessTrusted(),let actual = elementValue(app,kAXFocusedWindowAttribute),
                  CFEqual(actual,target),NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  bool(target,kAXModalAttribute) != true else { return T("close.finalStateChanged") }
            AXUIElementSetMessagingTimeout(command,0.25)
            let status = AXUIElementPerformAction(command,kAXPressAction as CFString)
            guard status == .success else { return T("close.pressRejected", status.rawValue) }
            return verifyCloseEffect(app:app,target:target,pid:pid)
        } catch { return T("close.commandCheckFailed", String(describing:error)) }
    }
    /// Word's public performClose: menu command works independently of hidden
    /// full-screen titlebar controls. Never resolve the command by its label.
    func nativeCloseCommandDiagnostics() -> [String:Any] {
        guard AXIsProcessTrusted(),let pid = activePID else { return ["available":false] }
        do {
            let command = try nativeCloseCommand(AXUIElementCreateApplication(pid))
            return ["available":true,"identifier":string(command,"AXIdentifier") ?? "unknown",
                    "role":string(command,kAXRoleAttribute) ?? "unknown","enabled":bool(command,kAXEnabledAttribute) ?? false]
        } catch { return ["available":false,"reason":String(describing:error)] }
    }
    private func nativeCloseCommand(_ app: AXUIElement) throws -> AXUIElement {
        guard let bar = elementValue(app,"AXMenuBar"),
              let roots = try value(bar,kAXChildrenAttribute) as? [AXUIElement] else {
            throw AXFailure(error:.failure,attribute:"AXMenuBar")
        }
        var matches: [AXUIElement] = []
        func visit(_ item:AXUIElement,depth:Int) throws {
            guard depth <= 2 else { return }
            AXUIElementSetMessagingTimeout(item,0.25)
            if string(item,"AXIdentifier") == "performClose:" {
                guard string(item,kAXRoleAttribute) == kAXMenuItemRole,
                      bool(item,kAXEnabledAttribute) == true else {
                    throw AXFailure(error:.failure,attribute:"performClose:enabled")
                }
                var actions:CFArray?
                guard AXUIElementCopyActionNames(item,&actions) == .success,
                      (actions as? [String])?.contains(kAXPressAction) == true else {
                    throw AXFailure(error:.failure,attribute:"performClose:AXPress")
                }
                if !matches.contains(where:{ CFEqual($0,item) }) { matches.append(item) }
                return
            }
            guard let role = try value(item,kAXRoleAttribute) as? String else {
                throw AXFailure(error:.failure,attribute:kAXRoleAttribute)
            }
            if role == kAXMenuBarItemRole || role == kAXMenuRole {
                guard let children = try value(item,kAXChildrenAttribute) as? [AXUIElement] else {
                    throw AXFailure(error:.failure,attribute:kAXChildrenAttribute)
                }
                for child in children { try visit(child,depth:depth+1) }
            }
        }
        for root in roots { try visit(root,depth:0) }
        guard matches.count == 1 else { throw AXFailure(error:.failure,attribute:"performClose:unique") }
        return matches[0]
    }
    private func verifyCloseEffect(app:AXUIElement,target:AXUIElement,pid:pid_t) -> String {
        let verifier = CloseVerifier(deadline:ProcessInfo.processInfo.systemUptime+2)
        while true {
            guard AXIsProcessTrusted(),let running = NSRunningApplication(processIdentifier:pid),!running.isTerminated else {
                return T("close.outcomeUnknown")
            }
            var invalid = false
            do { _ = try value(target,kAXRoleAttribute) }
            catch let failure as AXFailure where failure.error == .invalidUIElement { invalid = true }
            catch { /* A modal sheet can temporarily make AX reads fail. */ }
            var prompt = false
            var candidates = [target]
            if let focus = elementValue(app,kAXFocusedWindowAttribute) { candidates.append(focus) }
            if let focus = elementValue(app,kAXFocusedUIElementAttribute) {
                var current:AXUIElement? = focus
                for _ in 0..<4 {
                    guard let item = current else { break }
                    candidates.append(item); current = elementValue(item,kAXParentAttribute)
                }
            }
            if let children = try? value(app,kAXChildrenAttribute) as? [AXUIElement] { candidates += children }
            if let children = try? value(target,kAXChildrenAttribute) as? [AXUIElement] { candidates += children }
            for item in candidates {
                if string(item,kAXRoleAttribute) == kAXSheetRole || bool(item,kAXModalAttribute) == true { prompt = true; break }
            }
            switch verifier.evaluate(targetInvalid:invalid,nativePrompt:prompt,now:ProcessInfo.processInfo.systemUptime) {
            case .nativePrompt: return T("close.nativePrompt")
            case .closed: return T("close.confirmed")
            case .unconfirmed: return T("close.unconfirmed")
            case .waiting: usleep(50_000)
            }
        }
    }

    func activate(_ id: UUID) -> ActivationResult {
        guard AXIsProcessTrusted() else { clear(); return .failed(T("activate.permissionRevoked")) }
        guard let pid = activePID, let target = elements[id],
              let running = NSRunningApplication(processIdentifier: pid), !running.isTerminated,
              running.bundleIdentifier == profile.rawValue else { return .failed(T("activate.processGone")) }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        do {
            let windows = try liveWindowList(app,pid:pid)
            let targetStandard = try requiredStandardWindow(target)
            let hasTarget = windows.contains(where: { CFEqual($0, target) }) && targetStandard
            let focused = elementValue(app, kAXFocusedWindowAttribute)
            let focusedStandard = focused.map(isStandardWindow) ?? false
            var blockingWindow = focused.map { bool($0, kAXModalAttribute) == true } ?? false
            var blockers: [String] = blockingWindow ? ["focusedModal"] : []
            var childrenInspected = true
            for window in windows {
                let standard = try requiredStandardWindow(window)
                let modal = bool(window, kAXModalAttribute)
                let role = string(window, kAXRoleAttribute)
                if ControlSafety.blocksWindow(isStandard: standard, isModal: modal, isSheet: role == kAXSheetRole) {
                    blockingWindow = true
                    blockers.append("role=\(role ?? "unknown");subrole=\(string(window, kAXSubroleAttribute) ?? "unknown");modal=\(String(describing: modal))")
                }
                guard let children = try value(window, kAXChildrenAttribute) as? [AXUIElement] else {
                    childrenInspected = false; continue
                }
                for child in children {
                    guard let role = try value(child, kAXRoleAttribute) as? String else {
                        childrenInspected = false; continue
                    }
                    if role == kAXSheetRole { blockingWindow = true; blockers.append("AXSheet") }
                }
            }
            guard ControlSafety.permits(hasTarget: hasTarget, focusedStandard: focusedStandard,
                                        childrenInspected: childrenInspected, blockingWindow: blockingWindow) else {
                let reason = ControlSafety.rejection(hasTarget: hasTarget, focusedStandard: focusedStandard,
                                                     childrenInspected: childrenInspected, blockingWindow: blockingWindow) ?? "unknown"
                return .failed(T("activate.precheck", reason, blockers.joined(separator: ",")))
            }
            guard let minimized = bool(target, kAXMinimizedAttribute) else { return .failed(T("activate.minimizedUnknown")) }
            if minimized && AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse) != .success {
                return .failed(T("activate.restoreFailed"))
            }
            guard requestApplicationActivation(running) else { return .failed(T("activate.systemRejected")) }
            guard AXUIElementPerformAction(target, kAXRaiseAction as CFString) == .success else { return .failed(T("activate.raiseRejected")) }
            // Some apps reject setting these attributes; observation, never return codes, decides success.
            _ = AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, target)
            _ = AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
            let deadline = ProcessInfo.processInfo.systemUptime + 1.5
            let verifier = ActivationVerifier(target: id, processID: pid, deadline: deadline)
            var lastObservation = "notObserved"
            while ProcessInfo.processInfo.systemUptime < deadline {
                guard AXIsProcessTrusted(), !running.isTerminated else { return .failed(T("activate.stalePermission")) }
                let actual = elementValue(app, kAXFocusedWindowAttribute)
                let actualID = actual.flatMap { current in elements.first(where: { CFEqual($0.value, current) })?.key }
                let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
                lastObservation = "focusedMatch=\(actualID == id);frontmost=\(String(describing: frontmost));targetPID=\(pid)"
                let result = verifier.evaluate(focused: actualID, frontmostPID: frontmost, now: ProcessInfo.processInfo.systemUptime)
                if result == .confirmed { return .confirmed(id, actualID!, frontmost!) }
                if Thread.isMainThread {
                    // AppKit time-varying process state updates only on a new main run-loop turn.
                    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                } else {
                    usleep(50_000)
                }
            }
            return .failed(T("activate.focusTimeout", lastObservation))
        } catch { return .failed(T("activate.error", String(describing:error))) }
    }

    /// AppKit activation must be coordinated on the main thread; AX I/O remains on its worker queue.
    private func requestApplicationActivation(_ running: NSRunningApplication) -> Bool {
        let request = {
            // A queued request must not take over a different foreground app.
            // The diagnostic tool itself may hand off to its selected Office.
            let front = NSWorkspace.shared.frontmostApplication
            guard front?.processIdentifier == running.processIdentifier || front?.processIdentifier == NSRunningApplication.current.processIdentifier else { return false }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == running.processIdentifier { return true }
            if #available(macOS 14.0, *) {
                NSApplication.shared.yieldActivation(to: running)
                return running.activate(from: NSRunningApplication.current, options: [])
            }
            return running.activate(options: [.activateIgnoringOtherApps])
        }
        return Thread.isMainThread ? request() : DispatchQueue.main.sync(execute: request)
    }

    private let appNotifications = [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXApplicationActivatedNotification]
    private let windowNotifications = [kAXMovedNotification, kAXResizedNotification, kAXTitleChangedNotification,
                                       kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification]
    private func observe(pid: pid_t, app: AXUIElement, windows: [AXUIElement]) {
        if observer == nil {
            var created: AXObserver?
            let status = AXObserverCreate(pid, { _, element, notification, context in
                guard let context else { return }
                let client = Unmanaged<AXClient>.fromOpaque(context).takeUnretainedValue()
                if notification as String == kAXWindowCreatedNotification { client.onDiscoveredWindow?(element) }
                if notification as String == kAXUIElementDestroyedNotification { client.onDestroyedWindow?(element) }
                client.onEvent?(notification as String)
            }, &created)
            guard status == .success, let created else { onEvent?(T("observer.unavailable")); return }
            observer = created; observedApp = app
            let context = Unmanaged.passUnretained(self).toOpaque()
            for notification in appNotifications {
                _ = AXObserverAddNotification(created, app, notification as CFString, context)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        }
        guard let observer else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        for previous in watched where !windows.contains(where: { CFEqual($0, previous) }) {
            for notification in windowNotifications { AXObserverRemoveNotification(observer, previous, notification as CFString) }
        }
        for window in windows where !watched.contains(where: { CFEqual($0, window) }) {
            for notification in windowNotifications {
                _ = AXObserverAddNotification(observer, window, notification as CFString, context)
            }
        }
        watched = windows
    }
    func stopObserving() {
        guard let observer else { return }
        if let app = observedApp {
            for notification in appNotifications { AXObserverRemoveNotification(observer, app, notification as CFString) }
        }
        for window in watched {
            for notification in windowNotifications { AXObserverRemoveNotification(observer, window, notification as CFString) }
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        self.observer = nil; observedApp = nil; watched = []
    }
}
private struct AXFailure: Error, CustomStringConvertible {
    let error: AXError
    let attribute: String
    var description: String { "\(attribute) AXError=\(error.rawValue)" }
}

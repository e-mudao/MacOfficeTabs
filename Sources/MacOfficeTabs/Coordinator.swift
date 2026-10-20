import AppKit
import ApplicationServices
import OfficeTabsCore
import OSLog

final class Coordinator: NSObject, NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let clients = Dictionary(uniqueKeysWithValues: OfficeApp.allCases.map { ($0, AXClient(profile:$0)) })
    private var route = OfficeRoute()
    private var client: AXClient { clients[route.app]! }
    private let tabs = TabPanelController()
    private let preferences = OfficePreferences()
    private let shortcuts = ShortcutController()
    private lazy var settings = SettingsController(preferences:preferences)
    private let queue = DispatchQueue(label: "MacOfficeTabs.ax", qos: .userInitiated)
    private let logger = Logger(subsystem: "local.MacOfficeTabs", category: "Lifecycle")
    private var state = WindowState()
    private var registry = DocumentRegistry()
    private var details: [WindowDetails] = []
    private var targets: [TabTarget] = []
    private var tableKey = ""
    private var languageRevision = 0
    private var scanning = false
    private var controlling = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var events: [String] = []
    private var window: NSWindow!
    private let table = NSTableView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let actionStatus = NSTextField(wrappingLabelWithString: "")
    private let eventStatus = NSTextField(wrappingLabelWithString: "")
    private let activateButton = NSButton(title: "", target: nil, action: nil)
    private let refreshButton = NSButton(title: "", target: nil, action: nil)
    private let heading = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(wrappingLabelWithString: "")
    private let permissionButton = NSButton(title: "", target: nil, action: nil)
    private let copyButton = NSButton(title: "", target: nil, action: nil)
    private let privacy = NSTextField(wrappingLabelWithString: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu(); buildWindow()
        settings.changed = { [weak self] in
            guard let self else { return }
            self.tabs.enabled = self.preferences.tabsEnabled(for:self.route.app)
            self.shortcuts.resetFailure(); self.tabs.hide(); self.refresh()
        }
        settings.languageChanged = { [weak self] in
            guard let self else { return }
            self.languageRevision += 1
            self.events.removeAll(); self.tableKey = ""
            self.buildMenu(); self.localizeWindow(); self.settings.setShortcutStatus(self.shortcuts.status)
            self.table.reloadData(); self.refresh()
        }
        shortcuts.invoke = { [weak self] forward in self?.cycleTab(forward:forward) }

        tabs.activate = { [weak self] id in self?.control(id,closing:false) }
        tabs.close = { [weak self] id in self?.control(id,closing:true) }
        for (profile, client) in clients {
            client.onDiscoveredWindow = { [weak self, weak client] element in
                self?.queue.async { client?.rememberDiscoveredWindow(element) }
            }
            client.onDestroyedWindow = { [weak self, weak client] element in
                self?.queue.async { client?.forgetDestroyedWindow(element) }
            }
            client.onEvent = { [weak self] event in
                DispatchQueue.main.async {
                    guard let self, self.route.app == profile else { return }
                    self.recordEvent(event); self.refresh()
                }
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                if notification.name == NSWorkspace.didTerminateApplicationNotification,
                   let terminated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   let profile = OfficeApp(bundleID:terminated.bundleIdentifier) {
                    if profile == self?.route.app {
                        // Invalidate any scan already queued for the old process,
                        // even when the next process has the same bundle ID.
                        _ = self?.route.select(profile)
                        self?.state = WindowState(); self?.details = []; self?.targets = []
                        self?.table.reloadData(); self?.updateControls(); self?.tabs.reset()
                    }
                    if let client = self?.clients[profile] { self?.queue.async { client.processTerminated(terminated.processIdentifier) } }
                }
                self?.shortcuts.update(eligible:false)
                self?.selectFrontmostApp()
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != self?.route.app.rawValue { self?.tabs.hide() }
                self?.recordEvent(notification.name.rawValue); self?.refresh()
            })
        }
        selectFrontmostApp()
        refresh()
        scheduleNextPoll()
        NSApp.activate(ignoringOtherApps: true)
        logger.info("P0 diagnostic application started")
    }
    private func buildMenu() {
        let main = NSMenu(); let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: T("menu.about"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: T("menu.diagnostics"), action:#selector(showDiagnostics),keyEquivalent:"")
        appMenu.addItem(withTitle:T("menu.settings"),action:#selector(showSettings),keyEquivalent:",")
        appMenu.addItem(withTitle: T("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: T("menu.edit"))
        edit.addItem(withTitle: T("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: T("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; NSApp.mainMenu = main
    }
    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 580),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 720, height: 460)
        window.isReleasedWhenClosed = false
        heading.font = .systemFont(ofSize: 24, weight: .semibold)
        subtitle.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 14, weight: .medium)
        status.setAccessibilityIdentifier("permissionStatus")
        actionStatus.setAccessibilityIdentifier("activationStatus")
        eventStatus.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        eventStatus.textColor = .secondaryLabelColor
        for (identifier, title, width) in [("title", "diagnostics.columnTitle", 260.0), ("id", "diagnostics.columnID", 100.0),
                                           ("focus", "diagnostics.columnFocus", 75.0), ("min", "diagnostics.columnMinimized", 75.0), ("geometry", "diagnostics.columnAssociation", 260.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = T(title); column.width = width; table.addTableColumn(column)
        }
        table.dataSource = self; table.delegate = self; table.rowHeight = 34
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        refreshButton.target = self; refreshButton.action = #selector(refreshClicked)
        activateButton.target = self; activateButton.action = #selector(activateClicked); activateButton.isEnabled = false
        permissionButton.target = self; permissionButton.action = #selector(openPermissions)
        copyButton.target = self; copyButton.action = #selector(copyDiagnostics)
        let buttons = NSStackView(views: [refreshButton, activateButton, permissionButton, copyButton]); buttons.spacing = 10
        privacy.textColor = .secondaryLabelColor; privacy.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [heading, subtitle, status, scroll, buttons, actionStatus, eventStatus, privacy])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -24),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actionStatus.widthAnchor.constraint(equalTo: stack.widthAnchor),
            eventStatus.widthAnchor.constraint(equalTo: stack.widthAnchor),
            privacy.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        localizeWindow(); window.center(); window.makeKeyAndOrderFront(nil)
    }
    private func localizeWindow() {
        let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown"
        window.title = T("diagnostics.windowTitle", route.app.name)
        heading.stringValue = T("diagnostics.heading", version, build)
        subtitle.stringValue = T("diagnostics.subtitle")
        status.stringValue = T("diagnostics.checking")
        actionStatus.stringValue = T("diagnostics.initialAction")
        eventStatus.stringValue = T("diagnostics.noEvents")
        activateButton.title = T("diagnostics.activate")
        refreshButton.title = T("diagnostics.refresh")
        permissionButton.title = T("diagnostics.permissions")
        copyButton.title = T("diagnostics.copy")
        privacy.stringValue = T("diagnostics.privacy")
        table.setAccessibilityLabel(T("diagnostics.tableLabel"))
        let keys = ["title":"diagnostics.columnTitle", "id":"diagnostics.columnID", "focus":"diagnostics.columnFocus", "min":"diagnostics.columnMinimized", "geometry":"diagnostics.columnAssociation"]
        for column in table.tableColumns { if let key = keys[column.identifier.rawValue] { column.title = T(key) } }
    }
    private func selectFrontmostApp() {
        guard let profile = OfficeApp(bundleID:NSWorkspace.shared.frontmostApplication?.bundleIdentifier), profile != route.app else { return }
        _ = route.select(profile)
        tabs.enabled = preferences.tabsEnabled(for:profile)
        state = WindowState(); details = []; targets = []; tableKey = ""
        table.reloadData(); tabs.hide(); updateControls()
        window.title = T("diagnostics.windowTitle", profile.name)
    }
    @objc private func refreshClicked() { refresh() }
    private func refresh() {
        guard !scanning, !controlling else { return }
        selectFrontmostApp()
        let ticket = route.ticket
        let languageRevision = self.languageRevision
        let client = self.client
        shortcuts.update(eligible:false)
        scanning = true; refreshButton.isEnabled = false; activateButton.isEnabled = false
        let selected = table.selectedRow >= 0 && table.selectedRow < targets.count ? targets[table.selectedRow].id : nil
        queue.async { [weak self] in
            guard let self else { return }
            let result = client.scan()
            DispatchQueue.main.async {
                self.scanning = false; self.refreshButton.isEnabled = true
                guard self.route.accepts(ticket), self.languageRevision == languageRevision else { self.refresh(); return }
                self.state.apply(result.outcome)
                switch result.outcome {
                case .success: self.details = result.details; self.targets = result.tabs
                case .denied: self.details = []; self.targets = []
                case .failure: break
                }
                self.registry.reconcile(self.state.windows)
                self.status.stringValue = result.message
                self.status.textColor = self.state.canControl ? .labelColor : .systemOrange
                let key = self.targets.map { "\($0.id):\($0.title):\($0.windowID?.uuidString ?? "unknown"):\($0.focused)" }.joined(separator:"|")
                if key != self.tableKey { self.tableKey = key; self.table.reloadData() }
                if let selected, let row = self.targets.firstIndex(where: { $0.id == selected }) {
                    self.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
                self.updateControls()
                self.tabs.enabled = self.preferences.tabsEnabled(for:ticket.app)
                self.updateShortcuts()
                self.tabs.update(self.details,canControl:self.state.canControl && !self.controlling,targets:self.targets,profile:ticket.app)
                self.eventStatus.stringValue = T("diagnostics.recent", self.events.last ?? T("diagnostics.none"), self.tabs.diagnostic)
            }
        }
    }
    private func scheduleNextPoll() {
        let active = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == route.app.rawValue
        timer = Timer.scheduledTimer(withTimeInterval: active ? 0.5 : 2.0, repeats: false) { [weak self] _ in
            self?.refresh(); self?.scheduleNextPoll()
        }
    }
    private func updateControls() {
        activateButton.isEnabled = state.canControl && !scanning && !controlling && table.selectedRow >= 0 && table.selectedRow < targets.count
    }
    @objc private func activateClicked() {
        guard activateButton.isEnabled else { return }
        let id = targets[table.selectedRow].id
        control(id,closing:false)
    }
    private func control(_ id: UUID, closing:Bool) {
        guard state.canControl, !controlling, (details.contains(where: { $0.record.id == id }) || targets.contains(where: { $0.id == id })) else { return }
        let ticket = route.ticket
        let languageRevision = self.languageRevision
        let client = self.client
        shortcuts.update(eligible:false)
        controlling = true; updateControls(); refreshButton.isEnabled = false
        tabs.hide()
        actionStatus.stringValue = T("diagnostics.verifying")
        queue.async { [weak self] in
            guard let self else { return }
            let message = closing ? client.closeTab(id) : client.activateTab(id).message
            DispatchQueue.main.async {
                self.controlling = false
                guard self.route.accepts(ticket), self.languageRevision == languageRevision else { self.refresh(); return }
                self.actionStatus.stringValue = message
                self.recordEvent(T(closing ? "diagnostics.closeResult" : "diagnostics.activateResult", message)); self.refresh()
            }
        }
    }
    @objc private func showDiagnostics() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    @objc private func showSettings() { settings.show() }
    private func shortcutEligible() -> Bool {
        ShortcutPolicy.eligible(enabled:preferences.shortcutsEnabled,
            frontmost:OfficeApp(bundleID:NSWorkspace.shared.frontmostApplication?.bundleIdentifier),
            selected:route.app,safe:state.canControl && details.first(where:{ $0.focused })?.safeForPanel == true,
            busy:scanning || controlling,tabsEnabled:preferences.tabsEnabled(for:route.app))
    }
    private func updateShortcuts() {
        shortcuts.update(eligible:shortcutEligible())
        settings.setShortcutStatus(shortcuts.status)
    }
    private func cycleTab(forward:Bool) {
        guard shortcutEligible(),let next = ShortcutPolicy.next(in:tabs.orderedIDs(targets.map(\.id)),
            focused:targets.first(where:{ $0.focused })?.id,forward:forward) else { return }
        control(next,closing:false)
    }
    @objc private func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func copyDiagnostics() {
        let text = (["MacOfficeTabs", status.stringValue, actionStatus.stringValue, tabs.diagnostic] + details.map {
            "\($0.record.id) pid=\($0.record.processID) title=\($0.record.title) focused=\($0.focused) fullscreen=\(String(describing:$0.fullScreen)) safePanel=\($0.safeForPanel)"
        } + events).joined(separator: "\n")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        actionStatus.stringValue = T("diagnostics.copied")
    }
    private func recordEvent(_ event: String) {
        events.append("\(Date().formatted(date: .omitted, time: .standard)) \(event)")
        if events.count > 30 { events.removeFirst(events.count - 30) }
        eventStatus.stringValue = T("diagnostics.recent", events.last ?? T("diagnostics.none"), T("diagnostics.associations", registry.documents.count))
    }
    func numberOfRows(in tableView: NSTableView) -> Int { targets.count }
    func tableViewSelectionDidChange(_ notification: Notification) { updateControls() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < targets.count else { return nil }
        let target = targets[row]
        let detail = details.first(where:{ $0.record.id == target.windowID })
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "title": text = target.title
        case "id": text = String(target.id.uuidString.prefix(8))
        case "focus": text = T(target.focused ? "diagnostics.yes" : "diagnostics.no")
        case "min": text = detail?.minimized.map { T($0 ? "diagnostics.yes" : "diagnostics.no") } ?? T("diagnostics.unknown")
        default:
            text = target.menuCandidate ? T(target.canClose ? "diagnostics.menuVerified" : "diagnostics.menuUnverified") : T("diagnostics.axWindow")
        }
        let cell = NSTextField(labelWithString: text); cell.lineBreakMode = .byTruncatingTail; cell.toolTip = text
        return cell
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        tabs.hide(); shortcuts.unregister()
        timer?.invalidate()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        // A worker can be awaiting a main-thread activation handoff. Never wait on
        // that worker from application termination; the process also releases AX sources.
        let clients = Array(self.clients.values)
        queue.async { for client in clients { client.stopObserving() } }
        logger.info("P0 tool exited; no Office termination requested")
    }
}

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
    private var scanning = false
    private var controlling = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var events: [String] = []
    private var window: NSWindow!
    private let table = NSTableView()
    private let status = NSTextField(wrappingLabelWithString: "正在检查权限…")
    private let actionStatus = NSTextField(wrappingLabelWithString: "请选择测试窗口，再执行激活；工具不会关闭或保存文档。")
    private let eventStatus = NSTextField(wrappingLabelWithString: "尚无事件")
    private let activateButton = NSButton(title: "激活并核验选中窗口", target: nil, action: nil)
    private let refreshButton = NSButton(title: "刷新", target: nil, action: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu(); buildWindow()
        settings.changed = { [weak self] in
            guard let self else { return }
            self.tabs.enabled = self.preferences.tabsEnabled(for:self.route.app)
            self.shortcuts.resetFailure(); self.tabs.hide(); self.refresh()
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
        appMenu.addItem(withTitle: "关于 MacOfficeTabs", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "显示窗口诊断", action:#selector(showDiagnostics),keyEquivalent:"")
        appMenu.addItem(withTitle:"设置…",action:#selector(showSettings),keyEquivalent:",")
        appMenu.addItem(withTitle: "退出 MacOfficeTabs", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; NSApp.mainMenu = main
    }
    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 580),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "MacOfficeTabs · Office 窗口诊断"
        window.minSize = NSSize(width: 720, height: 460)
        window.isReleasedWhenClosed = false
        let version = Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown"
        let title = NSTextField(labelWithString: "Office 窗口与标签管理 · \(version) (\(build))")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: "Office 前台时显示辅助标签栏 · 窗口保持原有布局 · 关闭交给 Office 原生确认")
        subtitle.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 14, weight: .medium)
        status.setAccessibilityIdentifier("permissionStatus")
        actionStatus.setAccessibilityIdentifier("activationStatus")
        eventStatus.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        eventStatus.textColor = .secondaryLabelColor
        for (identifier, title, width) in [("title", "窗口标题", 260.0), ("id", "运行时 ID", 100.0),
                                           ("focus", "AX 焦点", 75.0), ("min", "最小化", 75.0), ("geometry", "几何 / 文档关联", 260.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title; column.width = width; table.addTableColumn(column)
        }
        table.dataSource = self; table.delegate = self; table.rowHeight = 34
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false; table.setAccessibilityLabel("Office 标准窗口候选列表")
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        refreshButton.target = self; refreshButton.action = #selector(refreshClicked)
        activateButton.target = self; activateButton.action = #selector(activateClicked); activateButton.isEnabled = false
        let permission = NSButton(title: "打开辅助功能设置", target: self, action: #selector(openPermissions))
        let copy = NSButton(title: "复制诊断（含标题）", target: self, action: #selector(copyDiagnostics))
        let buttons = NSStackView(views: [refreshButton, activateButton, permission, copy]); buttons.spacing = 10
        let privacy = NSTextField(wrappingLabelWithString: "辅助功能仅用于读取窗口与切换焦点。无自动化权限申请，无正文读取。退出工具不退出 Office。")
        privacy.textColor = .secondaryLabelColor; privacy.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [title, subtitle, status, scroll, buttons, actionStatus, eventStatus, privacy])
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
        window.center(); window.makeKeyAndOrderFront(nil)
    }
    private func selectFrontmostApp() {
        guard let profile = OfficeApp(bundleID:NSWorkspace.shared.frontmostApplication?.bundleIdentifier), profile != route.app else { return }
        _ = route.select(profile)
        tabs.enabled = preferences.tabsEnabled(for:profile)
        state = WindowState(); details = []; targets = []; tableKey = ""
        table.reloadData(); tabs.hide(); updateControls()
        window.title = "MacOfficeTabs · \(profile.name) 窗口诊断"
    }
    @objc private func refreshClicked() { refresh() }
    private func refresh() {
        guard !scanning, !controlling else { return }
        selectFrontmostApp()
        let ticket = route.ticket
        let client = self.client
        shortcuts.update(eligible:false)
        scanning = true; refreshButton.isEnabled = false; activateButton.isEnabled = false
        let selected = table.selectedRow >= 0 && table.selectedRow < targets.count ? targets[table.selectedRow].id : nil
        queue.async { [weak self] in
            guard let self else { return }
            let result = client.scan()
            DispatchQueue.main.async {
                self.scanning = false; self.refreshButton.isEnabled = true
                guard self.route.accepts(ticket) else { self.refresh(); return }
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
                self.eventStatus.stringValue = "最近事件：\(self.events.last ?? "无") · \(self.tabs.diagnostic)"
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
        let client = self.client
        shortcuts.update(eligible:false)
        controlling = true; updateControls(); refreshButton.isEnabled = false
        tabs.hide()
        actionStatus.stringValue = "正在验证目标窗口…（有限等待）"
        queue.async { [weak self] in
            guard let self else { return }
            let message = closing ? client.closeTab(id) : client.activateTab(id).message
            DispatchQueue.main.async {
                self.controlling = false
                guard self.route.accepts(ticket) else { self.refresh(); return }
                self.actionStatus.stringValue = message
                self.recordEvent(closing ? "关闭结果：" + message : "激活结果：" + message); self.refresh()
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
        actionStatus.stringValue = "诊断已复制，包含窗口标题。分享前请检查敏感信息。"
    }
    private func recordEvent(_ event: String) {
        events.append("\(Date().formatted(date: .omitted, time: .standard)) \(event)")
        if events.count > 30 { events.removeFirst(events.count - 30) }
        eventStatus.stringValue = "最近事件：\(events.last ?? "无") · 已确认文件关联 \(registry.documents.count)"
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
        case "focus": text = target.focused ? "是" : "否"
        case "min": text = detail?.minimized.map { $0 ? "是" : "否" } ?? "未知"
        default:
            text = target.menuCandidate ? (target.canClose ? "菜单对象 · 已核验 AX 关联" : "菜单对象 · 首次关联前禁止关闭") : "AX 窗口 · URL 可用性以实际读取为准"
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

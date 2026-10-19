import AppKit
import ServiceManagement
import OfficeTabsCore

final class SettingsController: NSObject {
    private let preferences: OfficePreferences
    private let window = NSWindow(contentRect:NSRect(x:0,y:0,width:510,height:340),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    private var tabButtons:[OfficeApp:NSButton] = [:]
    private let shortcut = NSButton(checkboxWithTitle:"启用 ⌃⌥⌘←/→ 切换当前应用标签",target:nil,action:nil)
    private let login = NSButton(checkboxWithTitle:"登录时启动 MacOfficeTabs",target:nil,action:nil)
    private let loginStatus = NSTextField(wrappingLabelWithString:"")
    private let shortcutStatus = NSTextField(wrappingLabelWithString:"")
    var changed:(() -> Void)?
    init(preferences:OfficePreferences) {
        self.preferences = preferences
        super.init()
        window.title = "MacOfficeTabs 设置"; window.isReleasedWhenClosed = false
        var views:[NSView] = [NSTextField(labelWithString:"显示标签栏")]
        for app in OfficeApp.allCases {
            let button = NSButton(checkboxWithTitle:app.name,target:self,action:#selector(toggleTab(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(app.rawValue)
            tabButtons[app] = button; views.append(button)
        }
        shortcut.target = self; shortcut.action = #selector(toggleShortcut)
        login.target = self; login.action = #selector(toggleLogin)
        let explanation = NSTextField(wrappingLabelWithString:"快捷键仅在 Office 前台、无模态且焦点已核验时占用。开机启动由 macOS 管理，可能需要在系统设置中批准。")
        explanation.textColor = .secondaryLabelColor
        let system = NSButton(title:"打开登录项设置",target:self,action:#selector(openLoginSettings))
        views += [shortcut,shortcutStatus,login,loginStatus,system,explanation]
        let stack = NSStackView(views:views); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:24),
                                     stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-24),
                                     stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:20),
                                     explanation.widthAnchor.constraint(equalTo:stack.widthAnchor),
                                     loginStatus.widthAnchor.constraint(equalTo:stack.widthAnchor),
                                     shortcutStatus.widthAnchor.constraint(equalTo:stack.widthAnchor)])
        window.center()
    }
    func show() {
        for (app,button) in tabButtons { button.state = preferences.tabsEnabled(for:app) ? .on : .off }
        shortcut.state = preferences.shortcutsEnabled ? .on : .off
        refreshLoginStatus(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func setShortcutStatus(_ status:String) { shortcutStatus.stringValue = status }
    @objc private func toggleTab(_ sender:NSButton) {
        guard let app = OfficeApp(bundleID:sender.identifier?.rawValue) else { return }
        preferences.setTabsEnabled(sender.state == .on,for:app); changed?()
    }
    @objc private func toggleShortcut() { preferences.shortcutsEnabled = shortcut.state == .on; changed?() }
    @objc private func toggleLogin() {
        do {
            if login.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
        } catch {
            refreshLoginStatus()
            let failure = error as NSError
            loginStatus.stringValue += " · 操作失败：\(failure.localizedDescription)（\(failure.domain):\(failure.code)）"
        }
    }
    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        login.state = (status == .enabled || status == .requiresApproval) ? .on : .off
        switch status {
        case .enabled: loginStatus.stringValue = "系统状态：已启用"
        case .requiresApproval: loginStatus.stringValue = "系统状态：等待你在登录项设置中批准"
        case .notRegistered: loginStatus.stringValue = "系统状态：未注册（默认关闭）"
        case .notFound: loginStatus.stringValue = "系统状态：尚未找到服务；可显式开启后检查注册结果"
        @unknown default: loginStatus.stringValue = "系统状态：未知"
        }
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}

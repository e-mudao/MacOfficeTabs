import AppKit
import ServiceManagement
import OfficeTabsCore

final class SettingsController: NSObject {
    private let preferences: OfficePreferences
    private let window = NSWindow(contentRect:NSRect(x:0,y:0,width:640,height:450),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    private var tabButtons:[OfficeApp:NSButton] = [:]
    private let languageLabel = NSTextField(labelWithString: "")
    private let languageChoice = NSPopUpButton()
    private let tabsLabel = NSTextField(labelWithString: "")
    private let shortcut = NSButton(checkboxWithTitle:"",target:nil,action:nil)
    private let login = NSButton(checkboxWithTitle:"",target:nil,action:nil)
    private let loginStatus = NSTextField(wrappingLabelWithString:"")
    private let shortcutStatus = NSTextField(wrappingLabelWithString:"")
    private let explanation = NSTextField(wrappingLabelWithString:"")
    private let system = NSButton(title:"",target:nil,action:nil)
    var changed:(() -> Void)?
    var languageChanged:(() -> Void)?
    init(preferences:OfficePreferences) {
        self.preferences = preferences
        super.init()
        window.isReleasedWhenClosed = false
        languageChoice.addItems(withTitles:["简体中文", "English"])
        languageChoice.target = self; languageChoice.action = #selector(changeLanguage)
        let languageRow = NSStackView(views:[languageLabel,languageChoice]); languageRow.orientation = .horizontal; languageRow.spacing = 12
        var views:[NSView] = [languageRow,tabsLabel]
        for app in OfficeApp.allCases {
            let button = NSButton(checkboxWithTitle:app.name,target:self,action:#selector(toggleTab(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(app.rawValue)
            tabButtons[app] = button; views.append(button)
        }
        shortcut.target = self; shortcut.action = #selector(toggleShortcut)
        login.target = self; login.action = #selector(toggleLogin)
        explanation.textColor = .secondaryLabelColor
        system.target = self; system.action = #selector(openLoginSettings)
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
        localize()
    }
    func show() {
        localize()
        for (app,button) in tabButtons { button.state = preferences.tabsEnabled(for:app) ? .on : .off }
        shortcut.state = preferences.shortcutsEnabled ? .on : .off
        refreshLoginStatus(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func setShortcutStatus(_ status:String) { shortcutStatus.stringValue = status }
    func localize() {
        window.title = T("settings.title")
        languageLabel.stringValue = T("settings.language")
        languageChoice.setAccessibilityLabel(T("settings.language"))
        languageChoice.selectItem(at: preferences.language == .english ? 1 : 0)
        tabsLabel.stringValue = T("settings.showTabs")
        shortcut.title = T("settings.shortcut")
        login.title = T("settings.login")
        system.title = T("settings.openLogin")
        explanation.stringValue = T("settings.explanation")
        refreshLoginStatus()
    }
    @objc private func changeLanguage() {
        preferences.language = languageChoice.indexOfSelectedItem == 1 ? .english : .simplifiedChinese
        localize(); languageChanged?()
    }
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
            loginStatus.stringValue += T("settings.operationFailed", failure.localizedDescription, failure.domain, failure.code)
        }
    }
    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        login.state = (status == .enabled || status == .requiresApproval) ? .on : .off
        switch status {
        case .enabled: loginStatus.stringValue = T("settings.loginEnabled")
        case .requiresApproval: loginStatus.stringValue = T("settings.loginApproval")
        case .notRegistered: loginStatus.stringValue = T("settings.loginNotRegistered")
        case .notFound: loginStatus.stringValue = T("settings.loginNotFound")
        @unknown default: loginStatus.stringValue = T("settings.loginUnknown")
        }
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
}

import OfficeTabsCore

/// Reads the current choice for each message, including messages produced on the AX queue.
func T(_ key: String, _ arguments: CVarArg...) -> String {
    AppText.render(key, language: OfficePreferences().language, arguments: arguments)
}

extension ShortcutController {
    var status: String {
        switch state {
        case .off: return T("shortcut.off")
        case .inactive: return T("shortcut.inactive")
        case .handlerUnavailable: return T("shortcut.handlerUnavailable")
        case .registrationFailed(let code): return T("shortcut.registrationFailed", code)
        case .registered: return T("shortcut.registered")
        }
    }
}

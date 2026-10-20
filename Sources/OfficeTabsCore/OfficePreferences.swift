import Foundation

public enum AppLanguage: String, CaseIterable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"
}

public final class OfficePreferences {
    private let defaults: UserDefaults
    public init(defaults:UserDefaults = .standard) { self.defaults = defaults }
    public var language: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: "interfaceLanguage") ?? "") ?? .simplifiedChinese }
        set { defaults.set(newValue.rawValue, forKey: "interfaceLanguage") }
    }
    public var shortcutsEnabled: Bool {
        get { defaults.bool(forKey:"shortcutsEnabled") }
        set { defaults.set(newValue,forKey:"shortcutsEnabled") }
    }
    public func tabsEnabled(for app:OfficeApp) -> Bool {
        defaults.object(forKey:"tabs." + app.rawValue) as? Bool ?? true
    }
    public func setTabsEnabled(_ enabled:Bool,for app:OfficeApp) {
        defaults.set(enabled,forKey:"tabs." + app.rawValue)
    }
}
public enum ShortcutPolicy {
    public static func eligible(enabled:Bool,frontmost:OfficeApp?,selected:OfficeApp,safe:Bool,busy:Bool,tabsEnabled:Bool) -> Bool {
        enabled && frontmost == selected && safe && !busy && tabsEnabled
    }
    public static func next(in order:[UUID],focused:UUID?,forward:Bool) -> UUID? {
        guard order.count > 1,let focused,let index = order.firstIndex(of:focused) else { return nil }
        return order[(index + (forward ? 1 : order.count-1)) % order.count]
    }
}

import XCTest
@testable import OfficeTabsCore

final class PreferencesTests: XCTestCase {
    func testDefaultsAndPersistenceAreIsolatedPerApplication() {
        let name = "MacOfficeTabs-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let preferences = OfficePreferences(defaults:defaults)
        XCTAssertFalse(preferences.shortcutsEnabled)
        XCTAssertTrue(preferences.tabsEnabled(for:.word))
        preferences.setTabsEnabled(false,for:.excel)
        preferences.shortcutsEnabled = true
        let restored = OfficePreferences(defaults:defaults)
        XCTAssertFalse(restored.tabsEnabled(for:.excel))
        XCTAssertTrue(restored.tabsEnabled(for:.word))
        XCTAssertTrue(restored.shortcutsEnabled)
    }
    func testLanguageDefaultsToChineseAndPersistsEnglishAcrossPreferencesInstances() {
        let name = "MacOfficeTabs-language-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName:name)!
        defer { defaults.removePersistentDomain(forName:name) }
        let preferences = OfficePreferences(defaults: defaults)
        XCTAssertEqual(preferences.language, .simplifiedChinese)
        preferences.language = .english
        XCTAssertEqual(OfficePreferences(defaults: defaults).language, .english)
        defaults.set("unsupported", forKey: "interfaceLanguage")
        XCTAssertEqual(preferences.language, .simplifiedChinese)
    }
    func testLocalizedMessagesPreserveDynamicNamesAndUseSelectedLanguage() {
        XCTAssertEqual(AppText.string("settings.title", language: .english), "MacOfficeTabs Settings")
        XCTAssertEqual(AppText.string("settings.title", language: .simplifiedChinese), "MacOfficeTabs 设置")
        XCTAssertEqual(AppText.format("scan.officeNotRunning", language: .english, "Word"), "Word is not running. Open a test document in Office.")
        XCTAssertEqual(AppText.format("scan.officeNotRunning", language: .simplifiedChinese, "Word"), "Word 未运行。请自行打开测试文档。")
        XCTAssertEqual(AppText.format("scan.summary", language: .english, "Excel", 3, 3, 2, 2, 1, "true", "none"),
                       "Excel · 3 tabs (menu 3) · 2 standard window candidates (checked 2, fullscreen 1, safe focus true); blockers: none; unknown document identities are not merged.")
        XCTAssertEqual(AppText.format("close.pressRejected", language: .english, -25205),
                       "Office rejected the close request [AXPress=-25205].")
    }
    func testCycleRequiresProvenFocusAndWrapsInVisualOrder() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(ShortcutPolicy.next(in:[c,a,b],focused:b,forward:true),c)
        XCTAssertEqual(ShortcutPolicy.next(in:[c,a,b],focused:c,forward:false),b)
        XCTAssertNil(ShortcutPolicy.next(in:[a,b],focused:nil,forward:true))
        XCTAssertNil(ShortcutPolicy.next(in:[a],focused:a,forward:true))
    }
    func testRegistrationRequiresAllSafetyConditions() {
        XCTAssertTrue(ShortcutPolicy.eligible(enabled:true,frontmost:.word,selected:.word,safe:true,busy:false,tabsEnabled:true))
        XCTAssertFalse(ShortcutPolicy.eligible(enabled:true,frontmost:.excel,selected:.word,safe:true,busy:false,tabsEnabled:true))
        XCTAssertFalse(ShortcutPolicy.eligible(enabled:true,frontmost:.word,selected:.word,safe:false,busy:false,tabsEnabled:true))
        XCTAssertFalse(ShortcutPolicy.eligible(enabled:true,frontmost:.word,selected:.word,safe:true,busy:true,tabsEnabled:true))
        XCTAssertFalse(ShortcutPolicy.eligible(enabled:false,frontmost:.word,selected:.word,safe:true,busy:false,tabsEnabled:true))
    }
}

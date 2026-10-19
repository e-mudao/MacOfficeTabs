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

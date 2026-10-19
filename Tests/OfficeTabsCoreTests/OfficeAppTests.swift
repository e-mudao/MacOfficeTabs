import XCTest
@testable import OfficeTabsCore
final class OfficeAppTests: XCTestCase {
    func testOnlySupportedBundlesRouteToAnOfficeClient() {
        XCTAssertEqual(OfficeApp(bundleID:"com.microsoft.Word"),.word)
        XCTAssertEqual(OfficeApp(bundleID:"com.microsoft.Excel"),.excel)
        XCTAssertEqual(OfficeApp(bundleID:"com.microsoft.Powerpoint"),.powerPoint)
        XCTAssertNil(OfficeApp(bundleID:"com.microsoft.Outlook"))
        XCTAssertNil(OfficeApp(bundleID:nil))
    }
    func testWindowIdentitiesStaySeparateForDifferentOfficePIDs() {
        let store = IdentityStore<Int>()
        XCTAssertNotEqual(store.identity(processID:11,token:1),store.identity(processID:22,token:1))
        store.remove(processID:11)
        let excel = store.identity(processID:22,token:1)
        XCTAssertEqual(excel,store.identity(processID:22,token:1))
    }
}

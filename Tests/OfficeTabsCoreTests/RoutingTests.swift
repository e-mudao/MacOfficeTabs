import XCTest
@testable import OfficeTabsCore

final class RoutingTests: XCTestCase {
    func testLateResultFromPreviousAppCannotReplaceCurrentApp() {
        var route = OfficeRoute()
        let word = route.select(.word)
        let excel = route.select(.excel)
        XCTAssertFalse(route.accepts(word))
        XCTAssertTrue(route.accepts(excel))
        let returnedWord = route.select(.word)
        XCTAssertFalse(route.accepts(word))
        XCTAssertTrue(route.accepts(returnedWord))
    }
}

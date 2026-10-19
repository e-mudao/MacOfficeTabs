import XCTest
@testable import OfficeTabsCore

final class WindowInventoryTests: XCTestCase {
    func testCurrentSheetIncludedButAbsentSheetDroppedWithoutDestroyNotification() throws {
        let inventory = WindowInventory<String>()
        let standard: (String) throws -> Bool = { $0 == "document" }
        XCTAssertEqual(try inventory.resolve(processID:1,discovered:["document","sheet"],
            retainAcrossAbsence:standard) { _ in true },["document","sheet"])
        XCTAssertEqual(try inventory.resolve(processID:1,discovered:["document"],
            retainAcrossAbsence:standard) { _ in true },["document"])
    }
    func testStandardDocumentInOtherSpaceRetainedWithFreshLivenessProbe() throws {
        let inventory = WindowInventory<String>()
        _ = try inventory.resolve(processID:1,discovered:["a","b"]) { _ in true }
        var probed: [String] = []
        XCTAssertEqual(try inventory.resolve(processID:1,discovered:["b"],
            retainAcrossAbsence:{ _ in true }) { probed.append($0); return true },["a","b"])
        XCTAssertEqual(probed,["a","b"])
    }
    func testUnknownAbsentWindowClassificationFailsSnapshot() throws {
        enum Failure: Error { case unknown }
        let inventory = WindowInventory<String>()
        _ = try inventory.resolve(processID:1,discovered:["document","unknown"]) { _ in true }
        XCTAssertThrowsError(try inventory.resolve(processID:1,discovered:["document"],
            retainAcrossAbsence:{ _ in throw Failure.unknown }) { _ in true })
    }
    func testDestroyedSheetIsRemovedEvenIfAXStillReadsItsOldRole() throws {
        let inventory = WindowInventory<String>()
        _ = try inventory.resolve(processID:1,discovered:["document","sheet"]) { _ in true }
        inventory.invalidate(processID:1,token:"sheet")
        XCTAssertEqual(try inventory.resolve(processID:1,discovered:["document"]) { _ in true },["document"])
    }
    func testDestructionFromOtherProcessCannotRemoveCurrentReference() throws {
        let inventory = WindowInventory<String>()
        _ = try inventory.resolve(processID:2,discovered:["document"]) { _ in true }
        inventory.invalidate(processID:1,token:"document")
        XCTAssertEqual(try inventory.resolve(processID:2,discovered:[]) { _ in true },["document"])
    }
    func testOtherSpaceRemainsOnlyAfterFreshValidation() throws {
        let inventory = WindowInventory<String>()
        _ = try inventory.resolve(processID:1,discovered:["a","b"]) { _ in true }
        var probed: [String] = []
        let result = try inventory.resolve(processID:1,discovered:["b"]) { probed.append($0); return true }
        XCTAssertEqual(result,["a","b"])
        XCTAssertEqual(probed,["a","b"])
    }
    func testClosedWindowRemovedAndDuplicateSourcesMerged() throws {
        let inventory = WindowInventory<String>()
        _ = try inventory.resolve(processID:1,discovered:["a","b"]) { _ in true }
        XCTAssertEqual(try inventory.resolve(processID:1,discovered:["b","b","c"]) { $0 != "a" },["b","c"])
        XCTAssertEqual(try inventory.resolve(processID:1,discovered:[]) { _ in true },["b","c"])
    }
    func testUnknownProbeCannotProduceSuccessfulSnapshot() throws {
        enum Failure: Error { case unavailable }
        let inventory = WindowInventory<String>()
        _ = try inventory.resolve(processID:1,discovered:["a","b"]) { _ in true }
        XCTAssertThrowsError(try inventory.resolve(processID:1,discovered:[]) { token in
            if token == "a" { throw Failure.unavailable }; return true
        })
        XCTAssertEqual(try inventory.resolve(processID:1,discovered:[]) { _ in true },["a","b"])
    }
    func testRestartAndPermissionClearDropPreviousReferences() throws {
        let inventory = WindowInventory<String>()
        _ = try inventory.resolve(processID:1,discovered:["old"]) { _ in true }
        XCTAssertEqual(try inventory.resolve(processID:2,discovered:["new"]) { _ in true },["new"])
        inventory.clear()
        XCTAssertEqual(try inventory.resolve(processID:2,discovered:[]) { _ in true },[])
    }
}

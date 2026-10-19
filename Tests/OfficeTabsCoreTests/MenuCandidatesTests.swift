import XCTest
@testable import OfficeTabsCore

final class MenuCandidatesTests: XCTestCase {
    func testSameTitlesStaySeparateAndCannotCloseBeforeProof() {
        let store = MenuCandidates<Int>()
        let entries = store.reconcile(processID: 7, sources: [(1,"same"),(2,"same")])
        XCTAssertEqual(entries.count,2)
        XCTAssertNotEqual(entries[0].id,entries[1].id)
        XCTAssertNil(entries[0].windowID)
        XCTAssertFalse(store.associate(entries[0].id,windowID:UUID(),selectedIDs:[entries[0].id,entries[1].id],frontmost:false,standardFocus:true))
        XCTAssertNil(store.entries[0].windowID)
    }
    func testOnlyUniqueSelectedSourceCanAssociateAndReplacementDropsLink() {
        let store = MenuCandidates<Int>()
        let entry = store.reconcile(processID:7,sources:[(1,"same")])[0]
        let window = UUID()
        XCTAssertTrue(store.associate(entry.id,windowID:window,selectedIDs:[entry.id],frontmost:true,standardFocus:true))
        XCTAssertEqual(store.reconcile(processID:7,sources:[(1,"same")])[0].windowID,window)
        let replacement = store.reconcile(processID:7,sources:[(1,"renamed")])[0]
        XCTAssertNotEqual(entry.id,replacement.id)
        XCTAssertNil(replacement.windowID)
        XCTAssertFalse(store.associate(entry.id,windowID:window,selectedIDs:[entry.id],frontmost:true,standardFocus:true))
    }
    func testRemovalProcessChangeAndAmbiguousProofInvalidate() {
        let store = MenuCandidates<Int>()
        let entries = store.reconcile(processID:7,sources:[(1,"a"),(2,"b")])
        XCTAssertFalse(store.associate(entries[0].id,windowID:UUID(),selectedIDs:entries.map(\.id),frontmost:true,standardFocus:true))
        XCTAssertEqual(store.reconcile(processID:7,sources:[(2,"b")]).map(\.id),[entries[1].id])
        XCTAssertNotEqual(store.reconcile(processID:8,sources:[(2,"b")])[0].id,entries[1].id)
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }
    func testNewVerifiedSourceForSameWindowDropsOldAssociation() {
        let store = MenuCandidates<Int>()
        let entries = store.reconcile(processID:7,sources:[(1,"a"),(2,"b")])
        let window = UUID()
        XCTAssertTrue(store.associate(entries[0].id,windowID:window,selectedIDs:[entries[0].id],frontmost:true,standardFocus:true))
        XCTAssertTrue(store.associate(entries[1].id,windowID:window,selectedIDs:[entries[1].id],frontmost:true,standardFocus:true))
        XCTAssertNil(store.entries[0].windowID)
        XCTAssertEqual(store.entries[1].windowID,window)
    }
    func testVerifiedFocusDoesNotDependOnStaleMenuMarkAndRemovedSourceCannotHighlight() {
        let store = MenuCandidates<Int>()
        let entries = store.reconcile(processID:7,sources:[(1,"same"),(2,"same")])
        let window = UUID()
        XCTAssertFalse(store.isFocused(entries[0].id,focusedWindowID:window))
        XCTAssertFalse(store.isFocused(entries[0].id,focusedWindowID:nil))
        XCTAssertTrue(store.associate(entries[0].id,windowID:window,selectedIDs:[entries[0].id],frontmost:true,standardFocus:true))
        XCTAssertTrue(store.isFocused(entries[0].id,focusedWindowID:window))
        XCTAssertFalse(store.isFocused(entries[1].id,focusedWindowID:window))
        store.reconcile(processID:7,sources:[(2,"same")])
        XCTAssertFalse(store.isFocused(entries[0].id,focusedWindowID:window))
    }

}

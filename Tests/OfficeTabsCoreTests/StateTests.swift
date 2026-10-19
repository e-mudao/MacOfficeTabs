import XCTest
@testable import OfficeTabsCore
final class StateTests: XCTestCase {
    func testStableObjectIdentity() {
        let store = IdentityStore<String>()
        XCTAssertEqual(store.identity(processID: 1, token: "ax1"), store.identity(processID: 1, token: "ax1"))
    }
    func testSameTitleDifferentWindowsAreDistinct() {
        let store = IdentityStore<String>()
        XCTAssertNotEqual(store.identity(processID: 1, token: "ax1"), store.identity(processID: 1, token: "ax2"))
    }
    func testPIDPartitionsIdentity() {
        let store = IdentityStore<String>()
        XCTAssertNotEqual(store.identity(processID: 1, token: "ax1"), store.identity(processID: 2, token: "ax1"))
    }
    func testSuccessfulScanRetainsOnlyLiveWindows() {
        let store = IdentityStore<String>()
        let live = store.identity(processID: 1, token: "live")
        let gone = store.identity(processID: 1, token: "gone")
        store.retain(processID: 1, tokens: ["live"])
        XCTAssertEqual(live, store.identity(processID: 1, token: "live"))
        XCTAssertNotEqual(gone, store.identity(processID: 1, token: "gone"))
    }
    func testProcessExitResetsIdentity() {
        let store = IdentityStore<String>()
        let old = store.identity(processID: 1, token: "ax")
        store.remove(processID: 1)
        XCTAssertNotEqual(old, store.identity(processID: 1, token: "ax"))
    }
    func testUnobservedWindowKeepsIdentityUntilConfirmedInvalid() {
        let store = IdentityStore<String>()
        let invisible = store.identity(processID: 1, token: "other-space")
        let closed = store.identity(processID: 1, token: "closed")
        store.invalidate(processID: 1, tokens: ["closed"])
        XCTAssertEqual(invisible, store.identity(processID: 1, token: "other-space"))
        XCTAssertNotEqual(closed, store.identity(processID: 1, token: "closed"))
    }
    func testInvalidationDoesNotAffectAnotherProcess() {
        let store = IdentityStore<String>()
        let other = store.identity(processID: 2, token: "same-object")
        store.invalidate(processID: 1, tokens: ["same-object"])
        XCTAssertEqual(other, store.identity(processID: 2, token: "same-object"))
    }
    func testRegistryUsesKnownURLNotTitle() {
        var registry = DocumentRegistry()
        let a = WindowRecord(id: UUID(), processID: 1, title: "same", fileURL: URL(fileURLWithPath: "/a/same.docx"))
        let b = WindowRecord(id: UUID(), processID: 1, title: "same", fileURL: URL(fileURLWithPath: "/b/same.docx"))
        registry.reconcile([a,b])
        XCTAssertEqual(registry.documents.count, 2)
    }
    func testOneDocumentMultipleWindows() {
        var registry = DocumentRegistry()
        let url = URL(fileURLWithPath: "/a.docx")
        let a = WindowRecord(id: UUID(), processID: 1, title: "a", fileURL: url)
        let b = WindowRecord(id: UUID(), processID: 1, title: "a:2", fileURL: url)
        registry.reconcile([a,b])
        XCTAssertEqual(registry.documents.first?.windowIDs, Set([a.id,b.id]))
    }
    func testUnknownDocumentDoesNotInventMapping() {
        var registry = DocumentRegistry()
        registry.reconcile([WindowRecord(id: UUID(), processID: 1, title: "untitled")])
        XCTAssertTrue(registry.documents.isEmpty)
    }
    func testKnownDocumentIdentitySurvivesTitleChange() {
        var registry = DocumentRegistry()
        var a = WindowRecord(id: UUID(), processID: 1, title: "a", fileURL: URL(fileURLWithPath: "/a.docx"))
        registry.reconcile([a]); let old = registry.documents.first?.id
        a.title = "renamed window"; registry.reconcile([a])
        XCTAssertNotNil(old)
        XCTAssertEqual(old, registry.documents.first?.id)
    }
    func testFailedScanPreservesStaleSnapshotButDisablesControl() {
        var state = WindowState()
        let a = WindowRecord(id: UUID(), processID: 1, title: "a")
        state.apply(.success([a])); state.apply(.failure("timeout"))
        XCTAssertEqual(state.windows, [a]); XCTAssertFalse(state.canControl)
    }
    func testSuccessfulEmptyScanClearsWindows() {
        var state = WindowState()
        state.apply(.success([WindowRecord(id: UUID(), processID: 1, title: "a")]))
        state.apply(.success([])); XCTAssertTrue(state.windows.isEmpty)
    }
    func testRevocationClearsWindowsAndDisablesControl() {
        var state = WindowState()
        state.apply(.success([WindowRecord(id: UUID(), processID: 1, title: "a")]))
        state.apply(.denied); XCTAssertTrue(state.windows.isEmpty); XCTAssertFalse(state.canControl)
    }
    func testActivationRequiresBothActualFocusAndFrontmost() {
        let id = UUID(); let verifier = ActivationVerifier(target: id, processID: 1, deadline: 10)
        XCTAssertEqual(verifier.evaluate(focused: id, frontmostPID: 2, now: 1), .pending)
        XCTAssertEqual(verifier.evaluate(focused: UUID(), frontmostPID: 1, now: 1), .pending)
        XCTAssertEqual(verifier.evaluate(focused: id, frontmostPID: 1, now: 1), .confirmed)
    }
    func testActivationDeadlineIsFinite() {
        let verifier = ActivationVerifier(target: UUID(), processID: 1, deadline: 10)
        XCTAssertEqual(verifier.evaluate(focused: nil, frontmostPID: 1, now: 10), .failed)
    }
}

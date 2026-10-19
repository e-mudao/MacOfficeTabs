import XCTest
@testable import OfficeTabsCore

final class AssociationPolicyTests: XCTestCase {
    func testSingleDocumentCanAssociateAfterStableFreshSingletonChecks() {
        let window = UUID()
        XCTAssertTrue(CandidateAssociationPolicy.permits(previousFocus:window,actualFocus:window,associated:nil,
            soleCandidateBefore:true,soleCandidateAfter:true,windowsBefore:[window],windowsAfter:[window]))
    }
    func testOneVisibleWindowCannotBindAmongMultipleSpaceCandidates() {
        let window = UUID()
        XCTAssertFalse(CandidateAssociationPolicy.permits(previousFocus:window,actualFocus:window,associated:nil,
            soleCandidateBefore:false,soleCandidateAfter:false,windowsBefore:[window],windowsAfter:[window]))
    }
    func testCandidateOrWindowChangeRejectsUnchangedFocusAssociation() {
        let window = UUID(), other = UUID()
        XCTAssertFalse(CandidateAssociationPolicy.permits(previousFocus:window,actualFocus:window,associated:nil,
            soleCandidateBefore:true,soleCandidateAfter:false,windowsBefore:[window],windowsAfter:[window]))
        XCTAssertFalse(CandidateAssociationPolicy.permits(previousFocus:window,actualFocus:window,associated:nil,
            soleCandidateBefore:true,soleCandidateAfter:true,windowsBefore:[window],windowsAfter:[window,other]))
        XCTAssertFalse(CandidateAssociationPolicy.permits(previousFocus:window,actualFocus:window,associated:nil,
            soleCandidateBefore:true,soleCandidateAfter:true,windowsBefore:[other],windowsAfter:[window]))
    }
    func testObservedTransitionAndProvenAssociationKeepExistingBehavior() {
        let window = UUID(), other = UUID()
        XCTAssertTrue(CandidateAssociationPolicy.permits(previousFocus:other,actualFocus:window,associated:nil,
            soleCandidateBefore:false,soleCandidateAfter:false,windowsBefore:[other],windowsAfter:[window]))
        XCTAssertTrue(CandidateAssociationPolicy.permits(previousFocus:window,actualFocus:window,associated:window,
            soleCandidateBefore:false,soleCandidateAfter:false,windowsBefore:[window],windowsAfter:[window]))
    }
}

import XCTest
@testable import OfficeTabsCore
final class SafetyTests: XCTestCase {
    func testUnknownChildInspectionRefusesActivation() {
        XCTAssertFalse(ControlSafety.permits(hasTarget: true, focusedStandard: true, childrenInspected: false, blockingWindow: false))
    }
    func testDialogRefusesActivation() {
        XCTAssertFalse(ControlSafety.permits(hasTarget: true, focusedStandard: true, childrenInspected: true, blockingWindow: true))
    }
    func testUnknownFocusRefusesActivation() {
        XCTAssertFalse(ControlSafety.permits(hasTarget: true, focusedStandard: false, childrenInspected: true, blockingWindow: false))
    }
    func testMissingTargetRefusesActivation() {
        XCTAssertFalse(ControlSafety.permits(hasTarget: false, focusedStandard: true, childrenInspected: true, blockingWindow: false))
    }
    func testInspectedStandardTargetPermitsActivation() {
        XCTAssertTrue(ControlSafety.permits(hasTarget: true, focusedStandard: true, childrenInspected: true, blockingWindow: false))
    }
    func testNonfiniteGeometryCannotReachUIIntegerConversion() {
        XCTAssertFalse(ControlSafety.validFrame(CGRect(x: Double.nan, y: 0, width: 100, height: 100)))
        XCTAssertFalse(ControlSafety.validFrame(CGRect(x: 0, y: 0, width: Double.infinity, height: 100)))
        XCTAssertFalse(ControlSafety.validFrame(CGRect(x: 0, y: 0, width: 0, height: 100)))
        XCTAssertTrue(ControlSafety.validFrame(CGRect(x: -1920, y: -900, width: 100, height: 100)))
    }
}

final class PreflightReasonTests: XCTestCase {
    func testMissingTargetReportsReasonBeforeFocus() {
        XCTAssertEqual(ControlSafety.rejection(hasTarget: false, focusedStandard: false, childrenInspected: true, blockingWindow: false), "targetMissing")
    }
    func testUnknownFocusReportsReason() {
        XCTAssertEqual(ControlSafety.rejection(hasTarget: true, focusedStandard: false, childrenInspected: true, blockingWindow: false), "focusUnknown")
    }
    func testSheetReportsReason() {
        XCTAssertEqual(ControlSafety.rejection(hasTarget: true, focusedStandard: true, childrenInspected: true, blockingWindow: true), "blockingWindow")
    }
    func testUnknownChildrenReportsReason() {
        XCTAssertEqual(ControlSafety.rejection(hasTarget: true, focusedStandard: true, childrenInspected: false, blockingWindow: false), "childrenUnknown")
    }
    func testSafeInspectionHasNoRejection() {
        XCTAssertNil(ControlSafety.rejection(hasTarget: true, focusedStandard: true, childrenInspected: true, blockingWindow: false))
    }
}

final class ModalClassificationTests: XCTestCase {
    func testExplicitNonmodalAuxiliaryWindowDoesNotBlockDocuments() {
        XCTAssertFalse(ControlSafety.blocksWindow(isStandard: false, isModal: false, isSheet: false))
    }
    func testUnknownAuxiliaryWindowStillBlocks() {
        XCTAssertTrue(ControlSafety.blocksWindow(isStandard: false, isModal: nil, isSheet: false))
    }
    func testModalStandardWindowStillBlocks() {
        XCTAssertTrue(ControlSafety.blocksWindow(isStandard: true, isModal: true, isSheet: false))
    }
    func testSheetBlocksEvenIfModalFlagFalse() {
        XCTAssertTrue(ControlSafety.blocksWindow(isStandard: false, isModal: false, isSheet: true))
    }
    func testOrdinaryDocumentWithoutOptionalModalAttributeIsAllowed() {
        XCTAssertFalse(ControlSafety.blocksWindow(isStandard: true, isModal: nil, isSheet: false))
    }
}

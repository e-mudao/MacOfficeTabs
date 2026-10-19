import XCTest
@testable import OfficeTabsCore

final class CloseVerificationTests: XCTestCase {
    func testAcceptedActionWithoutObservableEffectIsNotSuccess() {
        let verifier = CloseVerifier(deadline:2)
        XCTAssertEqual(verifier.evaluate(targetInvalid:false,nativePrompt:false,now:1),.waiting)
        XCTAssertEqual(verifier.evaluate(targetInvalid:false,nativePrompt:false,now:2),.unconfirmed)
    }
    func testSavePromptKeepsWindowAndDoesNotMeanClosed() {
        let verifier = CloseVerifier(deadline:2)
        XCTAssertEqual(verifier.evaluate(targetInvalid:false,nativePrompt:true,now:1),.nativePrompt)
    }
    func testOnlyInvalidatedTargetConfirmsClosed() {
        let verifier = CloseVerifier(deadline:2)
        XCTAssertEqual(verifier.evaluate(targetInvalid:true,nativePrompt:false,now:1),.closed)
    }
}

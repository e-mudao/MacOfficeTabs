import XCTest
@testable import OfficeTabsCore

final class PanelTests: XCTestCase {
    func testFullscreenStripClipsBelowMenuAndNotchSafeArea() {
        let safeScreen = CGRect(x:0,y:0,width:1800,height:1068)
        let result = PanelPlacement.frame(windowAX:CGRect(x:0,y:0,width:1800,height:1100),desktopTop:1100,visibleScreens:[safeScreen])
        XCTAssertEqual(result,CGRect(x:540,y:990,width:720,height:38))
    }
    func testOrderSurvivesTemporaryEmptyEnumeration() {
        var order = TabOrder(); let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(order.ordered([a,b]), [a,b])
        order.move(b, before: a)
        XCTAssertEqual(order.ordered([]), [])
        XCTAssertEqual(order.ordered([a,b,c]), [b,a,c])
    }
    func testMoveToEndAndRemovalDoNotChangeOtherTargets() {
        var order = TabOrder(); let a = UUID(), b = UUID(), c = UUID()
        _ = order.ordered([a,b,c]); order.move(a, before: nil)
        XCTAssertEqual(order.ordered([a,b,c]), [b,c,a])
        order.remove(b); XCTAssertEqual(order.ordered([a,c]), [c,a])
        order.move(UUID(), before: a); XCTAssertEqual(order.ordered([a,c]), [c,a])
    }
    func testAXCoordinatesKeepPanelInsideWindowTop() {
        let screen = CGRect(x:0,y:0,width:1440,height:900)
        let ax = CGRect(x:200,y:100,width:600,height:500)
        XCTAssertEqual(PanelPlacement.frame(windowAX:ax,desktopTop:900,visibleScreens:[screen]),CGRect(x:216,y:722,width:568,height:38))
    }
    func testWindowAtScreenTopDoesNotMovePanelToBottom() {
        let screen = CGRect(x:0,y:0,width:1440,height:900)
        XCTAssertEqual(PanelPlacement.frame(windowAX:CGRect(x:200,y:0,width:600,height:500),desktopTop:900,visibleScreens:[screen]),CGRect(x:216,y:822,width:568,height:38))
    }
    func testRealMaximizedExcelGeometryHasVisibleInternalStrip() {
        let frame = PanelPlacement.frame(windowAX:CGRect(x:0,y:39,width:1800,height:1130),desktopTop:1169,
            visibleScreens:[CGRect(x:0,y:0,width:1800,height:1130)])
        XCTAssertEqual(frame,CGRect(x:540,y:1052,width:720,height:38))
    }
    func testTinyInvisibleOrInvalidWindowCannotPlaceStrip() {
        let screen = CGRect(x:0,y:0,width:1440,height:900)
        XCTAssertNil(PanelPlacement.frame(windowAX:CGRect(x:0,y:0,width:100,height:900),desktopTop:900,visibleScreens:[screen]))
        XCTAssertNil(PanelPlacement.frame(windowAX:CGRect(x:0,y:0,width:800,height:60),desktopTop:900,visibleScreens:[screen]))
        XCTAssertNil(PanelPlacement.frame(windowAX:CGRect(x:2000,y:0,width:800,height:600),desktopTop:900,visibleScreens:[screen]))
        XCTAssertNil(PanelPlacement.frame(windowAX:CGRect(x:0,y:0,width:CGFloat.infinity,height:100),desktopTop:900,visibleScreens:[]))
    }
    func testSecondaryDisplayClipsInsideVisibleWindowIntersection() {
        let screen = CGRect(x:-1280,y:200,width:1280,height:800)
        let ax = CGRect(x:-1400,y:100,width:700,height:400)
        XCTAssertEqual(PanelPlacement.frame(windowAX:ax,desktopTop:900,visibleScreens:[screen]),CGRect(x:-1264,y:722,width:548,height:38))
    }
}

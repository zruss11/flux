import CoreGraphics
import XCTest

@testable import Flux

final class ScreenCaptureTests: XCTestCase {
    func testWindowFrameToScreenCoordsAccountsForScreenOrigin() {
        let screenFrame = CGRect(x: -500, y: 300, width: 1000, height: 800)
        let windowFrame = CGRect(x: -200, y: 600, width: 400, height: 200)

        let converted = ScreenCapture.windowFrameToScreenCoords(windowFrame, screenFrame: screenFrame)

        XCTAssertEqual(converted.origin.x, 300)
        XCTAssertEqual(converted.origin.y, 300)
        XCTAssertEqual(converted.size.width, 400)
        XCTAssertEqual(converted.size.height, 200)
    }

    func testWindowFrameToScreenCoordsMatchesPrimaryOrigin() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let windowFrame = CGRect(x: 120, y: 200, width: 640, height: 360)

        let converted = ScreenCapture.windowFrameToScreenCoords(windowFrame, screenFrame: screenFrame)

        XCTAssertEqual(converted.origin.x, 120)
        XCTAssertEqual(converted.origin.y, 340)
        XCTAssertEqual(converted.size.width, 640)
        XCTAssertEqual(converted.size.height, 360)
    }
}

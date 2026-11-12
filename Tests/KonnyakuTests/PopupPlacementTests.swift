import AppKit
import XCTest
@testable import Konnyaku

/// Where the popup opens relative to the mouse cursor.
@MainActor
final class PopupPlacementTests: XCTestCase {
    /// A 1440×875 visible area, like a laptop below its menu bar.
    private let primary = NSRect(x: 0, y: 0, width: 1440, height: 875)

    /// A display left of and below the primary one: x and y are negative.
    /// Its top 25 points are the menu bar strip outside the visible area.
    private let secondary = NSRect(x: -1920, y: -1080, width: 1920, height: 1055)

    private let size = NSSize(width: 400, height: 300)

    private func origin(
        x: CGFloat,
        y: CGFloat,
        visible: NSRect
    ) -> NSPoint {
        let mouse = NSPoint(x: x, y: y)
        return TranslatePanelController.origin(
            mouse: mouse,
            size: size,
            visible: visible
        )
    }

    /// The panel's top-left corner sits at the cursor.
    func testOpensBelowTheCursor() {
        let result = origin(x: 500, y: 600, visible: primary)
        XCTAssertEqual(result, NSPoint(x: 500, y: 300))
    }

    func testNearTheRightEdgeMovesLeft() {
        let result = origin(x: 1300, y: 600, visible: primary)
        XCTAssertEqual(result, NSPoint(x: 1040, y: 300))
    }

    /// Below the cursor would hang off the bottom, so it rests on the edge.
    func testNearTheBottomEdgeMovesUp() {
        let result = origin(x: 500, y: 100, visible: primary)
        XCTAssertEqual(result, NSPoint(x: 500, y: 0))
    }

    /// A cursor in the menu bar is above the visible area.
    func testCursorAboveTheTopEdgeMovesDown() {
        let result = origin(x: 500, y: 890, visible: primary)
        XCTAssertEqual(result, NSPoint(x: 500, y: 575))
    }

    /// A Dock on the left narrows the visible area; the cursor can be over it.
    func testCursorOverALeftDockMovesRight() {
        let besideDock = NSRect(x: 70, y: 0, width: 1370, height: 875)
        let result = origin(x: 10, y: 600, visible: besideDock)
        XCTAssertEqual(result, NSPoint(x: 70, y: 300))
    }

    func testSecondaryDisplayOpensBelowTheCursor() {
        let result = origin(x: -1000, y: -200, visible: secondary)
        XCTAssertEqual(result, NSPoint(x: -1000, y: -500))
    }

    func testSecondaryDisplayNearItsRightEdgeMovesLeft() {
        let result = origin(x: -50, y: -200, visible: secondary)
        XCTAssertEqual(result, NSPoint(x: -400, y: -500))
    }

    /// Below the cursor would go off the secondary display's bottom edge.
    func testSecondaryDisplayNearItsBottomEdgeMovesUp() {
        let result = origin(x: -1000, y: -1000, visible: secondary)
        XCTAssertEqual(result, NSPoint(x: -1000, y: -1080))
    }

    /// Too big to fit: the top-right corner stays inside, as `clamp` does.
    func testPanelLargerThanTheVisibleArea() {
        let mouse = NSPoint(x: 300, y: 600)
        let large = NSSize(width: 1600, height: 1000)
        let result = TranslatePanelController.origin(
            mouse: mouse,
            size: large,
            visible: primary
        )
        XCTAssertEqual(result, NSPoint(x: -160, y: -125))
    }
}

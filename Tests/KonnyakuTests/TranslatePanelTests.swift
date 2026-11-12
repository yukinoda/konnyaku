import AppKit
import XCTest
@testable import Konnyaku

@MainActor
final class TranslatePanelClampTests: XCTestCase {
    /// A 1440×875 visible area, like a laptop below its menu bar.
    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)

    private func clamp(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat = 400,
        height: CGFloat = 300
    ) -> NSRect {
        let frame = NSRect(x: x, y: y, width: width, height: height)
        return TranslatePanelController.clamp(frame, to: visible)
    }

    func testFrameInsideIsUnchanged() {
        let frame = NSRect(x: 100, y: 200, width: 400, height: 300)
        XCTAssertEqual(TranslatePanelController.clamp(frame, to: visible), frame)
    }

    func testFramePastAnEdgeMovesBackFlush() {
        XCTAssertEqual(clamp(x: 1300, y: 200).origin, NSPoint(x: 1040, y: 200))
        XCTAssertEqual(clamp(x: -50, y: 200).origin, NSPoint(x: 0, y: 200))
        XCTAssertEqual(clamp(x: 100, y: 800).origin, NSPoint(x: 100, y: 575))
        XCTAssertEqual(clamp(x: 100, y: -120).origin, NSPoint(x: 100, y: 0))
    }

    func testCornerMovesOnBothAxes() {
        XCTAssertEqual(clamp(x: 1400, y: -10).origin, NSPoint(x: 1040, y: 0))
    }

    func testSizeNeverChanges() {
        XCTAssertEqual(clamp(x: 5000, y: 5000).size, NSSize(width: 400, height: 300))
    }

    /// A display left of and below the primary one has negative coordinates.
    func testSecondaryDisplayWithNegativeCoordinates() {
        let secondary = NSRect(x: -1920, y: -1080, width: 1920, height: 1055)
        let frame = NSRect(x: -100, y: -1200, width: 400, height: 300)
        let result = TranslatePanelController.clamp(frame, to: secondary)
        XCTAssertEqual(result.origin, NSPoint(x: -400, y: -1080))
    }

    /// Too big to fit: the top-right corner stays on screen, so the title
    /// bar remains reachable, and the rest hangs off the left and bottom.
    func testOversizedFrameKeepsTopRightInside() {
        let result = clamp(x: 300, y: 300, width: 1600, height: 1000)
        XCTAssertEqual(result.maxX, visible.maxX)
        XCTAssertEqual(result.maxY, visible.maxY)
        XCTAssertEqual(result.origin, NSPoint(x: -160, y: -125))
    }
}

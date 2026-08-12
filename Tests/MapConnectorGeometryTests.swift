import Foundation
import Testing
@testable import Flowmap

/// `MapConnectorGeometry` is a pure function over plain CGPoint/CGSize
/// values, exactly like `MapLayout` — no `MapNode`, no `ModelContext`.
/// Ported verbatim from MindNodeClone's shipping code (`railX` / `branchStart`
/// / `branchEnd`, CanvasView.swift :783-857, and `roundedElbowPath`'s
/// single-L radius, CanvasView.swift :1791) — Task 63 pass 3.
@MainActor
struct MapConnectorGeometryTests {

    @Test("left-to-right connector starts at the external branch port")
    func horizontalStartUsesBranchPort() {
        let point = MapConnectorGeometry.horizontalStart(
            parentCenter: CGPoint(x: 100, y: 50),
            parentSize: CGSize(width: 80, height: 40),
            branchPortOffset: 29
        )
        #expect(abs(point.x - 169) < 0.0001)
        #expect(abs(point.y - 50) < 0.0001)
    }

    // MARK: - railX (root centre vs. child left edge + inset)

    @Test("railX at depth 0 is the node's own centre x, regardless of its width")
    func railXRootIsCentre() {
        let x = MapConnectorGeometry.railX(
            center: CGPoint(x: 100, y: 50),
            size: CGSize(width: 200, height: 40),
            depth: 0
        )
        #expect(abs(x - 100) < 0.0001)
    }

    @Test("railX below depth 0 is the node's own left edge + 14")
    func railXChildIsLeftEdgePlusInset() {
        let x = MapConnectorGeometry.railX(
            center: CGPoint(x: 100, y: 50),
            size: CGSize(width: 80, height: 40),
            depth: 1
        )
        // left edge = 100 - 40 = 60; + 14 = 74.
        #expect(abs(x - 74) < 0.0001)
    }

    // MARK: - depth-1 entry point (child's own rail, through its top edge)

    @Test("a depth-1 child is entered at (its own railX, its top edge + 8)")
    func depthOneEntryLandsOnChildsOwnRailThroughTop() {
        let childCenter = CGPoint(x: 300, y: 200)
        let childSize = CGSize(width: 80, height: 40)
        let point = MapConnectorGeometry.end(
            childCenter: childCenter,
            childSize: childSize,
            childDepth: 1,
            parentRailX: 999 // depth-1 entry ignores the parent's rail entirely
        )
        // railX(child) = 300 - 40 + 14 = 274; top + 8 = (200 - 20) + 8 = 188.
        #expect(abs(point.x - 274) < 0.0001)
        #expect(abs(point.y - 188) < 0.0001)
    }

    // MARK: - depth >= 2 entry point (side facing the parent's rail, mid-height)

    @Test("a depth >= 2 child sitting right of the parent's rail is entered from its LEFT side, -10 inside")
    func depthTwoEntryFromLeftWhenChildSitsRightOfParentRail() {
        let point = MapConnectorGeometry.end(
            childCenter: CGPoint(x: 100, y: 200),
            childSize: CGSize(width: 80, height: 40),
            childDepth: 2,
            parentRailX: 50
        )
        // child centre (100) >= parent rail (50) -> enters from the left:
        // x = 100 - (80/2 - 10) = 70, y = centre y unchanged.
        #expect(abs(point.x - 70) < 0.0001)
        #expect(abs(point.y - 200) < 0.0001)
    }

    @Test("a depth >= 2 child sitting left of the parent's rail is entered from its RIGHT side, -10 inside")
    func depthTwoEntryFromRightWhenChildSitsLeftOfParentRail() {
        let point = MapConnectorGeometry.end(
            childCenter: CGPoint(x: 20, y: 200),
            childSize: CGSize(width: 80, height: 40),
            childDepth: 2,
            parentRailX: 50
        )
        // child centre (20) < parent rail (50) -> enters from the right:
        // x = 20 + (80/2 - 10) = 50, y = centre y unchanged.
        #expect(abs(point.x - 50) < 0.0001)
        #expect(abs(point.y - 200) < 0.0001)
    }

    // MARK: - Single-L corner radius

    @Test("singleLRadius caps at 16pt, half the vertical run, and 90% of the horizontal run")
    func singleLRadiusTakesTheTightestBound() {
        // Vertical run is the tightest bound: min(16, 10, 90) = 10.
        #expect(abs(MapConnectorGeometry.singleLRadius(dx: 100, dy: 20) - 10) < 0.0001)
        // Horizontal run is the tightest bound: min(16, 50, 9) = 9.
        #expect(abs(MapConnectorGeometry.singleLRadius(dx: 10, dy: 100) - 9) < 0.0001)
        // The 16pt cap is the tightest bound.
        #expect(abs(MapConnectorGeometry.singleLRadius(dx: 50, dy: 50) - 16) < 0.0001)
    }

    // MARK: - endsHorizontally (which elbow shape a depth selects)

    @Test("endsHorizontally is true from depth 2 (side entry), false below it (top entry)")
    func endsHorizontallySelectsSideEntryFromDepthTwo() {
        #expect(MapConnectorGeometry.endsHorizontally(childDepth: 0) == false)
        #expect(MapConnectorGeometry.endsHorizontally(childDepth: 1) == false)
        #expect(MapConnectorGeometry.endsHorizontally(childDepth: 2) == true)
        #expect(MapConnectorGeometry.endsHorizontally(childDepth: 3) == true)
    }
}

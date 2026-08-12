import CoreGraphics

/// MindNode's connector-rail math for the top-down tree: pure functions over
/// plain `CGPoint`/`CGSize`, so they're unit-testable exactly like
/// `MapLayout`'s own pure helpers.
///
/// Every node owns a single vertical "rail". Its incoming connector lands on
/// the rail, and its own outgoing connectors leave from the same rail — one
/// straight line reads as running behind the node, with children hanging off
/// it. Ported verbatim from MindNodeClone's shipping code (never
/// reconstructed from memory): `railX` / `branchStart` / `branchEnd`
/// (`CanvasView.swift` :783-857, the vertical/non-horizontal branch) and the
/// single-L corner radius from `roundedElbowPath` (`CanvasView.swift` :1791).
/// Task 63 pass 3.
public enum MapConnectorGeometry {
    /// MindNode's connector stroke weight (Task 63 pass 3 restyle: measured
    /// ~4pt against the reference, up from the clone's thinner default).
    /// Read by `MapCanvasView.drawConnector` — the single stroke call for
    /// every connector, in both layout orientations.
    public static let lineWidth: CGFloat = 4

    /// How far inside a non-root node's own left edge its rail sits.
    /// Ported from `NodeChromeAnchor.railInset` (`CanvasView.swift` :787-790)
    /// — not to be confused with `MapLayout`'s `levelGap`/`indent` (16/30),
    /// which space the CHROME, not the connectors.
    public static let railInset: CGFloat = 14

    /// How far inside a parent's bottom edge a connector's start point sits.
    /// Ported from `branchStart` (`CanvasView.swift` :799-806).
    public static let startInset: CGFloat = 6

    /// How far inside a depth-1 child's top edge a connector's end point
    /// sits. Ported from `branchEnd` (`CanvasView.swift` :841-846).
    public static let topEntryInset: CGFloat = 8

    /// How far inside a depth >= 2 child's side edge a connector's end point
    /// sits. Ported from `branchEnd` (`CanvasView.swift` :832-840).
    public static let sideEntryInset: CGFloat = 10

    /// Where a left-to-right connector leaves the selected node's external
    /// branch port. Starting at the port, instead of the pill edge, prevents
    /// the coloured stroke from peeking around the circular disclosure control.
    public static func horizontalStart(
        parentCenter: CGPoint,
        parentSize: CGSize,
        branchPortOffset: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: parentCenter.x + parentSize.width / 2 + branchPortOffset,
            y: parentCenter.y
        )
    }

    /// A node's vertical rail x-coordinate: the root rails from its own
    /// centre; every other node rails `railInset` inside its own left edge.
    /// Ported from `railX` (`CanvasView.swift` :783-791).
    public static func railX(center: CGPoint, size: CGSize, depth: Int) -> CGFloat {
        depth == 0 ? center.x : center.x - size.width / 2 + railInset
    }

    /// Where a connector leaves its parent: the parent's own rail, through
    /// its bottom edge, `startInset` inside the body — the join stays
    /// invisible regardless of pill-sizing error. Ported from `branchStart`
    /// (`CanvasView.swift` :799-806).
    public static func start(parentCenter: CGPoint, parentSize: CGSize, parentDepth: Int) -> CGPoint {
        CGPoint(
            x: railX(center: parentCenter, size: parentSize, depth: parentDepth),
            y: parentCenter.y + parentSize.height / 2 - startInset
        )
    }

    /// Where a connector lands on its child. A depth-1 child is entered
    /// through its own TOP edge, on its own rail — collinear with the
    /// child's own outgoing spine. A depth >= 2 (stacked) child is entered
    /// through whichever SIDE faces the parent's rail. Ported from
    /// `branchEnd` (`CanvasView.swift` :830-846).
    public static func end(childCenter: CGPoint, childSize: CGSize, childDepth: Int, parentRailX: CGFloat) -> CGPoint {
        guard childDepth >= 2 else {
            return CGPoint(
                x: railX(center: childCenter, size: childSize, depth: childDepth),
                y: childCenter.y - childSize.height / 2 + topEntryInset
            )
        }
        let entersFromLeft = childCenter.x >= parentRailX
        return CGPoint(
            x: childCenter.x + (entersFromLeft ? -1 : 1) * (childSize.width / 2 - sideEntryInset),
            y: childCenter.y
        )
    }

    /// Whether the connector's final leg into the child runs horizontally (a
    /// depth >= 2 side entry, MindNode's single-L shape) rather than
    /// vertically (a depth-1 top entry, collinear with the child's own
    /// spine, MindNode's bus shape). Mirrors the `target.depth >= 2` branch
    /// in `branchEnd` (`CanvasView.swift` :832).
    public static func endsHorizontally(childDepth: Int) -> Bool {
        childDepth >= 2
    }

    /// MindNode's single-L corner radius: never sharper than 16pt, and never
    /// larger than half the vertical run or 90% of the horizontal run, so a
    /// tight gap still reads as one smooth curve instead of overshooting its
    /// own corner. Ported from `roundedElbowPath` (`CanvasView.swift` :1791).
    public static func singleLRadius(dx: CGFloat, dy: CGFloat) -> CGFloat {
        min(16, abs(dy) * 0.5, abs(dx) * 0.9)
    }
}

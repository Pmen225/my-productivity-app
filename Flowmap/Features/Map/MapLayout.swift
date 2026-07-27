import CoreGraphics
import Foundation

/// Pure automatic tree layout for the mind map canvas.
///
/// Deliberately ignorant of SwiftUI and of manual position overrides — it is a
/// plain function over the node graph, so it is unit-testable on its own and
/// fast enough for 200+ nodes (single depth-first pass, O(n)). Callers merge
/// `MapNode.manualPosition` on top of these results before drawing; the canvas
/// and the "fit map" / "centre selection" calculations all read from the same
/// merged positions so nodes and connectors never disagree about where a node is.
public enum MapLayout {
    /// Spacing and node-size constants shared with the views that draw nodes,
    /// so layout math and node bubbles can never drift out of sync.
    public struct Metrics: Sendable {
        public var levelSpacing: CGFloat
        public var siblingSpacing: CGFloat
        public var nodeWidth: CGFloat
        public var nodeHeight: CGFloat
        public var compactNodeHeight: CGFloat

        public init(
            levelSpacing: CGFloat = 220,
            siblingSpacing: CGFloat = 72,
            nodeWidth: CGFloat = 190,
            nodeHeight: CGFloat = 56,
            compactNodeHeight: CGFloat = 40
        ) {
            self.levelSpacing = levelSpacing
            self.siblingSpacing = siblingSpacing
            self.nodeWidth = nodeWidth
            self.nodeHeight = nodeHeight
            self.compactNodeHeight = compactNodeHeight
        }

        /// The one instance the canvas, the node bubbles and the layout maths
        /// all share, so a node is never sized differently than it is spaced.
        public static let shared = Metrics()
    }

    /// Positions every node reachable from `map`'s root, respecting collapsed
    /// branches exactly as `MapNode.visibleSubtreeNodes` does. The root sits at
    /// the origin; children fan out along +x by depth, siblings stack along +y.
    public static func positions(forMap map: MapDocument, metrics: Metrics = .shared) -> [UUID: CGPoint] {
        positions(root: map.rootNode, metrics: metrics)
    }

    /// The entry point unit tests use directly — it needs only a root `MapNode`
    /// built with a plain initialiser, no `MapDocument` or persistent store.
    public static func positions(root: MapNode?, metrics: Metrics = .shared) -> [UUID: CGPoint] {
        guard let root else { return [:] }
        var result: [UUID: CGPoint] = [:]
        var nextRow: CGFloat = 0
        assign(root, depth: 0, metrics: metrics, nextRow: &nextRow, result: &result)
        return result
    }

    /// Depth-first: a leaf claims the next free row in visiting order; an
    /// internal node's row is the average of its own children's rows. This is
    /// the standard tidy-tree shape, without the cost of a full
    /// Reingold–Tilford contour pass — more than enough for a personal map.
    @discardableResult
    private static func assign(
        _ node: MapNode,
        depth: Int,
        metrics: Metrics,
        nextRow: inout CGFloat,
        result: inout [UUID: CGPoint]
    ) -> CGFloat {
        let x = CGFloat(depth) * metrics.levelSpacing
        let visibleChildren = node.isCollapsed ? [] : node.orderedChildren

        guard !visibleChildren.isEmpty else {
            let row = nextRow
            nextRow += 1
            result[node.id] = CGPoint(x: x, y: row * metrics.siblingSpacing)
            return row
        }

        var childRows: [CGFloat] = []
        childRows.reserveCapacity(visibleChildren.count)
        for child in visibleChildren {
            childRows.append(
                assign(child, depth: depth + 1, metrics: metrics, nextRow: &nextRow, result: &result)
            )
        }
        let row = childRows.reduce(0, +) / CGFloat(childRows.count)
        result[node.id] = CGPoint(x: x, y: row * metrics.siblingSpacing)
        return row
    }

    /// Bounding box of a set of positions, expanded by half a node on each
    /// side — used by "fit map" so the outermost bubbles are not clipped.
    public static func bounds(of positions: [UUID: CGPoint], metrics: Metrics = .shared) -> CGRect {
        guard !positions.isEmpty else { return .zero }
        var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for point in positions.values {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let halfW = metrics.nodeWidth / 2
        let halfH = metrics.nodeHeight
        return CGRect(x: minX - halfW, y: minY - halfH, width: (maxX - minX) + halfW * 2, height: (maxY - minY) + halfH * 2)
    }
}

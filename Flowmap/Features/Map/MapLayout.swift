import CoreGraphics
import CoreText
import Foundation

/// Pure automatic tree layout for the mind map canvas.
///
/// Deliberately ignorant of SwiftUI and of manual position overrides — it is a
/// plain function over the node graph, so it is unit-testable on its own and
/// fast enough for a personal map (a handful of depth-first / recursive
/// passes, not a hot per-frame loop). Callers merge `MapNode.manualPosition`
/// on top of these results before drawing; the canvas and the "fit map" /
/// "centre selection" calculations all read from the same merged positions so
/// nodes and connectors never disagree about where a node is.
///
/// **The map layout rule**: a pill's width comes from its own text, never a
/// fixed number — `pillSize(for:)` measures the real glyph run. Columns are
/// spaced from those real widths (a leaf column clears its branch pill by at
/// least `Metrics.levelGap`; top-down siblings are spaced by their own real
/// half-widths), and the canvas grows to fit the result rather than
/// squeezing nodes to fit a canvas. Nodes never overlap.
public enum MapLayout {
    /// Spacing and node-size constants shared with the views that draw nodes,
    /// so layout math and node bubbles can never drift out of sync.
    public struct Metrics: Sendable {
        /// Floor a pill may shrink to however short its text — never below a
        /// comfortable minimum tap width.
        public var minPillWidth: CGFloat
        public var nodeHeight: CGFloat
        public var compactNodeHeight: CGFloat
        /// Horizontal padding inside a pill, each side, around the measured text.
        public var horizontalPadding: CGFloat
        /// Width reserved per inline accessory (collapse affordance, icon,
        /// completion mark) when one is present and the canvas isn't compact.
        public var accessoryAllowance: CGFloat
        /// Width reserved for the duration chip on a task leaf.
        public var chipAllowance: CGFloat
        /// The map layout rule's literal clearance: how far a leaf column
        /// must clear its branch pill (left-to-right depth spacing), and the
        /// floor for top-down row spacing. Reuses `FlowSpacing.l` (16pt).
        public var levelGap: CGFloat
        /// Clearance between sibling pills — their own real half-widths do
        /// the rest of the separating in top-down mode.
        public var siblingGap: CGFloat
        /// Vertical room reserved below a pill for its "+N" collapsed badge,
        /// so the badge never collides with the next row or column.
        public var badgeAllowance: CGFloat

        public init(
            minPillWidth: CGFloat = 96,
            nodeHeight: CGFloat = 40,
            compactNodeHeight: CGFloat = 32,
            horizontalPadding: CGFloat = FlowSpacing.l,
            accessoryAllowance: CGFloat = 20,
            chipAllowance: CGFloat = 44,
            levelGap: CGFloat = FlowSpacing.l,
            siblingGap: CGFloat = FlowSpacing.l,
            badgeAllowance: CGFloat = 20
        ) {
            self.minPillWidth = minPillWidth
            self.nodeHeight = nodeHeight
            self.compactNodeHeight = compactNodeHeight
            self.horizontalPadding = horizontalPadding
            self.accessoryAllowance = accessoryAllowance
            self.chipAllowance = chipAllowance
            self.levelGap = levelGap
            self.siblingGap = siblingGap
            self.badgeAllowance = badgeAllowance
        }

        /// The one instance the canvas, the node bubbles and the layout maths
        /// all share, so a node is never sized differently than it is spaced.
        public static let shared = Metrics()
    }

    // MARK: - Pill sizing

    /// The size one node's pill actually draws at — width measured from its
    /// own title, never a fixed column width. `MapNodeView` and the layout
    /// maths both call this, so a pill can never be sized differently than
    /// it is spaced.
    public static func pillSize(for node: MapNode, isCompact: Bool, metrics: Metrics = .shared) -> CGSize {
        let text = node.title.isEmpty ? "Untitled" : node.title
        // A leaf task and a branch pill both title themselves in
        // `FlowFont.caption.weight(.bold)` (a 12pt bold rounded face at the
        // default Dynamic Type size); root keeps its own fixed 13pt bold
        // title; a plain (non-task, childless) idea keeps the original
        // fixed-size title. Mirrors `MapNodeView.titleFont` exactly, or the
        // measured width and the rendered pill drift apart.
        let fontSize: CGFloat
        let bold: Bool
        if node.isRoot {
            fontSize = 13
            bold = true
        } else if node.isTask || node.hasChildren {
            fontSize = 12
            bold = true
        } else {
            fontSize = isCompact ? 11 : 13
            bold = false
        }
        var width = textWidth(text, fontSize: fontSize, bold: bold) + metrics.horizontalPadding * 2

        if !isCompact {
            if node.hasChildren { width += metrics.accessoryAllowance }
            if !node.iconName.isEmpty { width += metrics.accessoryAllowance }
            if node.isCompleted { width += metrics.accessoryAllowance }
            if node.isTask { width += metrics.chipAllowance }
        }

        let height = isCompact ? metrics.compactNodeHeight : metrics.nodeHeight
        return CGSize(width: max(ceil(width), metrics.minPillWidth), height: height)
    }

    /// Every visible node's pill size, keyed by id — the one measurement pass
    /// the canvas, the layout algorithm and the bounds calculation all share.
    public static func sizes(for nodes: [MapNode], isCompact: Bool, metrics: Metrics = .shared) -> [UUID: CGSize] {
        var result: [UUID: CGSize] = [:]
        result.reserveCapacity(nodes.count)
        for node in nodes {
            result[node.id] = pillSize(for: node, isCompact: isCompact, metrics: metrics)
        }
        return result
    }

    /// Measures a title at the exact size and weight it renders at, via
    /// CoreText rather than `UIFont`/`NSFont` — both frameworks are
    /// platform-specific extensions, while CoreText is one call that works
    /// identically on iOS and macOS. The system's rounded design is close
    /// enough in advance widths to the default one CoreText hands back that
    /// the difference never shows at pill scale.
    private static func textWidth(_ text: String, fontSize: CGFloat, bold: Bool) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let uiType: CTFontUIFontType = bold ? .emphasizedSystem : .system
        let font = CTFontCreateUIFontForLanguage(uiType, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        return ceil(CTLineGetBoundsWithOptions(line, .useOpticalBounds).width)
    }

    // MARK: - Positions

    /// Positions every node reachable from `map`'s root, respecting collapsed
    /// branches exactly as `MapNode.visibleSubtreeNodes` does.
    public static func positions(
        forMap map: MapDocument,
        orientation: MapLayoutOrientation,
        isCompact: Bool,
        metrics: Metrics = .shared
    ) -> [UUID: CGPoint] {
        positions(root: map.rootNode, orientation: orientation, isCompact: isCompact, metrics: metrics)
    }

    /// The entry point unit tests use directly — it needs only a root `MapNode`
    /// built with a plain initialiser, no `MapDocument` or persistent store.
    public static func positions(
        root: MapNode?,
        orientation: MapLayoutOrientation,
        isCompact: Bool,
        metrics: Metrics = .shared
    ) -> [UUID: CGPoint] {
        guard let root else { return [:] }
        let sizes = sizes(for: root.visibleSubtreeNodes, isCompact: isCompact, metrics: metrics)
        switch orientation {
        case .leftToRight:
            return positionsLeftToRight(root: root, sizes: sizes, metrics: metrics)
        case .topDown:
            return positionsTopDown(root: root, sizes: sizes, metrics: metrics)
        }
    }

    /// Children fan out along +x by depth, siblings stack along +y — the
    /// mock's "Left to right" orientation. Depth-axis (x) spacing between
    /// columns is the widest pill at the previous depth plus `levelGap`,
    /// which is the map layout rule's literal "leaf column clears its branch
    /// pill by at least 16px".
    private static func positionsLeftToRight(
        root: MapNode,
        sizes: [UUID: CGSize],
        metrics: Metrics
    ) -> [UUID: CGPoint] {
        var maxWidthByDepth: [Int: CGFloat] = [:]
        for node in root.visibleSubtreeNodes {
            let width = sizes[node.id]?.width ?? metrics.minPillWidth
            maxWidthByDepth[node.depth] = max(maxWidthByDepth[node.depth] ?? 0, width)
        }
        let maxDepth = maxWidthByDepth.keys.max() ?? 0
        var xByDepth: [Int: CGFloat] = [0: 0]
        if maxDepth > 0 {
            for depth in 1...maxDepth {
                let previousWidth = maxWidthByDepth[depth - 1] ?? metrics.minPillWidth
                xByDepth[depth] = (xByDepth[depth - 1] ?? 0) + previousWidth + metrics.levelGap
            }
        }

        let rowStep = (sizes.values.map(\.height).max() ?? metrics.nodeHeight) + metrics.siblingGap + metrics.badgeAllowance
        var result: [UUID: CGPoint] = [:]
        var nextRow: CGFloat = 0

        func assign(_ node: MapNode) -> CGFloat {
            let x = xByDepth[node.depth] ?? 0
            let visibleChildren = node.isCollapsed ? [] : node.orderedChildren
            guard !visibleChildren.isEmpty else {
                let row = nextRow
                nextRow += 1
                result[node.id] = CGPoint(x: x, y: row * rowStep)
                return row
            }
            let childRows = visibleChildren.map(assign)
            let row = childRows.reduce(0, +) / CGFloat(childRows.count)
            result[node.id] = CGPoint(x: x, y: row * rowStep)
            return row
        }
        assign(root)
        return result
    }

    /// Depth fans out along +y, siblings spread along +x — the mock's "Top
    /// down (org chart)" orientation. Cross-axis (x) spacing is each pill's
    /// own real half-width plus `siblingGap`, which is the map layout rule's
    /// "top-down columns spaced [by] real half-widths". A branch reserves the
    /// full width its subtree needs before any node is placed, so widening a
    /// leaf's text can never make it overlap a neighbouring branch.
    private static func positionsTopDown(
        root: MapNode,
        sizes: [UUID: CGSize],
        metrics: Metrics
    ) -> [UUID: CGPoint] {
        let rowStep = (sizes.values.map(\.height).max() ?? metrics.nodeHeight) + metrics.levelGap + metrics.badgeAllowance
        var result: [UUID: CGPoint] = [:]

        func subtreeWidth(_ node: MapNode) -> CGFloat {
            let own = sizes[node.id]?.width ?? metrics.minPillWidth
            let children = node.isCollapsed ? [] : node.orderedChildren
            guard !children.isEmpty else { return own }
            let childrenWidth = children.reduce(CGFloat(0)) { $0 + subtreeWidth($1) }
                + metrics.siblingGap * CGFloat(children.count - 1)
            return max(own, childrenWidth)
        }

        func assign(_ node: MapNode, leftEdge: CGFloat) {
            let y = CGFloat(node.depth) * rowStep
            let children = node.isCollapsed ? [] : node.orderedChildren
            guard !children.isEmpty else {
                let span = sizes[node.id]?.width ?? metrics.minPillWidth
                result[node.id] = CGPoint(x: leftEdge + span / 2, y: y)
                return
            }
            var cursor = leftEdge
            var childCentres: [CGFloat] = []
            for child in children {
                let childSpan = subtreeWidth(child)
                assign(child, leftEdge: cursor)
                childCentres.append(cursor + childSpan / 2)
                cursor += childSpan + metrics.siblingGap
            }
            let x = ((childCentres.first ?? leftEdge) + (childCentres.last ?? leftEdge)) / 2
            result[node.id] = CGPoint(x: x, y: y)
        }

        assign(root, leftEdge: 0)
        return result
    }

    // MARK: - Bounds

    /// Bounding box of a set of positioned, sized pills, expanded so the
    /// outermost bubbles (and any "+N" badge beneath them) are never clipped
    /// — used by "fit map" so the canvas grows to the tree rather than the
    /// tree squeezing to fit a fixed canvas.
    public static func bounds(
        of positions: [UUID: CGPoint],
        sizes: [UUID: CGSize] = [:],
        metrics: Metrics = .shared
    ) -> CGRect {
        guard !positions.isEmpty else { return .zero }
        var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for (id, point) in positions {
            let size = sizes[id] ?? CGSize(width: metrics.minPillWidth, height: metrics.nodeHeight)
            let halfW = size.width / 2
            let halfH = size.height / 2
            minX = min(minX, point.x - halfW)
            maxX = max(maxX, point.x + halfW)
            minY = min(minY, point.y - halfH)
            maxY = max(maxY, point.y + halfH + metrics.badgeAllowance)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

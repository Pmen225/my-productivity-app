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
        /// Fallback floor only — `pillSize` measures the real height from the
        /// title's font metrics plus vertical padding; a node whose measured
        /// height comes out shorter than this never renders below it.
        public var nodeHeight: CGFloat
        public var compactNodeHeight: CGFloat
        /// Horizontal padding inside a root pill, each side (EditableNodeLabel
        /// :203-217 — MindNode gives the anchor node visibly more breathing
        /// room than every other pill).
        public var rootHorizontalPadding: CGFloat
        /// Horizontal padding inside every other pill, each side, around the
        /// measured text.
        public var horizontalPadding: CGFloat
        /// Vertical padding inside a root pill, each side (EditableNodeLabel
        /// :203-217).
        public var rootVerticalPadding: CGFloat
        /// Vertical padding inside every other pill, each side.
        public var verticalPadding: CGFloat
        /// Touch target reserved for the external branch affordance. It never
        /// contributes to the label pill's width: MindNode keeps branch
        /// mechanics outside the text container so the hierarchy stays dense.
        public var accessoryAllowance: CGFloat
        /// Width occupied by a 21pt inline symbol plus its 8pt HStack gap.
        /// Keeping this separate from the 58pt collapse control prevents
        /// ordinary task icons from making every node needlessly wide.
        public var inlineAccessoryAllowance: CGFloat
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
            minPillWidth: CGFloat = 72,
            nodeHeight: CGFloat = 44,
            compactNodeHeight: CGFloat = 44,
            rootHorizontalPadding: CGFloat = FlowSpacing.l,
            horizontalPadding: CGFloat = FlowSpacing.m,
            rootVerticalPadding: CGFloat = FlowSpacing.m,
            verticalPadding: CGFloat = FlowSpacing.s,
            accessoryAllowance: CGFloat = 58,
            inlineAccessoryAllowance: CGFloat = 29,
            chipAllowance: CGFloat = 36,
            levelGap: CGFloat = FlowSpacing.l,
            siblingGap: CGFloat = FlowSpacing.l,
            badgeAllowance: CGFloat = 30
        ) {
            self.minPillWidth = minPillWidth
            self.nodeHeight = nodeHeight
            self.compactNodeHeight = compactNodeHeight
            self.rootHorizontalPadding = rootHorizontalPadding
            self.horizontalPadding = horizontalPadding
            self.rootVerticalPadding = rootVerticalPadding
            self.verticalPadding = verticalPadding
            self.accessoryAllowance = accessoryAllowance
            self.inlineAccessoryAllowance = inlineAccessoryAllowance
            self.chipAllowance = chipAllowance
            self.levelGap = levelGap
            self.siblingGap = siblingGap
            self.badgeAllowance = badgeAllowance
        }

        /// The one instance the canvas, the node bubbles and the layout maths
        /// all share, so a node is never sized differently than it is spaced.
        public static let shared = Metrics()

        /// The horizontal padding a pill of the given root-ness uses — the
        /// single read point `pillSize` and `MapNodeView`'s own padding both
        /// call, so the root/child split can never drift between measurement
        /// and drawing.
        public func horizontalPadding(forRoot isRoot: Bool) -> CGFloat {
            isRoot ? rootHorizontalPadding : horizontalPadding
        }

        /// The vertical padding a pill of the given root-ness uses — same
        /// invariant as `horizontalPadding(forRoot:)`.
        public func verticalPadding(forRoot isRoot: Bool) -> CGFloat {
            isRoot ? rootVerticalPadding : verticalPadding
        }
    }

    // MARK: - Pill sizing

    /// The MindNode-style continuous rounded-rect corner radius for a pill of
    /// the given height. Scales with height so a compact pill stays visibly
    /// rounded rather than square, and caps at MindNode's 16pt so a tall pill
    /// reads as a rounded rect rather than drifting back into a capsule.
    public static func nodeCornerRadius(forHeight height: CGFloat) -> CGFloat {
        min(height * 0.28, 16)
    }

    /// Lowest automatic fit scale that keeps the branch affordance at
    /// Apple's 44pt minimum touch size. Manual pinch zoom may go further;
    /// this floor is specifically for the view the app presents unaided.
    public static func minimumInteractiveFitZoom(metrics: Metrics = .shared) -> CGFloat {
        44 / metrics.accessoryAllowance
    }

    /// The size one node's pill actually draws at — width measured from its
    /// own title, never a fixed column width. `MapNodeView` and the layout
    /// maths both call this, so a pill can never be sized differently than
    /// it is spaced.
    public static func pillSize(for node: MapNode, isCompact: Bool, metrics: Metrics = .shared) -> CGSize {
        let text = node.title.isEmpty ? "Untitled" : node.title
        // Mirrors the shared `FlowFont` map tokens exactly. The former
        // 20–25pt override bypassed the design system and turned every label
        // into a card, which is why a small tree overflowed an iPhone.
        let fontSize = titleFontSize(isRoot: node.isRoot, isCompact: isCompact)
        let bold = true
        var width = textWidth(text, fontSize: fontSize, bold: bold)
            + metrics.horizontalPadding(forRoot: node.isRoot) * 2

        if !isCompact {
            if !node.iconName.isEmpty { width += metrics.inlineAccessoryAllowance }
            if node.isCompleted { width += metrics.inlineAccessoryAllowance }
            if node.isTask { width += metrics.chipAllowance }
        }

        // Height grows with the real font metrics and never drops below the
        // 44pt interactive floor.
        let measuredHeight = textHeight(fontSize: fontSize, bold: bold)
            + metrics.verticalPadding(forRoot: node.isRoot) * 2
        let heightFloor = isCompact ? metrics.compactNodeHeight : metrics.nodeHeight
        let height = max(measuredHeight, heightFloor)
        return CGSize(width: max(ceil(width), metrics.minPillWidth), height: ceil(height))
    }

    /// Exact fixed sizes owned by `FlowFont.mapRootTitle`,
    /// `mapNodeTitle`, and `mapNodeTitleCompact`.
    public static func titleFontSize(isRoot: Bool, isCompact: Bool) -> CGFloat {
        switch (isRoot, isCompact) {
        case (true, _): 13
        case (false, false): 13
        case (false, true): 11
        }
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

    /// The title's real line height at the given size and weight — ascent
    /// plus descent, the same font-metrics approach `textWidth` uses for
    /// width, so a pill's height grows with its title exactly as its width
    /// already does.
    private static func textHeight(fontSize: CGFloat, bold: Bool) -> CGFloat {
        let uiType: CTFontUIFontType = bold ? .emphasizedSystem : .system
        let font = CTFontCreateUIFontForLanguage(uiType, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        return ceil(CTFontGetAscent(font) + CTFontGetDescent(font))
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

    /// MindNode's real vertical tree shape: the root sits at the TOP, its
    /// direct children flow into at most two downward columns beneath it, and
    /// every generation below stacks under its own parent. A single wide row
    /// is desktop map behaviour; on an iPhone it clips both ends and defeats
    /// the purpose of choosing an org-chart view.
    private static func positionsTopDown(
        root: MapNode,
        sizes: [UUID: CGSize],
        metrics: Metrics
    ) -> [UUID: CGPoint] {
        let indent: CGFloat = 30
        let verticalGap: CGFloat = 16
        let firstChildGap: CGFloat = 26

        func size(_ node: MapNode) -> CGSize {
            sizes[node.id] ?? CGSize(width: metrics.minPillWidth, height: metrics.nodeHeight)
        }

        func visibleChildren(_ node: MapNode) -> [MapNode] {
            node.isCollapsed ? [] : node.orderedChildren
        }

        let rootToChildCentreY: CGFloat = 118

        // Total height of a node's own stacked subtree (Layout.swift
        // :668-681, `stackedSubtreeHeight`) — a stacked sibling's top must
        // clear everything the PREVIOUS sibling stacked below it, not just
        // that sibling's own pill.
        func stackedSubtreeHeight(_ node: MapNode) -> CGFloat {
            let own = size(node).height
            let children = visibleChildren(node)
            guard !children.isEmpty else { return own }
            let childHeights = children.map(stackedSubtreeHeight)
            return own + firstChildGap + childHeights.reduce(0, +)
                + CGFloat(max(children.count - 1, 0)) * verticalGap
        }

        // The horizontal room a depth >= 1 node's own stacked subtree needs
        // so a neighbouring branch's column can never collide with it — its
        // own width, or (if wider) the indent plus its widest stacked
        // descendant, since a stack only ever grows rightward from its
        // parent's own left edge.
        func stackedSubtreeWidth(_ node: MapNode) -> CGFloat {
            let own = size(node).width
            let children = visibleChildren(node)
            guard !children.isEmpty else { return own }
            let deepest = children.map(stackedSubtreeWidth).max() ?? 0
            return max(own, indent + deepest)
        }

        var result: [UUID: CGPoint] = [:]

        // Places `node` with its own LEFT edge at `leftEdge` and TOP edge at
        // `top`, then stacks its visible children straight down from it —
        // every generation below depth 1 lands here, whether it is a root's
        // direct child or a deeper grandchild.
        func stack(_ node: MapNode, leftEdge: CGFloat, top: CGFloat) {
            let nodeSize = size(node)
            result[node.id] = CGPoint(x: leftEdge + nodeSize.width / 2, y: top + nodeSize.height / 2)

            let children = visibleChildren(node)
            guard !children.isEmpty else { return }
            var currentTop = top + nodeSize.height + firstChildGap
            for child in children {
                stack(child, leftEdge: leftEdge + indent, top: currentTop)
                currentTop += stackedSubtreeHeight(child) + verticalGap
            }
        }

        let rootSize = size(root)
        let rootChildren = visibleChildren(root)
        guard !rootChildren.isEmpty else {
            result[root.id] = .zero
            return result
        }

        // Depth 1 uses a two-column masonry flow. Each branch stays intact in
        // one column; the next branch enters whichever column is currently
        // shorter, keeping the overall map narrow and vertically balanced.
        let rootCenterY = rootSize.height / 2
        let columnCount = min(2, rootChildren.count)
        var columns = Array(repeating: [MapNode](), count: columnCount)
        var columnHeights = Array(repeating: CGFloat.zero, count: columnCount)

        for child in rootChildren {
            let column = columnHeights.indices.min { columnHeights[$0] < columnHeights[$1] } ?? 0
            columns[column].append(child)
            columnHeights[column] += stackedSubtreeHeight(child) + verticalGap
        }

        let columnWidths = columns.map { column in
            column.map(stackedSubtreeWidth).max() ?? metrics.minPillWidth
        }
        let totalWidth = columnWidths.reduce(0, +)
            + CGFloat(max(columnCount - 1, 0)) * metrics.siblingGap

        var columnLeft: CGFloat = 0
        for columnIndex in columns.indices {
            var top = rootCenterY + rootToChildCentreY - size(columns[columnIndex][0]).height / 2
            for child in columns[columnIndex] {
                stack(child, leftEdge: columnLeft, top: top)
                top += stackedSubtreeHeight(child) + verticalGap
            }
            columnLeft += columnWidths[columnIndex] + metrics.siblingGap
        }

        result[root.id] = CGPoint(x: totalWidth / 2, y: rootSize.height / 2)
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

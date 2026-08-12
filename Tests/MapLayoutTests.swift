import Foundation
import Testing
@testable import Flowmap

/// `MapLayout` is a pure function over plain, never-inserted `MapNode`
/// models, exactly like `AutoMapBuilder` — these tests build nodes directly,
/// no `ModelContext`.
@MainActor
struct MapLayoutTests {

    // MARK: - Corner radius (Task 63 MindNode restyle, item 1)

    @Test("nodeCornerRadius scales with pill height (28% of height) below the 16pt MindNode cap")
    func nodeCornerRadiusScalesBelowCap() {
        #expect(abs(MapLayout.nodeCornerRadius(forHeight: 40) - 11.2) < 0.0001)
    }

    @Test("nodeCornerRadius caps at 16pt once height * 0.28 would exceed it")
    func nodeCornerRadiusCapsAtSixteen() {
        // 16 / 0.28 = 57.142857... — just below the cap boundary the formula
        // still applies, just past it the cap engages.
        #expect(abs(MapLayout.nodeCornerRadius(forHeight: 57.0) - 15.96) < 0.0001)
        #expect(abs(MapLayout.nodeCornerRadius(forHeight: 57.142857142857146) - 16) < 0.0001)
        #expect(MapLayout.nodeCornerRadius(forHeight: 200) == 16)
    }

    // MARK: - Root vs. non-root horizontal padding (Task 63 MindNode restyle, item 2)

    @Test("pillSize reads rootHorizontalPadding for the root and horizontalPadding for every other node")
    func pillSizeHonoursRootPaddingSplit() {
        // A title long enough that both nodes' widths sit well clear of
        // `minPillWidth`, so the padding delta below is never swallowed by
        // the floor clamp.
        let root = MapNode(title: "Plan out the whole quarter roadmap")
        let child = MapNode(title: "Plan out the whole quarter roadmap", parent: root)

        let base = MapLayout.Metrics.shared
        var widerRootPadding = base
        widerRootPadding.rootHorizontalPadding += 20
        var widerChildPadding = base
        widerChildPadding.horizontalPadding += 20

        let baseRootWidth = MapLayout.pillSize(for: root, isCompact: false, metrics: base).width
        let baseChildWidth = MapLayout.pillSize(for: child, isCompact: false, metrics: base).width

        // Growing the root-only padding grows the root pill by 2x the delta
        // and leaves the child pill untouched.
        let rootWidthUnderWiderRootPadding = MapLayout.pillSize(for: root, isCompact: false, metrics: widerRootPadding).width
        let childWidthUnderWiderRootPadding = MapLayout.pillSize(for: child, isCompact: false, metrics: widerRootPadding).width
        #expect(abs(rootWidthUnderWiderRootPadding - (baseRootWidth + 40)) < 0.0001)
        #expect(abs(childWidthUnderWiderRootPadding - baseChildWidth) < 0.0001)

        // Growing the non-root padding grows the child pill by 2x the delta
        // and leaves the root pill untouched.
        let childWidthUnderWiderChildPadding = MapLayout.pillSize(for: child, isCompact: false, metrics: widerChildPadding).width
        let rootWidthUnderWiderChildPadding = MapLayout.pillSize(for: root, isCompact: false, metrics: widerChildPadding).width
        #expect(abs(childWidthUnderWiderChildPadding - (baseChildWidth + 40)) < 0.0001)
        #expect(abs(rootWidthUnderWiderChildPadding - baseRootWidth) < 0.0001)
    }

    @Test("Metrics.shared keeps compact MindNode labels and an external 58pt branch target")
    func defaultMetricsMatchCompactMapSystem() {
        let metrics = MapLayout.Metrics.shared
        #expect(metrics.minPillWidth == 72)
        #expect(metrics.nodeHeight == 44)
        #expect(metrics.compactNodeHeight == 44)
        #expect(metrics.rootHorizontalPadding == 16)
        #expect(metrics.horizontalPadding == 12)
        #expect(metrics.rootVerticalPadding == 12)
        #expect(metrics.verticalPadding == 8)
        #expect(metrics.accessoryAllowance == 58)
        #expect(metrics.inlineAccessoryAllowance == 29)
    }

    // MARK: - Title font sizes (Task 63 MindNode restyle, item 3 — Layout.swift :148-174)

    @Test("titleFontSize matches the shared compact FlowFont map tokens")
    func titleFontSizeMatchesDesignSystem() {
        #expect(MapLayout.titleFontSize(isRoot: true, isCompact: false) == 13)
        #expect(MapLayout.titleFontSize(isRoot: false, isCompact: false) == 13)
        #expect(MapLayout.titleFontSize(isRoot: true, isCompact: true) == 13)
        #expect(MapLayout.titleFontSize(isRoot: false, isCompact: true) == 11)
    }

    @Test("a branch affordance never widens its label pill")
    func branchControlDoesNotWasteLabelWidth() {
        let leaf = MapNode(title: "Compact")
        let branch = MapNode(title: "Compact")
        _ = MapNode(title: "Child", parent: branch)

        let leafWidth = MapLayout.pillSize(for: leaf, isCompact: false).width
        let branchWidth = MapLayout.pillSize(for: branch, isCompact: false).width
        #expect(branchWidth == leafWidth)
    }

    // MARK: - Top-down tree layout (Task 63 pass 2 — MindNode vertical
    // orientation, ported from `MindMapLayoutEngine.layoutNodes`,
    // MindNodeClone/Sources/MindNodeClone/Layout.swift :377-513, :720-736)

    @Test("topDown: root sits top-centre above the two-column depth-1 flow")
    func topDownRootSitsTopCentre() throws {
        let root = MapNode(title: "Root", sortOrder: 0)
        let branchA = MapNode(title: "Branch A", sortOrder: 0, parent: root)
        let branchB = MapNode(title: "Branch B", sortOrder: 1, parent: root)
        let branchC = MapNode(title: "Branch C", sortOrder: 2, parent: root)

        let positions = MapLayout.positions(root: root, orientation: .topDown, isCompact: false)
        let rootPos = try #require(positions[root.id])
        let aPos = try #require(positions[branchA.id])
        let bPos = try #require(positions[branchB.id])
        let cPos = try #require(positions[branchC.id])

        #expect(rootPos.y < aPos.y)
        #expect(rootPos.y < bPos.y)
        #expect(rootPos.y < cPos.y)

        let positionsWithoutRoot = positions.filter { $0.key != root.id }
        let sizes = MapLayout.sizes(for: root.visibleSubtreeNodes, isCompact: false)
        let childBounds = MapLayout.bounds(of: positionsWithoutRoot, sizes: sizes)
        #expect(abs(rootPos.x - childBounds.midX) < 0.0001)
    }

    @Test("topDown: depth-1 children use at most two columns and continue downward")
    func topDownDepthOneChildrenFlowDownTwoColumns() throws {
        let root = MapNode(title: "Root", sortOrder: 0)
        let branchA = MapNode(title: "Branch A", sortOrder: 0, parent: root)
        let branchB = MapNode(title: "Branch B", sortOrder: 1, parent: root)
        let branchC = MapNode(title: "Branch C", sortOrder: 2, parent: root)

        let positions = MapLayout.positions(root: root, orientation: .topDown, isCompact: false)
        let aPos = try #require(positions[branchA.id])
        let bPos = try #require(positions[branchB.id])
        let cPos = try #require(positions[branchC.id])

        #expect(aPos.y == bPos.y)
        #expect(aPos.x < bPos.x)
        #expect(cPos.x == aPos.x)
        #expect(cPos.y > aPos.y)

        let metrics = MapLayout.Metrics.shared
        let aWidth = MapLayout.pillSize(for: branchA, isCompact: false, metrics: metrics).width
        let bWidth = MapLayout.pillSize(for: branchB, isCompact: false, metrics: metrics).width
        let edgeGap = (bPos.x - bWidth / 2) - (aPos.x + aWidth / 2)
        #expect(abs(edgeGap - metrics.siblingGap) < 0.0001)
    }

    @Test("automatic fit floor keeps the shared branch control at 44pt")
    func automaticFitFloorKeepsBranchControlHittable() {
        let metrics = MapLayout.Metrics.shared
        let zoom = MapLayout.minimumInteractiveFitZoom(metrics: metrics)

        #expect(abs(metrics.accessoryAllowance * zoom - 44) < 0.0001)
    }

    @Test("topDown: a stacked child's left edge sits its parent's left edge + indent (30), consecutive siblings clear by verticalGap (16)")
    func topDownStackedChildrenIndentAndClearVerticalGap() throws {
        let root = MapNode(title: "Root", sortOrder: 0)
        let branchA = MapNode(title: "Branch A", sortOrder: 0, parent: root)
        let childA1 = MapNode(title: "A1", sortOrder: 0, parent: branchA)
        let childA2 = MapNode(title: "A2", sortOrder: 1, parent: branchA)

        let positions = MapLayout.positions(root: root, orientation: .topDown, isCompact: false)
        let aPos = try #require(positions[branchA.id])
        let a1Pos = try #require(positions[childA1.id])
        let a2Pos = try #require(positions[childA2.id])

        let aWidth = MapLayout.pillSize(for: branchA, isCompact: false).width
        let a1Width = MapLayout.pillSize(for: childA1, isCompact: false).width
        let a1Height = MapLayout.pillSize(for: childA1, isCompact: false).height
        let a2Height = MapLayout.pillSize(for: childA2, isCompact: false).height

        let aLeftEdge = aPos.x - aWidth / 2
        let a1LeftEdge = a1Pos.x - a1Width / 2
        #expect(abs(a1LeftEdge - (aLeftEdge + 30)) < 0.0001)

        let a1Bottom = a1Pos.y + a1Height / 2
        let a2Top = a2Pos.y - a2Height / 2
        #expect(abs((a2Top - a1Bottom) - 16) < 0.0001)
    }

    @Test("topDown: the first stacked child's top sits at its parent's bottom + 26")
    func topDownFirstStackedChildTopIsParentBottomPlus26() throws {
        let root = MapNode(title: "Root", sortOrder: 0)
        let branchA = MapNode(title: "Branch A", sortOrder: 0, parent: root)
        let childA1 = MapNode(title: "A1", sortOrder: 0, parent: branchA)

        let positions = MapLayout.positions(root: root, orientation: .topDown, isCompact: false)
        let aPos = try #require(positions[branchA.id])
        let a1Pos = try #require(positions[childA1.id])

        let aHeight = MapLayout.pillSize(for: branchA, isCompact: false).height
        let a1Height = MapLayout.pillSize(for: childA1, isCompact: false).height

        let aBottom = aPos.y + aHeight / 2
        let a1Top = a1Pos.y - a1Height / 2
        #expect(abs((a1Top - aBottom) - 26) < 0.0001)
    }
}

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

    @Test("Metrics.shared's default padding matches EditableNodeLabel :203-217: root 30x20pt, others 26x17pt")
    func defaultMetricsMatchSpecValues() {
        let metrics = MapLayout.Metrics.shared
        #expect(metrics.rootHorizontalPadding == 30)
        #expect(metrics.horizontalPadding == 26)
        #expect(metrics.rootVerticalPadding == 20)
        #expect(metrics.verticalPadding == 17)
    }

    // MARK: - Title font sizes (Task 63 MindNode restyle, item 3 — Layout.swift :148-174)

    @Test("titleFontSize matches the clone's NodeTextSizeStyle: standard 25/20, compact 21/17")
    func titleFontSizeMatchesClone() {
        #expect(MapLayout.titleFontSize(isRoot: true, isCompact: false) == 25)
        #expect(MapLayout.titleFontSize(isRoot: false, isCompact: false) == 20)
        #expect(MapLayout.titleFontSize(isRoot: true, isCompact: true) == 21)
        #expect(MapLayout.titleFontSize(isRoot: false, isCompact: true) == 17)
    }

    // MARK: - Top-down tree layout (Task 63 pass 2 — MindNode vertical
    // orientation, ported from `MindMapLayoutEngine.layoutNodes`,
    // MindNodeClone/Sources/MindNodeClone/Layout.swift :377-513, :720-736)

    @Test("topDown: root sits top-centre — above every depth-1 child, x centred on the depth-1 row's span")
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

        let aWidth = MapLayout.pillSize(for: branchA, isCompact: false).width
        let cWidth = MapLayout.pillSize(for: branchC, isCompact: false).width
        let rowMinX = aPos.x - aWidth / 2
        let rowMaxX = cPos.x + cWidth / 2
        #expect(abs(rootPos.x - (rowMinX + rowMaxX) / 2) < 0.0001)
    }

    @Test("topDown: depth-1 children share one row beneath root, ordered left to right by index")
    func topDownDepthOneChildrenShareRowOrderedByIndex() throws {
        let root = MapNode(title: "Root", sortOrder: 0)
        let branchA = MapNode(title: "Branch A", sortOrder: 0, parent: root)
        let branchB = MapNode(title: "Branch B", sortOrder: 1, parent: root)
        let branchC = MapNode(title: "Branch C", sortOrder: 2, parent: root)

        let positions = MapLayout.positions(root: root, orientation: .topDown, isCompact: false)
        let aPos = try #require(positions[branchA.id])
        let bPos = try #require(positions[branchB.id])
        let cPos = try #require(positions[branchC.id])

        #expect(aPos.y == bPos.y)
        #expect(bPos.y == cPos.y)
        #expect(aPos.x < bPos.x)
        #expect(bPos.x < cPos.x)
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

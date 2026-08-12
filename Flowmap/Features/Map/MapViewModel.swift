import CoreGraphics
import Foundation
import Observation
import SwiftData
import SwiftUI

/// Map and Outline are two presentations of the same node graph. Which one is
/// on screen right now.
public enum MapViewMode: String, CaseIterable, Sendable {
    case map
    case outline

    public var displayName: String {
        switch self {
        case .map: "Map"
        case .outline: "Outline"
        }
    }

    public var symbolName: String {
        switch self {
        case .map: "point.topleft.down.to.point.bottomright.curvepath"
        case .outline: "list.bullet.indent"
        }
    }
}

/// Drives one open `MapDocument`: canvas viewport, selection, search, Focus
/// Branch and collapse/expand.
///
/// The Map canvas and the Outline list both read through this one object —
/// neither keeps its own copy of the graph, so a viewport or collapse change
/// made in either view is visible in the other the moment SwiftData saves it.
@Observable
@MainActor
public final class MapViewModel {
    public let map: MapDocument
    private let context: ModelContext

    // MARK: - Canvas viewport (persisted to the map on change)

    public var zoom: CGFloat
    public var panOffset: CGSize

    // MARK: - Selection & UI state

    public var selectedNodeID: UUID?
    public var viewMode: MapViewMode = .map
    public var isCompact: Bool = false
    public var focusBranchID: UUID?
    public var searchQuery: String = ""
    public var isSearchPresented: Bool = false
    /// The canvas's current size, published here so the toolbar's canvas menu
    /// can drive `fitToMap`/`centreOnSelection` without the canvas having to
    /// own a floating control of its own.
    public var viewportSize: CGSize = .zero

    public init(map: MapDocument, context: ModelContext) {
        self.map = map
        self.context = context
        self.zoom = CGFloat(map.canvasZoom == 0 ? 1 : map.canvasZoom)
        self.panOffset = CGSize(width: map.canvasOffsetX, height: map.canvasOffsetY)
    }

    /// Every mutation funnels its persistence through here rather than
    /// calling `context.save()` directly. Safe unconditionally: the
    /// transient, read-only auto map (Task 63) never inserts its `MapDocument`
    /// / `MapNode`s into `context` in the first place, so a save here has
    /// nothing of theirs to write.
    private func save() {
        try? context.save()
    }

    // MARK: - Derived reads

    public var visibleNodes: [MapNode] { map.visibleNodes }

    public var selectedNode: MapNode? {
        guard let selectedNodeID else { return nil }
        return nodeByID(selectedNodeID)
    }

    private var metrics: MapLayout.Metrics { .shared }

    public var layoutPositions: [UUID: CGPoint] {
        MapLayout.positions(forMap: map, orientation: map.layoutOrientation, isCompact: isCompact, metrics: metrics)
    }

    /// Every visible node's real pill size — the one measurement the canvas,
    /// the connectors and `fitToMap` all read, so a pill is never drawn a
    /// different size than it was laid out at.
    public var layoutSizes: [UUID: CGSize] {
        MapLayout.sizes(for: visibleNodes, isCompact: isCompact, metrics: metrics)
    }

    /// Which way the tree fans out. Persisted on the map itself so reopening
    /// it keeps the chosen shape; every node's position is recomputed from
    /// this the moment it changes.
    public var layoutOrientation: MapLayoutOrientation {
        get { map.layoutOrientation }
        set {
            guard newValue != map.layoutOrientation else { return }
            map.layoutOrientation = newValue
            save()
        }
    }

    /// The position both a node bubble and its connectors must read: automatic
    /// layout, overridden by a manual placement when the node has one.
    public func position(of node: MapNode, in positions: [UUID: CGPoint]) -> CGPoint {
        node.manualPosition ?? positions[node.id] ?? .zero
    }

    private func nodeByID(_ id: UUID) -> MapNode? {
        map.allNodes.first { $0.id == id }
    }

    // MARK: - Search

    /// Ids of every node whose title or body contains the query — the canvas
    /// and the outline both use this to highlight matches.
    public var searchMatchIDs: Set<UUID> {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return Set(
            map.allNodes
                .filter {
                    $0.title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                        || $0.body.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }
                .map(\.id)
        )
    }

    /// Selects the next match after the current selection, wrapping around.
    public func jumpToNextSearchMatch() {
        let matches = map.orderedNodes.filter { searchMatchIDs.contains($0.id) }
        guard !matches.isEmpty else { return }
        guard let currentID = selectedNodeID, let index = matches.firstIndex(where: { $0.id == currentID }) else {
            selectedNodeID = matches.first?.id
            return
        }
        selectedNodeID = matches[(index + 1) % matches.count].id
    }

    // MARK: - Focus Branch

    /// Every node id that stays at full opacity while Focus Branch is active:
    /// the focused node, its ancestors and its whole subtree. `nil` means
    /// Focus Branch is off and nothing should be dimmed.
    public var focusedNodeIDs: Set<UUID>? {
        guard let focusBranchID, let node = nodeByID(focusBranchID) else { return nil }
        var ids = Set(node.ancestorIDs)
        ids.insert(node.id)
        ids.formUnion(node.subtreeNodes.map(\.id))
        return ids
    }

    public func isDimmed(_ nodeID: UUID) -> Bool {
        guard let focused = focusedNodeIDs else { return false }
        return !focused.contains(nodeID)
    }

    public func toggleFocusBranch(on node: MapNode) {
        focusBranchID = (focusBranchID == node.id) ? nil : node.id
    }

    // MARK: - Collapse / expand

    public func toggleCollapse(_ node: MapNode) {
        node.isCollapsed.toggle()
        node.touch()
        save()
    }

    // MARK: - Canvas viewport

    public func persistCanvasState() {
        map.canvasZoom = Double(zoom)
        map.canvasOffsetX = Double(panOffset.width)
        map.canvasOffsetY = Double(panOffset.height)
        map.touch()
        save()
    }

    /// Zooms and pans so every visible node fits inside `viewportSize`.
    ///
    /// The canvas renders content SHIFTED so the tree's bounding box starts at
    /// `margin` (see `MapCanvasView.originShift`) — offsets must be computed in
    /// that rendered space, not raw layout space, or fitting frames nothing.
    public func fitToMap(viewportSize: CGSize, margin: CGFloat = 160) {
        // Manual placements override automatic layout in rendering, so the
        // fitted bounds must include them too or a hand-moved node sits
        // outside the frame.
        var fitPositions = layoutPositions
        for node in visibleNodes {
            if let manual = node.manualPosition { fitPositions[node.id] = manual }
        }
        let box = MapLayout.bounds(of: fitPositions, sizes: layoutSizes, metrics: metrics)
        guard box.width > 0, box.height > 0, viewportSize.width > 0, viewportSize.height > 0 else {
            zoom = 1
            panOffset = .zero
            persistCanvasState()
            return
        }
        let padding: CGFloat = 80
        let scaleX = (viewportSize.width - padding) / box.width
        let scaleY = (viewportSize.height - padding) / box.height
        // The fitted view must still be an interactive view, not a thumbnail.
        // Derive the floor from the shared branch-control measurement so the
        // rendered control lands at exactly Apple's 44pt minimum rather than
        // relying on a slightly-too-large magic zoom that clips phone maps.
        let minimumInteractiveZoom = MapLayout.minimumInteractiveFitZoom(metrics: metrics)
        zoom = min(max(min(scaleX, scaleY), minimumInteractiveZoom), 1.5)
        panOffset = CGSize(
            width: viewportSize.width / 2 - (margin + box.width / 2) * zoom,
            height: viewportSize.height / 2 - (margin + box.height / 2) * zoom
        )
        persistCanvasState()
    }

    /// Pans, at the current zoom, so the selected node sits at the viewport's centre.
    public func centreOnSelection(viewportSize: CGSize, margin: CGFloat = 160) {
        guard let node = selectedNode else { return }
        let box = MapLayout.bounds(of: layoutPositions, sizes: layoutSizes, metrics: metrics)
        let point = position(of: node, in: layoutPositions)
        panOffset = CGSize(
            width: viewportSize.width / 2 - (point.x - box.minX + margin) * zoom,
            height: viewportSize.height / 2 - (point.y - box.minY + margin) * zoom
        )
        persistCanvasState()
    }
}

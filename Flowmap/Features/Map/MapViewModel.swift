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
/// Branch, undo/redo and every node mutation.
///
/// The Map canvas and the Outline list both read and mutate through this one
/// object — neither keeps its own copy of the graph, so an edit made in
/// either view is visible in the other the moment SwiftData saves it.
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
    public var pendingDeletion: MapNode?
    public var searchQuery: String = ""

    public init(map: MapDocument, context: ModelContext) {
        self.map = map
        self.context = context
        self.zoom = CGFloat(map.canvasZoom == 0 ? 1 : map.canvasZoom)
        self.panOffset = CGSize(width: map.canvasOffsetX, height: map.canvasOffsetY)
    }

    // MARK: - Derived reads

    public var visibleNodes: [MapNode] { map.visibleNodes }

    public var selectedNode: MapNode? {
        guard let selectedNodeID else { return nil }
        return nodeByID(selectedNodeID)
    }

    public var layoutPositions: [UUID: CGPoint] {
        MapLayout.positions(forMap: map)
    }

    /// The position both a node bubble and its connectors must read: automatic
    /// layout, overridden by a manual placement when the node has one.
    public func position(of node: MapNode, in positions: [UUID: CGPoint]) -> CGPoint {
        node.manualPosition ?? positions[node.id] ?? .zero
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

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

    // MARK: - Node creation

    /// Creates the map's first idea. Only meaningful while the map has none —
    /// `MapDocument` keeps exactly one root once it exists.
    @discardableResult
    public static func createRootTopic(in map: MapDocument, title: String, context: ModelContext) -> MapNode {
        let node = MapNode(title: title, colourToken: map.themeToken, map: map)
        context.insert(node)
        try? context.save()
        return node
    }

    @discardableResult
    public func addRootTopic(title: String = "Main idea") -> MapNode {
        let node = Self.createRootTopic(in: map, title: title, context: context)
        selectedNodeID = node.id
        let snapshot = NodeSnapshot(node: node)
        record(
            undo: { [weak self] in self?.rawDelete(nodeID: snapshot.id) },
            redo: { [weak self] in self?.rawRestore(snapshot, parentID: nil) }
        )
        return node
    }

    @discardableResult
    public func addChild(to parent: MapNode, title: String = "New idea") -> MapNode {
        let child = MapNode(
            title: title,
            colourToken: parent.colourToken,
            sortOrder: (parent.children ?? []).count,
            map: map,
            parent: parent
        )
        context.insert(child)
        parent.isCollapsed = false
        selectedNodeID = child.id
        try? context.save()

        let snapshot = NodeSnapshot(node: child)
        let parentID = parent.id
        record(
            undo: { [weak self] in self?.rawDelete(nodeID: snapshot.id) },
            redo: { [weak self] in self?.rawRestore(snapshot, parentID: parentID) }
        )
        return child
    }

    /// Adds a sibling positioned right after `node`. A root has no siblings to
    /// join, so a sibling request on the root becomes a child instead.
    @discardableResult
    public func addSibling(to node: MapNode, title: String = "New idea") -> MapNode {
        guard let parent = node.parent else { return addChild(to: node, title: title) }
        let sibling = MapNode(
            title: title,
            colourToken: parent.colourToken,
            sortOrder: node.sortOrder + 1,
            map: map,
            parent: parent
        )
        for other in parent.orderedChildren where other.sortOrder > node.sortOrder {
            other.sortOrder += 1
        }
        context.insert(sibling)
        selectedNodeID = sibling.id
        try? context.save()

        let snapshot = NodeSnapshot(node: sibling)
        let parentID = parent.id
        record(
            undo: { [weak self] in self?.rawDelete(nodeID: snapshot.id) },
            redo: { [weak self] in self?.rawRestore(snapshot, parentID: parentID) }
        )
        return sibling
    }

    // MARK: - Rename

    public func rename(_ node: MapNode, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != node.title else { return }
        let nodeID = node.id
        let previous = node.title
        rawSetTitle(nodeID: nodeID, title: trimmed)
        record(
            undo: { [weak self] in self?.rawSetTitle(nodeID: nodeID, title: previous) },
            redo: { [weak self] in self?.rawSetTitle(nodeID: nodeID, title: trimmed) }
        )
    }

    private func rawSetTitle(nodeID: UUID, title: String) {
        guard let node = nodeByID(nodeID) else { return }
        node.title = title
        node.touch()
        try? context.save()
    }

    // MARK: - Collapse / expand

    /// Not undo-tracked: a disclosure state is view chrome, not content — on a
    /// par with scroll position, not with an edit.
    public func toggleCollapse(_ node: MapNode) {
        node.isCollapsed.toggle()
        node.touch()
        try? context.save()
    }

    // MARK: - Manual position (free drag on the canvas)

    public func setManualPosition(_ node: MapNode, to point: CGPoint?) {
        node.setManualPosition(point)
        try? context.save()
    }

    // MARK: - Reparent / reorder (drag and drop in the Outline)

    /// Moves `node` to become a sibling positioned immediately before
    /// `target`, adopting `target`'s parent. Refuses to drop a node onto its
    /// own descendant, which would otherwise create a cycle.
    public func moveNode(_ node: MapNode, beforeSibling target: MapNode) {
        guard node.id != target.id, !node.subtreeNodes.contains(where: { $0.id == target.id }) else { return }
        let nodeID = node.id
        let targetID = target.id
        let previousParentID = node.parent?.id
        let previousSortOrder = node.sortOrder

        rawMove(nodeID: nodeID, beforeSiblingID: targetID)

        record(
            undo: { [weak self] in
                self?.rawRestoreParent(nodeID: nodeID, parentID: previousParentID, sortOrder: previousSortOrder)
            },
            redo: { [weak self] in self?.rawMove(nodeID: nodeID, beforeSiblingID: targetID) }
        )
    }

    private func rawMove(nodeID: UUID, beforeSiblingID: UUID) {
        guard let node = nodeByID(nodeID), let target = nodeByID(beforeSiblingID) else { return }
        let newParent = target.parent
        node.parent = newParent
        var siblings = (newParent?.children ?? map.allNodes.filter { $0.parent == nil })
            .filter { $0.id != node.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        if let targetIndex = siblings.firstIndex(where: { $0.id == target.id }) {
            siblings.insert(node, at: targetIndex)
        } else {
            siblings.append(node)
        }
        for (index, sibling) in siblings.enumerated() { sibling.sortOrder = index }
        node.touch()
        try? context.save()
    }

    private func rawRestoreParent(nodeID: UUID, parentID: UUID?, sortOrder: Int) {
        guard let node = nodeByID(nodeID) else { return }
        node.parent = parentID.flatMap(nodeByID)
        node.sortOrder = sortOrder
        node.touch()
        try? context.save()
    }

    // MARK: - Delete (with confirmation)

    public func requestDelete(_ node: MapNode) {
        pendingDeletion = node
    }

    public func cancelDelete() {
        pendingDeletion = nil
    }

    public func confirmDelete() {
        guard let node = pendingDeletion else { return }
        let snapshot = NodeSnapshot(node: node)
        let parentID = node.parent?.id
        rawDelete(nodeID: node.id)
        pendingDeletion = nil
        record(
            undo: { [weak self] in self?.rawRestore(snapshot, parentID: parentID) },
            redo: { [weak self] in self?.rawDelete(nodeID: snapshot.id) }
        )
    }

    /// Deletes a node and its subtree (children cascade via the model's
    /// relationship). Also clears selection and Focus Branch if either
    /// pointed inside the deleted subtree, so the UI never references a node
    /// that no longer exists.
    private func rawDelete(nodeID: UUID) {
        guard let node = nodeByID(nodeID) else { return }
        if selectedNodeID == nodeID || node.subtreeNodes.contains(where: { $0.id == selectedNodeID }) {
            selectedNodeID = node.parent?.id
        }
        if let focusBranchID, focusBranchID == nodeID || node.subtreeNodes.contains(where: { $0.id == focusBranchID }) {
            self.focusBranchID = nil
        }
        context.delete(node)
        try? context.save()
    }

    /// Rebuilds a node (and, for a delete undo, its whole subtree) from a
    /// snapshot. A deleted SwiftData object cannot safely be resurrected in
    /// place, so undoing a delete or redoing a create always creates fresh
    /// model instances rather than reusing the original one — `NodeSnapshot`
    /// carries the original id across so selection and further undo entries
    /// keep working by id.
    @discardableResult
    private func rawRestore(_ snapshot: NodeSnapshot, parentID: UUID?) -> MapNode {
        rebuild(snapshot, parent: parentID.flatMap(nodeByID))
    }

    @discardableResult
    private func rebuild(_ snapshot: NodeSnapshot, parent: MapNode?) -> MapNode {
        let node = MapNode(
            title: snapshot.title,
            body: snapshot.body,
            iconName: snapshot.iconName,
            colourToken: snapshot.colourToken,
            sortOrder: snapshot.sortOrder,
            map: map,
            parent: parent
        )
        node.id = snapshot.id
        node.isCollapsed = snapshot.isCollapsed
        node.isTask = snapshot.isTask
        node.priorityRaw = snapshot.priorityRaw
        node.estimatedMinutes = snapshot.estimatedMinutes
        node.manualPositionX = snapshot.manualPositionX
        node.manualPositionY = snapshot.manualPositionY
        context.insert(node)
        for childSnapshot in snapshot.children {
            rebuild(childSnapshot, parent: node)
        }
        try? context.save()
        return node
    }

    // MARK: - Undo / redo stack

    private struct UndoEntry {
        let undo: () -> Void
        let redo: () -> Void
    }

    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []

    /// Every public mutation calls this exactly once, with closures built from
    /// the private `raw...` primitives. Those primitives must never call
    /// `record` themselves — undo and redo would otherwise push extra entries
    /// every time they run, corrupting the stack.
    private func record(undo: @escaping () -> Void, redo: @escaping () -> Void) {
        undoStack.append(UndoEntry(undo: undo, redo: redo))
        redoStack.removeAll()
    }

    public func undo() {
        guard let entry = undoStack.popLast() else { return }
        entry.undo()
        redoStack.append(entry)
    }

    public func redo() {
        guard let entry = redoStack.popLast() else { return }
        entry.redo()
        undoStack.append(entry)
    }

    // MARK: - Canvas viewport

    public func persistCanvasState() {
        map.canvasZoom = Double(zoom)
        map.canvasOffsetX = Double(panOffset.width)
        map.canvasOffsetY = Double(panOffset.height)
        map.touch()
        try? context.save()
    }

    /// Zooms and pans so every visible node fits inside `viewportSize`.
    public func fitToMap(viewportSize: CGSize) {
        let box = MapLayout.bounds(of: layoutPositions)
        guard box.width > 0, box.height > 0, viewportSize.width > 0, viewportSize.height > 0 else {
            zoom = 1
            panOffset = .zero
            persistCanvasState()
            return
        }
        let padding: CGFloat = 80
        let scaleX = (viewportSize.width - padding) / box.width
        let scaleY = (viewportSize.height - padding) / box.height
        zoom = min(max(min(scaleX, scaleY), 0.25), 1.5)
        let centre = CGPoint(x: box.midX, y: box.midY)
        panOffset = CGSize(
            width: viewportSize.width / 2 - centre.x * zoom,
            height: viewportSize.height / 2 - centre.y * zoom
        )
        persistCanvasState()
    }

    /// Pans, at the current zoom, so the selected node sits at the viewport's centre.
    public func centreOnSelection(viewportSize: CGSize) {
        guard let node = selectedNode else { return }
        let point = position(of: node, in: layoutPositions)
        panOffset = CGSize(
            width: viewportSize.width / 2 - point.x * zoom,
            height: viewportSize.height / 2 - point.y * zoom
        )
        persistCanvasState()
    }
}

// MARK: - Node snapshot

/// A plain-value copy of a node and its subtree, used to survive the moment
/// of deletion so undo can rebuild what was there — a deleted `@Model`
/// instance cannot be safely reused, so undo always rebuilds fresh objects
/// and restores the original id onto them.
///
/// Deliberately does not carry `linkedTask` / `linkedNote`: those are separate
/// records with their own lifetime, and re-linking them automatically on an
/// undone delete would risk resurrecting a stale link silently.
private struct NodeSnapshot {
    let id: UUID
    let title: String
    let body: String
    let iconName: String
    let colourToken: String
    let sortOrder: Int
    let isCollapsed: Bool
    let isTask: Bool
    let priorityRaw: String
    let estimatedMinutes: Int
    let manualPositionX: Double?
    let manualPositionY: Double?
    let children: [NodeSnapshot]

    init(node: MapNode) {
        id = node.id
        title = node.title
        body = node.body
        iconName = node.iconName
        colourToken = node.colourToken
        sortOrder = node.sortOrder
        isCollapsed = node.isCollapsed
        isTask = node.isTask
        priorityRaw = node.priorityRaw
        estimatedMinutes = node.estimatedMinutes
        manualPositionX = node.manualPositionX
        manualPositionY = node.manualPositionY
        children = node.orderedChildren.map(NodeSnapshot.init)
    }
}

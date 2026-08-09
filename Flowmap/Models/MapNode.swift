import CoreGraphics
import Foundation
import SwiftData

/// One idea on the canvas. Map view and Outline view both render this same
/// graph, so an edit in either is an edit to the same object.
@Model
public final class MapNode {
    public var id: UUID = UUID()
    public var title: String = ""
    public var body: String = ""
    public var iconName: String = ""
    public var colourToken: String = ColourToken.violet.rawValue
    public var sortOrder: Int = 0
    public var isCollapsed: Bool = false
    public var isTask: Bool = false
    public var priorityRaw: String = TaskPriority.none.rawValue
    public var estimatedMinutes: Int = 30
    /// Manual placement overrides automatic layout when both are set.
    public var manualPositionX: Double?
    public var manualPositionY: Double?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var map: MapDocument?
    public var parent: MapNode?

    @Relationship(deleteRule: .cascade, inverse: \MapNode.parent)
    public var children: [MapNode]?

    /// At most one task per node. Converting an already-linked node reuses this.
    public var linkedTask: FlowTask?

    /// The auto-map's link to the task a node displays. `AutoMapBuilder`'s
    /// tree is never inserted, and assigning `linkedTask` there writes the
    /// INVERSE (`FlowTask.mapNode`) onto the persisted task — SwiftData
    /// asserted and crashed on every reseeded launch that opened the Map.
    /// @Transient keeps the reference entirely outside the store; read
    /// through `displayTask`, which resolves whichever link a node carries.
    @Transient public var transientTask: FlowTask? = nil

    public var displayTask: FlowTask? { transientTask ?? linkedTask }

    @Relationship(deleteRule: .nullify, inverse: \Note.mapNode)
    public var linkedNote: Note?

    public var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue; touch() }
    }

    public var colour: ColourToken { ColourToken.token(colourToken) }

    public init(
        title: String,
        body: String = "",
        iconName: String = "",
        colourToken: String = ColourToken.violet.rawValue,
        sortOrder: Int = 0,
        map: MapDocument? = nil,
        parent: MapNode? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.body = body
        self.iconName = iconName
        self.colourToken = colourToken
        self.sortOrder = sortOrder
        self.map = map
        self.parent = parent
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func touch(_ date: Date = Date()) { updatedAt = date }

    // MARK: - Tree

    public var orderedChildren: [MapNode] {
        (children ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    public var isRoot: Bool { parent == nil }

    public var hasChildren: Bool { !(children ?? []).isEmpty }

    public var depth: Int {
        var count = 0
        var current = parent
        while let node = current {
            count += 1
            current = node.parent
            if count > 64 { break } // cycle guard
        }
        return count
    }

    /// This node's position among the root's direct children — the depth-1
    /// ancestor's `sortOrder`. `MapPalette.branchColour` keys a whole branch
    /// subtree's colour off this so it stays flat top to bottom (Task 63
    /// MindNode restyle). Meaningless for the root itself, which never reads it.
    public var rootChildIndex: Int {
        var current = self
        var hops = 0
        while let ancestor = current.parent, !ancestor.isRoot {
            current = ancestor
            hops += 1
            if hops > 64 { break } // cycle guard, matches `depth`/`ancestorIDs`
        }
        return current.sortOrder
    }

    /// Self and all descendants, depth-first in display order.
    public var subtreeNodes: [MapNode] {
        collectSubtree(respectingCollapse: false, seen: [])
    }

    /// Nodes drawn when ancestors' collapse state is respected.
    public var visibleSubtreeNodes: [MapNode] {
        collectSubtree(respectingCollapse: true, seen: [])
    }

    /// Walks the subtree while refusing to visit a node twice.
    ///
    /// A parent chain is meant to be acyclic, but an imported backup can carry a
    /// corrupted `parentID`. Without this guard the first read of the tree after
    /// such an import would recurse until the app died.
    private func collectSubtree(respectingCollapse: Bool, seen: Set<UUID>) -> [MapNode] {
        guard !seen.contains(id) else { return [] }
        var visited = seen
        visited.insert(id)

        var result: [MapNode] = [self]
        if respectingCollapse, isCollapsed { return result }
        for child in orderedChildren {
            result.append(
                contentsOf: child.collectSubtree(respectingCollapse: respectingCollapse, seen: visited)
            )
            visited.formUnion(result.map(\.id))
        }
        return result
    }

    public var ancestorIDs: [UUID] {
        var result: [UUID] = []
        var current = parent
        while let node = current {
            result.append(node.id)
            current = node.parent
            if result.count > 64 { break }
        }
        return result
    }

    public var manualPosition: CGPoint? {
        guard let manualPositionX, let manualPositionY else { return nil }
        return CGPoint(x: manualPositionX, y: manualPositionY)
    }

    public func setManualPosition(_ point: CGPoint?) {
        manualPositionX = point.map { Double($0.x) }
        manualPositionY = point.map { Double($0.y) }
        touch()
    }

    /// Completion mirrors the linked task so the canvas reflects real progress.
    public var isCompleted: Bool { displayTask?.status == .completed }
}

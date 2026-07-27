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

    /// Self and all descendants, depth-first in display order.
    public var subtreeNodes: [MapNode] {
        var result: [MapNode] = [self]
        for child in orderedChildren {
            result.append(contentsOf: child.subtreeNodes)
        }
        return result
    }

    /// Nodes drawn when ancestors' collapse state is respected.
    public var visibleSubtreeNodes: [MapNode] {
        var result: [MapNode] = [self]
        guard !isCollapsed else { return result }
        for child in orderedChildren {
            result.append(contentsOf: child.visibleSubtreeNodes)
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
    public var isCompleted: Bool { linkedTask?.status == .completed }
}

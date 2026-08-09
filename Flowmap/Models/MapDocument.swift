import Foundation
import SwiftData

/// The two tree shapes the map canvas can lay itself out in. Persisted per
/// map — string raw value for the same reason every other enum here is: a
/// `@Model` primitive that CloudKit and `#Predicate` can both use directly.
public enum MapLayoutOrientation: String, CaseIterable, Sendable {
    case leftToRight
    case topDown

    public var displayName: String {
        switch self {
        case .leftToRight: "Left to right"
        case .topDown: "Top down (org chart)"
        }
    }

    public var symbolName: String {
        switch self {
        case .leftToRight: "arrow.right"
        case .topDown: "arrow.down"
        }
    }
}

/// A mind map. Holds its own canvas viewport so reopening a map returns the
/// user to where they were looking.
@Model
public final class MapDocument {
    public var id: UUID = UUID()
    public var title: String = ""
    public var summary: String = ""
    public var themeToken: String = ColourToken.violet.rawValue
    public var canvasOffsetX: Double = 0
    public var canvasOffsetY: Double = 0
    public var canvasZoom: Double = 1
    public var layoutOrientationRaw: String = MapLayoutOrientation.topDown.rawValue
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var workspace: Workspace?
    public var project: Project?

    @Relationship(deleteRule: .cascade, inverse: \MapNode.map)
    public var nodes: [MapNode]?

    public var theme: ColourToken { ColourToken.token(themeToken) }

    /// Which way the canvas fans the tree out. Chosen from the map's "⋯"
    /// layout menu; every node's position is recomputed from this on change.
    public var layoutOrientation: MapLayoutOrientation {
        get { MapLayoutOrientation(rawValue: layoutOrientationRaw) ?? .topDown }
        set { layoutOrientationRaw = newValue.rawValue; touch() }
    }

    public init(
        title: String,
        summary: String = "",
        themeToken: String = ColourToken.violet.rawValue,
        workspace: Workspace? = nil,
        project: Project? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.themeToken = themeToken
        self.workspace = workspace
        self.project = project
        self.canvasZoom = 1
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func touch(_ date: Date = Date()) { updatedAt = date }

    /// The single root topic. Maps are created with one and keep exactly one.
    public var rootNode: MapNode? {
        (nodes ?? []).first { $0.parent == nil }
    }

    public var allNodes: [MapNode] { nodes ?? [] }

    public var nodeCount: Int { (nodes ?? []).count }

    /// Depth-first display order starting at the root.
    public var orderedNodes: [MapNode] {
        rootNode?.subtreeNodes ?? []
    }

    /// Respects collapsed branches — what the canvas and outline actually draw.
    public var visibleNodes: [MapNode] {
        rootNode?.visibleSubtreeNodes ?? []
    }
}

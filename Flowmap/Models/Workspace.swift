import Foundation
import SwiftData

/// A top-level personal space such as Personal, Work, Study or Ideas.
///
/// CloudKit rules observed by every model in this folder: no unique attributes,
/// every stored attribute carries a default, and every relationship is optional.
@Model
public final class Workspace {
    public var id: UUID = UUID()
    public var name: String = ""
    public var iconName: String = "square.grid.2x2"
    public var colourToken: String = ColourToken.violet.rawValue
    public var sortOrder: Int = 0
    public var isArchived: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \TaskList.workspace)
    public var lists: [TaskList]?

    @Relationship(deleteRule: .cascade, inverse: \Project.workspace)
    public var projects: [Project]?

    @Relationship(deleteRule: .nullify, inverse: \FlowTask.workspace)
    public var tasks: [FlowTask]?

    @Relationship(deleteRule: .cascade, inverse: \MapDocument.workspace)
    public var maps: [MapDocument]?

    @Relationship(deleteRule: .cascade, inverse: \Note.workspace)
    public var notes: [Note]?

    public init(
        name: String,
        iconName: String = "square.grid.2x2",
        colourToken: String = ColourToken.violet.rawValue,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.colourToken = colourToken
        self.sortOrder = sortOrder
        self.isArchived = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func touch(_ date: Date = Date()) { updatedAt = date }
}

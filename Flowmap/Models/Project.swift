import Foundation
import SwiftData

/// A body of work with its own tasks, map and notes.
@Model
public final class Project {
    public var id: UUID = UUID()
    public var title: String = ""
    public var summary: String = ""
    public var statusRaw: String = ProjectStatus.active.rawValue
    public var priorityRaw: String = TaskPriority.none.rawValue
    public var startDate: Date?
    public var dueDate: Date?
    public var colourToken: String = ColourToken.teal.rawValue
    public var iconName: String = "folder"
    public var sortOrder: Int = 0
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var workspace: Workspace?
    /// The goal this project feeds, if any. The inverse lives on `Initiative`.
    public var initiative: Initiative?

    @Relationship(deleteRule: .nullify, inverse: \FlowTask.project)
    public var tasks: [FlowTask]?

    @Relationship(deleteRule: .nullify, inverse: \MapDocument.project)
    public var maps: [MapDocument]?

    @Relationship(deleteRule: .nullify, inverse: \Note.project)
    public var notes: [Note]?

    public var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue; touch() }
    }

    public var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue; touch() }
    }

    public var colour: ColourToken { ColourToken.token(colourToken) }

    public init(
        title: String,
        summary: String = "",
        status: ProjectStatus = .active,
        priority: TaskPriority = .none,
        colourToken: String = ColourToken.teal.rawValue,
        iconName: String = "folder",
        sortOrder: Int = 0,
        workspace: Workspace? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.colourToken = colourToken
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.workspace = workspace
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func touch(_ date: Date = Date()) { updatedAt = date }

    // MARK: - Progress

    /// Tasks that count toward progress. Cancelled work is excluded so it cannot
    /// distort the ratio; paused work still counts as outstanding.
    public var actionableTasks: [FlowTask] {
        (tasks ?? []).filter { $0.status.isActionable }
    }

    public var completedTaskCount: Int {
        actionableTasks.count { $0.status == .completed }
    }

    /// The single source of truth for project progress — always derived, never
    /// stored, so a second value can never contradict it.
    public var progress: Double {
        let actionable = actionableTasks
        guard !actionable.isEmpty else { return 0 }
        return Double(actionable.count { $0.status == .completed }) / Double(actionable.count)
    }

    public var progressPercentText: String {
        "\(Int((progress * 100).rounded()))%"
    }
}

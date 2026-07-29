import Foundation
import SwiftData

/// The goal at the root of a map.
///
/// Projects hang off an initiative, and the tasks under those projects are what
/// move it: finish them all and the initiative is complete. It owns no work of
/// its own — asking it for progress always walks down to the tasks, so there is
/// never a stored number that can disagree with them.
@Model
public final class Initiative {
    public var id: UUID = UUID()
    public var title: String = ""
    public var summary: String = ""
    public var colourToken: String = ColourToken.clay.rawValue
    public var iconName: String = "target"
    public var sortOrder: Int = 0
    public var isArchived: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var workspace: Workspace?

    /// Nullify rather than cascade: dropping the goal must not delete the work
    /// done toward it — the projects simply stop belonging to anything.
    @Relationship(deleteRule: .nullify, inverse: \Project.initiative)
    public var projects: [Project]?

    public var colour: ColourToken { ColourToken.token(colourToken) }

    public init(
        title: String,
        summary: String = "",
        colourToken: String = ColourToken.clay.rawValue,
        iconName: String = "target",
        sortOrder: Int = 0,
        workspace: Workspace? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.summary = summary
        self.colourToken = colourToken
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.workspace = workspace
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func touch(_ date: Date = Date()) { updatedAt = date }

    // MARK: - Progress

    public var orderedProjects: [Project] {
        (projects ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Every task under this initiative that counts, through its projects.
    public var actionableTasks: [FlowTask] {
        (projects ?? []).flatMap(\.actionableTasks)
    }

    public var completedTaskCount: Int {
        actionableTasks.count { $0.status == .completed }
    }

    /// Derived on every read, the same rule `Project.progress` uses.
    public var progress: Double {
        let actionable = actionableTasks
        guard !actionable.isEmpty else { return 0 }
        return Double(actionable.count { $0.status == .completed }) / Double(actionable.count)
    }

    public var progressPercentText: String {
        "\(Int((progress * 100).rounded()))%"
    }

    /// Complete only once there is work and all of it is done — an initiative
    /// with no projects yet is not finished, it has not started.
    public var isComplete: Bool {
        !actionableTasks.isEmpty && completedTaskCount == actionableTasks.count
    }
}

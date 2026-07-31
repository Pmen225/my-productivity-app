import Foundation
import SwiftData

/// A user-created list of tasks.
///
/// Inbox, Today, Upcoming, Anytime, All Tasks and Completed are *not*
/// stored here — they are query-backed smart views (`SmartView`) so a task is
/// never duplicated into a second container.
@Model
public final class TaskList {
    public var id: UUID = UUID()
    public var name: String = ""
    public var iconName: String = "list.bullet"
    public var colourToken: String = ColourToken.blue.rawValue
    public var sortOrder: Int = 0
    public var groupingModeRaw: String = GroupingMode.manual.rawValue
    public var isSystemList: Bool = false
    public var isArchived: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var workspace: Workspace?

    @Relationship(deleteRule: .nullify, inverse: \FlowTask.list)
    public var tasks: [FlowTask]?

    public var groupingMode: GroupingMode {
        get { GroupingMode(rawValue: groupingModeRaw) ?? .manual }
        set { groupingModeRaw = newValue.rawValue; touch() }
    }

    public var colour: ColourToken { ColourToken.token(colourToken) }

    public init(
        name: String,
        iconName: String = "list.bullet",
        colourToken: String = ColourToken.blue.rawValue,
        sortOrder: Int = 0,
        groupingMode: GroupingMode = .manual,
        isSystemList: Bool = false,
        workspace: Workspace? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.colourToken = colourToken
        self.sortOrder = sortOrder
        self.groupingModeRaw = groupingMode.rawValue
        self.isSystemList = isSystemList
        self.isArchived = false
        self.workspace = workspace
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func touch(_ date: Date = Date()) { updatedAt = date }

    /// Open tasks only. Completed work leaves the list quietly rather than
    /// vanishing from history.
    public var openTasks: [FlowTask] {
        (tasks ?? []).filter { $0.status.isOpen }
    }
}

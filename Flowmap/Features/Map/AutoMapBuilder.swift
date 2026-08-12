import Foundation

/// Builds the map's tree fresh from the planned window (Task 63, R1–R7): the
/// scope is the same window `MapTaskScopeFilter` already computes for
/// emphasis, branches are one per `Project` with included work,
/// project-less tasks sit directly under root, and each task's subtasks hang
/// under it as plain nodes.
///
/// Pure and side-effect free. Every `MapNode` returned is a fresh, never
/// persisted instance (R4/R5) — the caller rebuilds this tree whenever the
/// underlying tasks or segments change rather than storing it.
enum AutoMapBuilder {
    /// A task that has at least one live segment starting inside the window,
    /// carrying the earliest such start for ordering (R6).
    private struct Included {
        let task: FlowTask
        let earliestStart: Date
    }

    /// One direct child of the root: either a project branch or a
    /// project-less task, ordered together by the same R6 rule.
    private enum RootChild {
        case branch(Project, [Included])
        case task(Included)

        var sortDate: Date {
            switch self {
            case .branch(_, let items):
                items.map(\.earliestStart).min() ?? .distantFuture
            case .task(let item):
                item.earliestStart
            }
        }

        var sortTitle: String {
            switch self {
            case .branch(let project, _): project.title
            case .task(let item): item.task.title
            }
        }
    }

    /// nil when nothing is planned in the window → caller shows the empty state.
    static func build(
        scope: TodayScope,
        reference: Date,
        tasks: [FlowTask],
        includesBacklog: Bool = false,
        calendar: Calendar = .current
    ) -> MapNode? {
        let window = MapTaskScopeFilter.interval(for: scope, at: reference, calendar: calendar)

        let included: [Included] = tasks.compactMap { task in
            if let earliest = task.liveSegments.map(\.startDate).filter(window.contains).min() {
                return Included(task: task, earliestStart: earliest)
            }
            guard includesBacklog, task.status.isOpen else { return nil }
            return Included(task: task, earliestStart: task.createdAt)
        }

        guard !included.isEmpty else { return nil }
        let includedIDs = Set(included.map { $0.task.id })

        var itemsByProject: [ObjectIdentifier: [Included]] = [:]
        var projectByID: [ObjectIdentifier: Project] = [:]
        var projectless: [Included] = []
        for item in included {
            if let parentID = item.task.parentTask?.id, includedIDs.contains(parentID) {
                continue
            }
            if let project = item.task.project {
                let key = ObjectIdentifier(project)
                itemsByProject[key, default: []].append(item)
                projectByID[key] = project
            } else {
                projectless.append(item)
            }
        }

        var rootChildren: [RootChild] = itemsByProject.map { key, items in
            .branch(projectByID[key]!, items)
        }
        rootChildren += projectless.map { .task($0) }
        rootChildren.sort { lhs, rhs in
            if lhs.sortDate != rhs.sortDate { return lhs.sortDate < rhs.sortDate }
            return lhs.sortTitle < rhs.sortTitle
        }

        let root = MapNode(title: scope.paneTitle, sortOrder: 0)
        root.isCollapsed = false
        root.children = rootChildren.enumerated().map { index, child in
            switch child {
            case .branch(let project, let items):
                let branch = MapNode(
                    title: project.title,
                    iconName: project.iconName,
                    colourToken: project.colourToken,
                    sortOrder: index,
                    parent: root
                )
                branch.isCollapsed = false
                branch.children = orderedTaskNodes(for: items, parent: branch, includedIDs: includedIDs)
                return branch
            case .task(let item):
                var visited: Set<UUID> = []
                return taskNode(
                    for: item.task,
                    sortOrder: index,
                    parent: root,
                    includedIDs: includedIDs,
                    visited: &visited
                )!
            }
        }

        return root
    }

    /// Tasks within a branch, ordered by first segment start then title (R6).
    private static func orderedTaskNodes(
        for items: [Included],
        parent: MapNode,
        includedIDs: Set<UUID>
    ) -> [MapNode] {
        var visited: Set<UUID> = []
        return items
            .sorted {
                if $0.earliestStart != $1.earliestStart { return $0.earliestStart < $1.earliestStart }
                return $0.task.title < $1.task.title
            }
            .enumerated()
            .compactMap { index, item in
                taskNode(
                    for: item.task,
                    sortOrder: index,
                    parent: parent,
                    includedIDs: includedIDs,
                    visited: &visited
                )
            }
    }

    /// A task node with its subtasks attached as plain child nodes. Starts
    /// collapsed when it has subtasks (R3) — a leaf task has no children, so
    /// the flag has nothing to hide either way.
    private static func taskNode(
        for task: FlowTask,
        sortOrder: Int,
        parent: MapNode,
        includedIDs: Set<UUID>,
        visited: inout Set<UUID>
    ) -> MapNode? {
        guard visited.insert(task.id).inserted else { return nil }
        let node = MapNode(
            title: task.title,
            iconName: task.iconName,
            colourToken: task.colourToken,
            sortOrder: sortOrder,
            parent: parent
        )
        node.isTask = true
        node.estimatedMinutes = task.estimatedMinutes
        // Never `linkedTask`: that writes the inverse onto the persisted
        // task and drags this never-inserted tree into the store.
        node.transientTask = task

        var taskChildren: [MapNode] = []
        let includedChildren = task.orderedChildTasks.filter { includedIDs.contains($0.id) }
        for (index, child) in includedChildren.enumerated() {
            if let childNode = taskNode(
                for: child,
                sortOrder: index,
                parent: node,
                includedIDs: includedIDs,
                visited: &visited
            ) {
                taskChildren.append(childNode)
            }
        }

        let subtaskNodes = task.orderedSubtasks.enumerated().map { index, subtask in
            MapNode(
                title: subtask.title,
                iconName: "checkmark.circle",
                colourToken: task.colourToken,
                sortOrder: taskChildren.count + index,
                parent: node
            )
        }
        node.children = taskChildren + subtaskNodes
        // Real task branches open on first view so the relationship is
        // legible immediately. Checklist-only detail stays collapsed to keep
        // the map calm; both remain user-toggleable.
        node.isCollapsed = taskChildren.isEmpty && !subtaskNodes.isEmpty

        return node
    }
}

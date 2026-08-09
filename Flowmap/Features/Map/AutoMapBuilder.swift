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
        calendar: Calendar = .current
    ) -> MapNode? {
        let window = MapTaskScopeFilter.interval(for: scope, at: reference, calendar: calendar)

        let included: [Included] = tasks.compactMap { task in
            guard let earliest = task.liveSegments.map(\.startDate).filter(window.contains).min() else {
                return nil
            }
            return Included(task: task, earliestStart: earliest)
        }

        guard !included.isEmpty else { return nil }

        var itemsByProject: [ObjectIdentifier: [Included]] = [:]
        var projectByID: [ObjectIdentifier: Project] = [:]
        var projectless: [Included] = []
        for item in included {
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
                let branch = MapNode(title: project.title, sortOrder: index, parent: root)
                branch.isCollapsed = false
                branch.children = orderedTaskNodes(for: items, parent: branch)
                return branch
            case .task(let item):
                return taskNode(for: item, sortOrder: index, parent: root)
            }
        }

        return root
    }

    /// Tasks within a branch, ordered by first segment start then title (R6).
    private static func orderedTaskNodes(for items: [Included], parent: MapNode) -> [MapNode] {
        items
            .sorted {
                if $0.earliestStart != $1.earliestStart { return $0.earliestStart < $1.earliestStart }
                return $0.task.title < $1.task.title
            }
            .enumerated()
            .map { index, item in taskNode(for: item, sortOrder: index, parent: parent) }
    }

    /// A task node with its subtasks attached as plain child nodes. Starts
    /// collapsed when it has subtasks (R3) — a leaf task has no children, so
    /// the flag has nothing to hide either way.
    private static func taskNode(for item: Included, sortOrder: Int, parent: MapNode) -> MapNode {
        let task = item.task
        let node = MapNode(
            title: task.title,
            colourToken: task.colourToken,
            sortOrder: sortOrder,
            parent: parent
        )
        node.isTask = true
        // Never `linkedTask`: that writes the inverse onto the persisted
        // task and drags this never-inserted tree into the store.
        node.transientTask = task

        let subtaskNodes = task.orderedSubtasks.enumerated().map { index, subtask in
            MapNode(title: subtask.title, sortOrder: index, parent: node)
        }
        node.children = subtaskNodes
        node.isCollapsed = !subtaskNodes.isEmpty

        return node
    }
}

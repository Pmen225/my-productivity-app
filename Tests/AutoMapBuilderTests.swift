import Foundation
import Testing
@testable import Flowmap

/// `AutoMapBuilder` is a pure function over plain, never-inserted models (R4),
/// so these tests build `FlowTask`/`Project`/`Subtask`/`TaskSegment` directly —
/// no `ModelContext` — matching the transient/derived contract the builder
/// itself must honour.
@MainActor
struct AutoMapBuilderTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    /// A task with the given segment start dates wired up as live, scheduled
    /// segments. `segments`/`subtasks` are assigned explicitly rather than
    /// relying on the reverse relationship syncing on a detached model —
    /// `liveSegments`/`orderedSubtasks` read those arrays directly.
    private func makeTask(
        _ title: String,
        project: Project? = nil,
        segmentStarts: [Date] = [],
        subtaskTitles: [String] = [],
        completed: Bool = false
    ) -> FlowTask {
        let task = FlowTask(title: title)
        task.project = project
        task.segments = segmentStarts.map { start in
            TaskSegment(
                task: task,
                startDate: start,
                endDate: start.addingTimeInterval(30 * 60),
                state: .scheduled,
                isLocked: false,
                source: .manual
            )
        }
        task.subtasks = subtaskTitles.enumerated().map { index, subtaskTitle in
            Subtask(title: subtaskTitle, sortOrder: index, task: task)
        }
        if completed {
            task.status = .completed
        }
        return task
    }

    /// Depth-first search for the task node linked to `title`.
    private func find(_ title: String, in node: MapNode) -> MapNode? {
        if node.displayTask?.title == title { return node }
        for child in node.orderedChildren {
            if let match = find(title, in: child) { return match }
        }
        return nil
    }

    /// Depth-first search for a plain (project branch) node titled `title`.
    private func find(branch title: String, in node: MapNode) -> MapNode? {
        if !node.isTask, node.title == title { return node }
        for child in node.orderedChildren {
            if let match = find(branch: title, in: child) { return match }
        }
        return nil
    }

    // MARK: - Case 1: backlog exclusion

    @Test("A task with no segments is backlog — it never appears on the auto map")
    func backlogTaskNeverAppears() {
        let scheduled = makeTask("Scheduled", segmentStarts: [date(10, hour: 9)])
        let backlog = makeTask("Backlog")

        let root = AutoMapBuilder.build(scope: .day, reference: date(10), tasks: [scheduled, backlog], calendar: calendar)

        #expect(root != nil)
        #expect(find("Scheduled", in: root!) != nil)
        #expect(find("Backlog", in: root!) == nil)
    }

    @Test("Plan's Map mode includes open unscheduled tasks")
    func backlogTaskAppearsInPlanMapMode() {
        let backlog = makeTask("Backlog")

        let root = AutoMapBuilder.build(
            scope: .day,
            reference: date(10),
            tasks: [backlog],
            includesBacklog: true,
            calendar: calendar
        )

        #expect(root != nil)
        #expect(find("Backlog", in: root!) != nil)
    }

    @Test("A FlowTask child is one connected child node, not a second root")
    func flowTaskHierarchyBuildsOneBranch() {
        let parent = makeTask("Project A")
        let child = makeTask("Subtask B")
        parent.childTasks = [child]
        child.parentTask = parent

        let root = AutoMapBuilder.build(
            scope: .day,
            reference: date(10),
            tasks: [parent, child],
            includesBacklog: true,
            calendar: calendar
        )!

        let parentNode = find("Project A", in: root)!
        let childNode = find("Subtask B", in: root)!
        #expect(root.orderedChildren.filter { $0.isTask }.map(\.title) == ["Project A"])
        #expect(childNode.parent?.id == parentNode.id)
        #expect(parentNode.isCollapsed == false)
        #expect(childNode.colourToken == child.colourToken)
    }

    @Test("Changing a task colour is reflected by its generated map node")
    func taskColourFlowsToMapNode() {
        let task = makeTask("Colourful task")
        task.colourToken = ColourToken.teal.rawValue

        let root = AutoMapBuilder.build(
            scope: .day,
            reference: date(10),
            tasks: [task],
            includesBacklog: true,
            calendar: calendar
        )!

        #expect(find("Colourful task", in: root)?.colourToken == ColourToken.teal.rawValue)
    }

    // MARK: - Case 2: window inclusion

    @Test("Only segments starting inside the scope window are included")
    func windowInclusion() {
        let inside = makeTask("Inside", segmentStarts: [date(10, hour: 9)])
        let outside = makeTask("Outside", segmentStarts: [date(11, hour: 9)])

        let root = AutoMapBuilder.build(scope: .day, reference: date(10), tasks: [inside, outside], calendar: calendar)

        #expect(root != nil)
        #expect(find("Inside", in: root!) != nil)
        #expect(find("Outside", in: root!) == nil)
    }

    // MARK: - Case 3: project grouping + project-less tasks under root

    @Test("Tasks group under a project branch; project-less tasks sit directly under root")
    func projectGroupingAndProjectlessTasks() {
        let project = Project(title: "Launch")
        let grouped = makeTask("Grouped", project: project, segmentStarts: [date(10, hour: 9)])
        let loose = makeTask("Loose", segmentStarts: [date(10, hour: 10)])

        let root = AutoMapBuilder.build(scope: .day, reference: date(10), tasks: [grouped, loose], calendar: calendar)!

        let branch = find(branch: "Launch", in: root)
        #expect(branch != nil)
        #expect(branch.flatMap { find("Grouped", in: $0) } != nil)

        // The loose task is a direct child of root, not nested in any branch.
        let looseNode = root.orderedChildren.first { $0.displayTask?.title == "Loose" }
        #expect(looseNode != nil)
    }

    // MARK: - Case 4: subtasks + default collapse states

    @Test("Subtasks attach under their task; a task with subtasks starts collapsed, its project branch starts expanded")
    func subtasksAndDefaultCollapse() {
        let project = Project(title: "Launch")
        let task = makeTask(
            "Write brief",
            project: project,
            segmentStarts: [date(10, hour: 9)],
            subtaskTitles: ["Outline", "Draft"]
        )

        let root = AutoMapBuilder.build(scope: .day, reference: date(10), tasks: [task], calendar: calendar)!
        let branch = find(branch: "Launch", in: root)!
        let taskNode = find("Write brief", in: root)!

        #expect(branch.isCollapsed == false)
        #expect(taskNode.isCollapsed == true)
        #expect(taskNode.orderedChildren.map(\.title) == ["Outline", "Draft"])
        #expect(taskNode.orderedChildren.allSatisfy { !$0.isTask && $0.linkedTask == nil })
    }

    // MARK: - Case 5: completed task stays visible

    @Test("A completed task in the window stays on the map, its node reporting completed")
    func completedTaskStaysVisible() {
        let task = makeTask("Ship it", segmentStarts: [date(10, hour: 9)], completed: true)

        let root = AutoMapBuilder.build(scope: .day, reference: date(10), tasks: [task], calendar: calendar)!
        let node = find("Ship it", in: root)!

        #expect(node.isCompleted)
    }

    // MARK: - Case 6: R6 ordering

    @Test("Branches order by earliest included segment start, not by title")
    func branchesOrderByEarliestSegmentStart() {
        // "Alpha" sorts first alphabetically but its earliest segment is later —
        // the earlier-starting "Zeta" branch must still come first.
        let alpha = Project(title: "Alpha")
        let zeta = Project(title: "Zeta")
        let laterTask = makeTask("Later", project: alpha, segmentStarts: [date(10, hour: 14)])
        let earlierTask = makeTask("Earlier", project: zeta, segmentStarts: [date(10, hour: 9)])

        let root = AutoMapBuilder.build(scope: .day, reference: date(10), tasks: [laterTask, earlierTask], calendar: calendar)!

        let branchTitles = root.orderedChildren.filter { !$0.isTask }.map(\.title)
        #expect(branchTitles == ["Zeta", "Alpha"])
    }

    @Test("Branches with the same earliest start order alphabetically by title")
    func branchesTiebreakByTitle() {
        let zeta = Project(title: "Zeta")
        let alpha = Project(title: "Alpha")
        let same = date(10, hour: 9)
        let taskA = makeTask("TaskA", project: zeta, segmentStarts: [same])
        let taskB = makeTask("TaskB", project: alpha, segmentStarts: [same])

        let root = AutoMapBuilder.build(scope: .day, reference: date(10), tasks: [taskA, taskB], calendar: calendar)!

        let branchTitles = root.orderedChildren.filter { !$0.isTask }.map(\.title)
        #expect(branchTitles == ["Alpha", "Zeta"])
    }

    @Test("Tasks within a branch order by first segment start, not by title")
    func tasksWithinBranchOrderBySegmentStart() {
        let project = Project(title: "Launch")
        let later = makeTask("Zebra", project: project, segmentStarts: [date(10, hour: 14)])
        let earlier = makeTask("Apple", project: project, segmentStarts: [date(10, hour: 9)])

        let root = AutoMapBuilder.build(scope: .day, reference: date(10), tasks: [later, earlier], calendar: calendar)!
        let branch = find(branch: "Launch", in: root)!

        #expect(branch.orderedChildren.map(\.title) == ["Apple", "Zebra"])
    }

    // MARK: - Case 7: empty input

    @Test("No tasks in the window produces no root")
    func emptyInputProducesNilRoot() {
        #expect(AutoMapBuilder.build(scope: .day, reference: date(10), tasks: [], calendar: calendar) == nil)

        let backlogOnly = makeTask("Backlog")
        #expect(AutoMapBuilder.build(scope: .day, reference: date(10), tasks: [backlogOnly], calendar: calendar) == nil)
    }

    // MARK: - Case 8: week/month windows

    @Test("Week scope honours MapTaskScopeFilter's seven-day window")
    func weekScopeWindow() {
        let inside = makeTask("Inside", segmentStarts: [date(18, hour: 9)])
        let outside = makeTask("Outside", segmentStarts: [date(19, hour: 9)])

        let root = AutoMapBuilder.build(scope: .week, reference: date(12), tasks: [inside, outside], calendar: calendar)!

        #expect(find("Inside", in: root) != nil)
        #expect(find("Outside", in: root) == nil)
    }

    @Test("Month scope honours MapTaskScopeFilter's four-calendar-week window")
    func monthScopeWindow() {
        let insideEarly = makeTask("InsideEarly", segmentStarts: [date(10, hour: 9)])
        let insideLate = makeTask("InsideLate", segmentStarts: [date(31, hour: 9)])
        let outside = makeTask("Outside", segmentStarts: [date(9, hour: 9)])

        let root = AutoMapBuilder.build(
            scope: .month,
            reference: date(12),
            tasks: [insideEarly, insideLate, outside],
            calendar: calendar
        )!

        #expect(find("InsideEarly", in: root) != nil)
        #expect(find("InsideLate", in: root) != nil)
        #expect(find("Outside", in: root) == nil)
    }

    /// Regression (Task 63 pixel gate): building the display tree must never
    /// write through to a PERSISTED task. Linking via the `linkedTask`
    /// relationship sets the inverse (`FlowTask.mapNode`) on the store side,
    /// dragging the never-inserted tree into the store — SwiftData asserted
    /// and crashed on every `-flowmapSeedDemo` relaunch that opened the Map
    /// (Flowmap-2026-08-09-041441.ips). The detached tasks every other test
    /// here uses cannot see the inverse write, so this one uses a real
    /// managed context.
    @Test
    func buildNeverMutatesPersistedTasks() throws {
        let world = try TestWorld()
        let task = FlowTask(title: "Persisted")
        world.context.insert(task)
        let start = world.date(hour: 12)
        let segment = TaskSegment(
            task: task,
            startDate: start,
            endDate: start.addingTimeInterval(30 * 60),
            state: .scheduled,
            isLocked: false,
            source: .manual
        )
        world.context.insert(segment)
        try world.context.save()

        let root = AutoMapBuilder.build(
            scope: .day,
            reference: start,
            tasks: [task],
            calendar: world.calendar
        )

        #expect(root != nil)
        #expect(task.mapNode == nil)
    }
}

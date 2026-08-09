import Foundation
import SwiftData

/// The demo workspace, offered on first launch rather than written silently.
public enum SeedData {
    /// A demo task described declaratively so the seed reads like the spec.
    private struct DemoTask {
        let title: String
        let minutes: Int
        let icon: String
        let colour: ColourToken
        let branch: String
        let subtasks: [String]
    }

    private static let demoTasks: [DemoTask] = [
        DemoTask(
            title: "Reading", minutes: 30, icon: "book", colour: .blue, branch: "Learning",
            subtasks: ["Choose chapter", "Read 10 pages", "Highlight key points", "Summarise notes"]
        ),
        DemoTask(
            title: "Exercise", minutes: 30, icon: "figure.run", colour: .green, branch: "Personal Wellbeing",
            subtasks: ["Warm up", "Main workout", "Cool down"]
        ),
        DemoTask(
            title: "Break", minutes: 15, icon: "cup.and.saucer", colour: .peach, branch: "Personal Wellbeing",
            subtasks: ["Leave the desk", "Drink water"]
        ),
        DemoTask(
            title: "Planning", minutes: 20, icon: "calendar", colour: .yellow, branch: "Focus Goals",
            subtasks: ["Review priorities", "Plan tomorrow"]
        ),
        DemoTask(
            title: "Learning", minutes: 45, icon: "graduationcap", colour: .teal, branch: "Learning",
            subtasks: ["Open lesson", "Take notes", "Write one takeaway"]
        ),
        DemoTask(
            title: "Focus", minutes: 25, icon: "target", colour: .lavender, branch: "Work Priorities",
            subtasks: ["Choose outcome", "Work without switching"]
        ),
        DemoTask(
            title: "Deep Work", minutes: 60, icon: "hammer", colour: .pink, branch: "Work Priorities",
            subtasks: ["Define deliverable", "Build", "Review"]
        ),
    ]

    private static let branches = [
        "Focus Goals", "Work Priorities", "Personal Wellbeing", "Learning", "Life & Fun",
    ]

    /// Whether a demo workspace already exists, so the offer can be hidden.
    @MainActor
    public static func isLoaded(in context: ModelContext) -> Bool {
        let workspaces = (try? context.fetch(FetchDescriptor<Workspace>())) ?? []
        return workspaces.contains { $0.name == "Personal" }
    }

    /// Creates the Personal workspace, the Weekly Plan map and the seven demo tasks.
    ///
    /// Idempotent: calling it twice does not create a second copy.
    /// Demo runs pin the appearance so screenshot passes are deterministic:
    /// dark when launched with `-flowmapDemoDark`, light otherwise.
    private static var demoAppearance: AppearanceMode {
        ProcessInfo.processInfo.arguments.contains("-flowmapDemoDark") ? .dark : .light
    }

    @MainActor
    @discardableResult
    public static func load(into context: ModelContext, settings: AppSettings) -> Workspace? {
        guard !isLoaded(in: context) else {
            // Re-seeding on a device that already holds the demo day: restore
            // the design's clay chrome and forget any persisted pan/zoom so
            // the map always reopens fitted — a stale offset from an older
            // layout frames empty canvas.
            settings.accentToken = ColourToken.clay.rawValue
            settings.appearance = demoAppearance
            // The original Focus design opens on the 2-task dial. Persisted
            // zoom state must not make a demo capture reopen on the tiny All
            // overview or force the founder to reconstruct the dial each run.
            settings.wheelVisibility = .two
            settings.appFont = .system
            settings.touch()
            if let maps = try? context.fetch(FetchDescriptor<MapDocument>()) {
                for map in maps {
                    map.canvasOffsetX = 0
                    map.canvasOffsetY = 0
                    map.canvasZoom = 1
                    for node in map.allNodes {
                        node.setManualPosition(nil)
                    }
                }
                try? context.save()
            }
            return nil
        }

        let workspace = Workspace(name: "Personal", iconName: "house", colourToken: ColourToken.violet.rawValue)
        context.insert(workspace)

        let inbox = TaskList(
            name: "Personal",
            iconName: "tray",
            colourToken: ColourToken.violet.rawValue,
            sortOrder: 0,
            workspace: workspace
        )
        context.insert(inbox)

        // Each branch is also a project, so the Stats page has real rows to
        // show rather than its "No projects yet" empty state. "Life & Fun"
        // deliberately gets no tasks below — it is what photographs the
        // per-project empty state.
        var branchProjects: [String: Project] = [:]
        for (index, name) in branches.enumerated() {
            let token = ColourToken.taskTokens[(index + 1) % ColourToken.taskTokens.count]

            let project = Project(
                title: name,
                colourToken: token.rawValue,
                sortOrder: index,
                workspace: workspace
            )
            context.insert(project)
            branchProjects[name] = project
        }

        for (index, demo) in demoTasks.enumerated() {
            let task = FlowTask(
                title: demo.title,
                status: .inbox,
                priority: index < 2 ? .high : .medium,
                estimatedMinutes: demo.minutes,
                colourToken: demo.colour.rawValue,
                iconName: demo.icon,
                sortOrder: index,
                list: inbox,
                workspace: workspace
            )
            task.isSplittable = demo.minutes >= 45
            task.minimumChunkMinutes = 15
            // Same branch, same project — so the Stats row's D/T fraction and
            // the map's branch tell the same story about the same work.
            task.project = branchProjects[demo.branch]
            context.insert(task)

            for (subIndex, title) in demo.subtasks.enumerated() {
                let subtask = Subtask(title: title, sortOrder: subIndex, task: task)
                context.insert(subtask)
            }
        }

        let note = Note(title: "How Flowmap works", iconName: "sparkles", workspace: workspace)
        context.insert(note)
        let noteLines: [(NoteBlockType, String)] = [
            (.heading2, "The loop"),
            (.paragraph, "Capture an idea, expand it on the map, turn branches into tasks, then let Flowmap place them in your day."),
            (.bullet, "Plan my day fills the gaps around anything fixed or locked."),
            (.bullet, "Focus walks you through one task at a time."),
            (.bullet, "Anything you do not finish is requeued automatically — it never just disappears."),
        ]
        for (index, line) in noteLines.enumerated() {
            context.insert(NoteBlock(type: line.0, text: line.1, sortOrder: index, note: note))
        }

        settings.hasLoadedDemoData = true
        // The demo day always photographs with the design's clay chrome, even
        // on a simulator that persisted an older accent choice.
        settings.accentToken = ColourToken.clay.rawValue
        settings.appearance = demoAppearance
        settings.wheelVisibility = .two
        settings.appFont = .system
        settings.touch()
        try? context.save()
        return workspace
    }

    /// Creates one deterministic unfinished sealed-day task for the review
    /// screenshot and UI smoke path. It is opt-in through a launch argument and
    /// never runs during an ordinary user launch.
    @MainActor
    public static func loadRolloverReviewDemo(into context: ModelContext, settings: AppSettings) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sourceDay = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let task = FlowTask(
            title: "Review the unfinished brief",
            status: .planned,
            estimatedMinutes: 30,
            sortOrder: 0
        )
        task.sealedForDay = sourceDay
        task.hasBeenPlanned = true
        context.insert(task)

        let start = calendar.date(
            bySettingHour: settings.workdayStartHour,
            minute: settings.workdayStartMinute,
            second: 0,
            of: sourceDay
        ) ?? sourceDay
        context.insert(TaskSegment(
            task: task,
            startDate: start,
            endDate: start.addingTimeInterval(30 * 60),
            state: .scheduled,
            source: .autoPlanned
        ))
        settings.sealedPlanDay = sourceDay
        settings.lastRolloverReviewedDay = nil
        settings.appearance = .light
        settings.touch()
        try? context.save()
    }

    /// Removes demo content so the user can start clean.
    @MainActor
    public static func reset(in context: ModelContext, settings: AppSettings) {
        let workspaces = (try? context.fetch(FetchDescriptor<Workspace>())) ?? []
        let demoWorkspaceIDs = Set(workspaces.filter { $0.name == "Personal" }.map(\.id))
        // Workspace.tasks and TaskList.tasks are intentionally `.nullify` for
        // CloudKit safety, so deleting the workspace alone leaves its tasks
        // orphaned until a later fetch. Capture and delete those task objects
        // explicitly before removing their containers.
        let tasks = (try? context.fetch(FetchDescriptor<FlowTask>())) ?? []
        for task in tasks where
            demoWorkspaceIDs.contains(task.workspace?.id ?? UUID()) ||
            demoWorkspaceIDs.contains(task.list?.workspace?.id ?? UUID()) {
            context.delete(task)
        }
        for workspace in workspaces where workspace.name == "Personal" {
            context.delete(workspace)
        }
        settings.hasLoadedDemoData = false
        settings.sealedPlanDay = nil
        settings.lastRolloverReviewedDay = nil
        settings.lastDayClearedAwardDay = nil
        settings.touch()
        try? context.save()
    }

    /// Restores the deterministic demo workspace immediately, including a
    /// fresh schedule for the current day. This is deliberately separate from
    /// `reset(in:settings:)`: the Settings action is a restart, not a one-way
    /// delete that waits for the next launch argument to seed again.
    @MainActor
    @discardableResult
    public static func restartDemoDay(in context: ModelContext, settings: AppSettings) -> Workspace? {
        reset(in: context, settings: settings)
        return load(into: context, settings: settings)
    }
}

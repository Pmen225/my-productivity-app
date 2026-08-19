import Foundation
import SwiftData

/// Every action the assistant can take. Each one calls an existing service or
/// mutates existing SwiftData models directly — there is no parallel
/// scheduling, focus or search logic here.
public enum AssistantToolName: String, CaseIterable, Sendable {
    case createTask
    case updateTask
    case completeTask
    case cancelTask
    case deleteTask
    case scheduleTask
    case rescheduleTask
    case rescheduleDay
    case createProject
    case createNote
    case appendNoteBlock
    case searchAppContent
    case summariseToday
    case startFocus

    // Calendar control API — see `CalendarControlAPI`.
    case listCalendarAccounts
    case connectCalendarAccount
    case disconnectCalendarAccount
    case setCalendarSelection
    case setCalendarConfiguration
    case listCalendarEvents
    case createCalendarEvent
    case moveCalendarEvent
    case deleteCalendarEvent

    /// Anything that touches many segments at once, disconnects an account, or
    /// writes/moves/deletes a calendar event always comes back as a preview
    /// the user must confirm before anything happens.
    public var requiresConfirmation: Bool {
        switch self {
        case .deleteTask, .rescheduleDay, .disconnectCalendarAccount, .createCalendarEvent, .moveCalendarEvent, .deleteCalendarEvent:
            return true
        default:
            return false
        }
    }
}

/// What a tool call did. Rendered directly — the assistant's own prose is
/// never trusted as a record of what happened.
public struct AssistantToolResult: Codable, Sendable {
    /// A reversible change the "Undo" affordance can replay.
    public enum UndoAction: Codable, Sendable {
        case deleteTask(UUID)
        case deleteProject(UUID)
        case deleteNote(UUID)
        case deleteNoteBlock(UUID)
        case unscheduleSegment(UUID)
        case moveSegment(UUID, Date)
        case reopenTask(UUID)
        case revertTask(UUID, TaskFieldSnapshot)
        case stopFocusSession
        /// Reverses the most recent plan the assistant applied.
        case undoLastPlan
    }

    public struct TaskFieldSnapshot: Codable, Sendable {
        public let title: String
        public let estimatedMinutes: Int
        public let priorityRaw: String
        public let dueDate: Date?
    }

    public let toolName: String
    public let success: Bool
    public let message: String
    public let undo: UndoAction?

    public init(toolName: String, success: Bool, message: String, undo: UndoAction? = nil) {
        self.toolName = toolName
        self.success = success
        self.message = message
        self.undo = undo
    }
}

/// A change big or ambiguous enough that it must be shown before it happens.
public struct AssistantToolProposal: Codable, Identifiable, Sendable {
    public var id = UUID()
    public let toolName: String
    public let title: String
    public let summary: String
    /// The original arguments, replayed by `AssistantToolRouter.confirm(_:)`.
    public let argumentsJSON: String

    public init(toolName: String, title: String, summary: String, argumentsJSON: String) {
        self.toolName = toolName
        self.title = title
        self.summary = summary
        self.argumentsJSON = argumentsJSON
    }
}

/// What running a tool call produces: either it already happened, or it needs
/// a confirmation first.
public enum AssistantToolOutcome: Sendable {
    case executed(AssistantToolResult)
    case pendingConfirmation(AssistantToolProposal)
}

/// Routes a named tool call (as the model or `QuickCommandParser` produced it)
/// to the existing domain services, and executes it against existing SwiftData
/// models. Read-only tools run immediately; obvious reversible edits run and
/// hand back an `UndoAction`; `rescheduleDay` always comes back as a proposal.
@MainActor
public struct AssistantToolRouter {
    private let flow: AppEnvironment
    private var context: ModelContext { flow.context }

    public init(flow: AppEnvironment) {
        self.flow = flow
    }

    public func handle(toolName: String, argumentsJSON: String) -> AssistantToolOutcome {
        guard let tool = AssistantToolName(rawValue: toolName) else {
            return .executed(AssistantToolResult(toolName: toolName, success: false, message: "I don't know how to do that yet."))
        }
        if tool.requiresConfirmation {
            return .pendingConfirmation(proposal(for: tool, argumentsJSON: argumentsJSON))
        }
        return .executed(execute(tool, argumentsJSON: argumentsJSON))
    }

    /// Runs a previously-shown proposal after the user confirms it.
    public func confirm(_ proposal: AssistantToolProposal) async -> AssistantToolResult {
        guard let tool = AssistantToolName(rawValue: proposal.toolName) else {
            return AssistantToolResult(toolName: proposal.toolName, success: false, message: "That proposal is no longer recognised.")
        }
        switch tool {
        case .createCalendarEvent: return await calendarAPI.createEvent(proposal.argumentsJSON)
        case .moveCalendarEvent: return await calendarAPI.moveEvent(proposal.argumentsJSON)
        case .deleteCalendarEvent: return await calendarAPI.deleteEvent(proposal.argumentsJSON)
        default: return execute(tool, argumentsJSON: proposal.argumentsJSON)
        }
    }

    public func undo(_ action: AssistantToolResult.UndoAction) -> AssistantToolResult {
        switch action {
        case .deleteTask(let id):
            guard let task = fetchTask(id) else { return undoFailed() }
            context.delete(task)
            save()
            return AssistantToolResult(toolName: "undo", success: true, message: "Removed the task that was created.")
        case .deleteProject(let id):
            guard let project = fetchProject(id) else { return undoFailed() }
            context.delete(project)
            save()
            return AssistantToolResult(toolName: "undo", success: true, message: "Removed the project that was created.")
        case .deleteNote(let id):
            guard let note = fetchNote(id) else { return undoFailed() }
            context.delete(note)
            save()
            return AssistantToolResult(toolName: "undo", success: true, message: "Removed the note that was created.")
        case .deleteNoteBlock(let id):
            guard let block = fetchNoteBlock(id) else { return undoFailed() }
            context.delete(block)
            save()
            return AssistantToolResult(toolName: "undo", success: true, message: "Removed the note block that was added.")
        case .unscheduleSegment(let id):
            guard let segment = fetchSegment(id) else { return undoFailed() }
            flow.scheduling().unschedule(segment: segment)
            return AssistantToolResult(toolName: "undo", success: true, message: "Unscheduled the task again.")
        case .moveSegment(let id, let start):
            guard let segment = fetchSegment(id), flow.scheduling().move(segment: segment, to: start) else { return undoFailed() }
            return AssistantToolResult(toolName: "undo", success: true, message: "Moved the task back to its previous time.")
        case .reopenTask(let id):
            guard let task = fetchTask(id) else { return undoFailed() }
            task.reopen()
            save()
            return AssistantToolResult(toolName: "undo", success: true, message: "\"\(task.title)\" was reopened.")
        case .revertTask(let id, let snapshot):
            guard let task = fetchTask(id) else { return undoFailed() }
            task.title = snapshot.title
            task.estimatedMinutes = snapshot.estimatedMinutes
            task.priorityRaw = snapshot.priorityRaw
            task.dueDate = snapshot.dueDate
            task.touch()
            save()
            return AssistantToolResult(toolName: "undo", success: true, message: "Reverted the changes to \"\(task.title)\".")
        case .stopFocusSession:
            flow.focusEngine.stop(now: flow.now)
            return AssistantToolResult(toolName: "undo", success: true, message: "Focus session stopped.")
        case .undoLastPlan:
            flow.undoLastPlan()
            return AssistantToolResult(toolName: "undo", success: true, message: "Put your schedule back the way it was.")
        }
    }

    // MARK: - Dispatch

    private func execute(_ tool: AssistantToolName, argumentsJSON: String) -> AssistantToolResult {
        switch tool {
        case .createTask: return createTask(argumentsJSON)
        case .updateTask: return updateTask(argumentsJSON)
        case .completeTask: return completeTask(argumentsJSON)
        case .cancelTask: return cancelTask(argumentsJSON)
        case .deleteTask: return deleteTask(argumentsJSON)
        case .scheduleTask: return scheduleTask(argumentsJSON)
        case .rescheduleTask: return rescheduleTask(argumentsJSON)
        case .rescheduleDay: return rescheduleDay(argumentsJSON)
        case .createProject: return createProject(argumentsJSON)
        case .createNote: return createNote(argumentsJSON)
        case .appendNoteBlock: return appendNoteBlock(argumentsJSON)
        case .searchAppContent: return searchAppContent(argumentsJSON)
        case .summariseToday: return summariseToday()
        case .startFocus: return startFocus(argumentsJSON)
        case .listCalendarAccounts: return calendarAPI.listAccounts()
        case .connectCalendarAccount: return calendarAPI.connect(argumentsJSON)
        case .disconnectCalendarAccount: return calendarAPI.disconnect(argumentsJSON)
        case .setCalendarSelection: return calendarAPI.setSelection(argumentsJSON)
        case .setCalendarConfiguration: return calendarAPI.setConfiguration(argumentsJSON)
        case .listCalendarEvents: return calendarAPI.listEvents(argumentsJSON)
        case .createCalendarEvent, .moveCalendarEvent, .deleteCalendarEvent:
            return AssistantToolResult(toolName: tool.rawValue, success: false, message: "Confirm this calendar change first.")
        }
    }

    private var calendarAPI: CalendarControlAPI { CalendarControlAPI(flow: flow) }

    private func proposal(for tool: AssistantToolName, argumentsJSON: String) -> AssistantToolProposal {
        switch tool {
        case .rescheduleDay:
            let args = decode(RescheduleDayArgs.self, argumentsJSON) ?? RescheduleDayArgs(dayISO8601: nil, replanExisting: nil)
            let day = date(from: args.dayISO8601) ?? flow.now
            let replanExisting = args.replanExisting ?? false
            let proposal = flow.planToday(replanExisting: replanExisting)
            return AssistantToolProposal(
                toolName: tool.rawValue,
                title: replanExisting ? "Replan the whole day" : "Plan today",
                summary: summarise(proposal),
                argumentsJSON: encode(RescheduleDayArgs(dayISO8601: ISO8601DateFormatter().string(from: day), replanExisting: replanExisting))
            )
        case .deleteTask:
            let title = decode(TaskQueryArgs.self, argumentsJSON)?.taskQuery ?? "this task"
            return AssistantToolProposal(
                toolName: tool.rawValue,
                title: "Delete \"\(title)\"",
                summary: "Permanently removes the task. This can't be undone.",
                argumentsJSON: argumentsJSON
            )
        case .disconnectCalendarAccount:
            let account = decode(CalendarControlAPI.AccountArgs.self, argumentsJSON)
            let name = account.flatMap { CalendarAccountKind(rawValue: $0.account) }?.displayName ?? "that account"
            return AssistantToolProposal(
                toolName: tool.rawValue,
                title: "Disconnect \(name)",
                summary: "Turns off \(name) and clears its selected calendars.",
                argumentsJSON: argumentsJSON
            )
        case .createCalendarEvent:
            let args = decode(CalendarControlAPI.CreateEventArgs.self, argumentsJSON)
            let title = args?.title ?? "this event"
            return AssistantToolProposal(
                toolName: tool.rawValue,
                title: "Create \"\(title)\"",
                summary: "Adds \"\(title)\" to your calendar.",
                argumentsJSON: argumentsJSON
            )
        case .moveCalendarEvent:
            return AssistantToolProposal(
                toolName: tool.rawValue,
                title: "Move calendar event",
                summary: "Moves the event to a new time.",
                argumentsJSON: argumentsJSON
            )
        case .deleteCalendarEvent:
            return AssistantToolProposal(
                toolName: tool.rawValue,
                title: "Delete calendar event",
                summary: "Removes the event from your calendar. This can't be undone.",
                argumentsJSON: argumentsJSON
            )
        default:
            return AssistantToolProposal(toolName: tool.rawValue, title: tool.rawValue, summary: "", argumentsJSON: argumentsJSON)
        }
    }

    // MARK: - Task tools

    private struct CreateTaskArgs: Codable {
        let title: String
        let minutes: Int?
        let dueDateISO8601: String?
        let priority: String?
        let projectTitle: String?
    }

    private func createTask(_ json: String) -> AssistantToolResult {
        guard let args = decode(CreateTaskArgs.self, json) else {
            return AssistantToolResult(toolName: AssistantToolName.createTask.rawValue, success: false, message: "I need at least a title to create a task.")
        }
        let title = args.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return AssistantToolResult(toolName: AssistantToolName.createTask.rawValue, success: false, message: "I need at least a title to create a task.")
        }
        let project = args.projectTitle.flatMap { findProject(matching: $0) }
        let task = FlowTask(
            title: title,
            priority: args.priority.flatMap(TaskPriority.init(rawValue:)) ?? .none,
            estimatedMinutes: args.minutes ?? flow.settings.defaultTaskMinutes,
            dueDate: flow.scheduling().dueDateForNewTask(
                date(from: args.dueDateISO8601),
                now: flow.now
            ),
            project: project
        )
        _ = TaskCreationService.insert(task, in: context)
        return AssistantToolResult(
            toolName: AssistantToolName.createTask.rawValue,
            success: true,
            message: "Created \"\(task.title)\" in the Inbox.",
            undo: .deleteTask(task.id)
        )
    }

    private struct UpdateTaskArgs: Codable {
        let taskQuery: String
        let title: String?
        let minutes: Int?
        let dueDateISO8601: String?
        let priority: String?
    }

    private func updateTask(_ json: String) -> AssistantToolResult {
        guard let args = decode(UpdateTaskArgs.self, json) else {
            return AssistantToolResult(toolName: AssistantToolName.updateTask.rawValue, success: false, message: "I need to know which task to change.")
        }
        guard let task = findTask(matching: args.taskQuery) else {
            return AssistantToolResult(toolName: AssistantToolName.updateTask.rawValue, success: false, message: "I couldn't find a single task matching \"\(args.taskQuery)\".")
        }
        let snapshot = AssistantToolResult.TaskFieldSnapshot(
            title: task.title, estimatedMinutes: task.estimatedMinutes, priorityRaw: task.priorityRaw, dueDate: task.dueDate
        )
        if let title = args.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { task.title = title }
        if let minutes = args.minutes { task.estimatedMinutes = minutes }
        if let priority = args.priority.flatMap(TaskPriority.init(rawValue:)) { task.priority = priority }
        if let due = date(from: args.dueDateISO8601) { task.dueDate = due }
        task.touch()
        save()
        return AssistantToolResult(
            toolName: AssistantToolName.updateTask.rawValue,
            success: true,
            message: "Updated \"\(task.title)\".",
            undo: .revertTask(task.id, snapshot)
        )
    }

    private struct TaskQueryArgs: Codable { let taskQuery: String }

    private func completeTask(_ json: String) -> AssistantToolResult {
        guard let args = decode(TaskQueryArgs.self, json) else {
            return AssistantToolResult(toolName: AssistantToolName.completeTask.rawValue, success: false, message: "I need to know which task to complete.")
        }
        guard let task = findTask(matching: args.taskQuery) else {
            return AssistantToolResult(toolName: AssistantToolName.completeTask.rawValue, success: false, message: "I couldn't find a single task matching \"\(args.taskQuery)\".")
        }
        task.markCompleted(at: flow.now)
        save()
        return AssistantToolResult(
            toolName: AssistantToolName.completeTask.rawValue,
            success: true,
            message: "Completed \"\(task.title)\".",
            undo: .reopenTask(task.id)
        )
    }

    private func cancelTask(_ json: String) -> AssistantToolResult {
        guard let args = decode(TaskQueryArgs.self, json) else {
            return AssistantToolResult(toolName: AssistantToolName.cancelTask.rawValue, success: false, message: "I need to know which task to cancel.")
        }
        guard let task = findTask(matching: args.taskQuery) else {
            return AssistantToolResult(toolName: AssistantToolName.cancelTask.rawValue, success: false, message: "I couldn't find a single task matching \"\(args.taskQuery)\".")
        }
        task.markCancelled(at: flow.now)
        save()
        return AssistantToolResult(
            toolName: AssistantToolName.cancelTask.rawValue,
            success: true,
            message: "Cancelled \"\(task.title)\".",
            undo: .reopenTask(task.id)
        )
    }

    private func deleteTask(_ json: String) -> AssistantToolResult {
        guard let args = decode(TaskQueryArgs.self, json) else {
            return AssistantToolResult(toolName: AssistantToolName.deleteTask.rawValue, success: false, message: "I need to know which task to delete.")
        }
        guard let task = findTask(matching: args.taskQuery) else {
            return AssistantToolResult(toolName: AssistantToolName.deleteTask.rawValue, success: false, message: "I couldn't find a single task matching \"\(args.taskQuery)\".")
        }
        let title = task.title
        context.delete(task)
        save()
        return AssistantToolResult(toolName: AssistantToolName.deleteTask.rawValue, success: true, message: "Deleted \"\(title)\".")
    }

    private struct ScheduleTaskArgs: Codable {
        let taskQuery: String
        let dateISO8601: String
    }

    private func scheduleTask(_ json: String) -> AssistantToolResult {
        guard let args = decode(ScheduleTaskArgs.self, json), let when = date(from: args.dateISO8601) else {
            return AssistantToolResult(toolName: AssistantToolName.scheduleTask.rawValue, success: false, message: "I need a task and a specific time to schedule it at.")
        }
        guard let task = findTask(matching: args.taskQuery) else {
            return AssistantToolResult(toolName: AssistantToolName.scheduleTask.rawValue, success: false, message: "I couldn't find a single task matching \"\(args.taskQuery)\".")
        }
        guard let segment = flow.scheduling().schedule(task: task, at: when) else {
            return AssistantToolResult(toolName: AssistantToolName.scheduleTask.rawValue, success: false, message: "That time is already busy, so I didn't schedule \"\(task.title)\".")
        }
        return AssistantToolResult(
            toolName: AssistantToolName.scheduleTask.rawValue,
            success: true,
            message: "Scheduled \"\(task.title)\" for \(DurationFormatter.time(when)).",
            undo: .unscheduleSegment(segment.id)
        )
    }

    private func rescheduleTask(_ json: String) -> AssistantToolResult {
        guard let args = decode(ScheduleTaskArgs.self, json), let when = date(from: args.dateISO8601) else {
            return AssistantToolResult(toolName: AssistantToolName.rescheduleTask.rawValue, success: false, message: "I need a task and a specific time to move it to.")
        }
        guard let task = findTask(matching: args.taskQuery) else {
            return AssistantToolResult(toolName: AssistantToolName.rescheduleTask.rawValue, success: false, message: "I couldn't find a single task matching \"\(args.taskQuery)\".")
        }
        let segments = task.liveSegments
        guard segments.count == 1, let segment = segments.first else {
            return AssistantToolResult(toolName: AssistantToolName.rescheduleTask.rawValue, success: false, message: "I need that task to have exactly one scheduled block before I can move it.")
        }
        let previousStart = segment.startDate
        guard flow.scheduling().move(segment: segment, to: when) else {
            return AssistantToolResult(toolName: AssistantToolName.rescheduleTask.rawValue, success: false, message: "That block is locked or the new time is busy, so I didn't move \"\(task.title)\".")
        }
        return AssistantToolResult(
            toolName: AssistantToolName.rescheduleTask.rawValue,
            success: true,
            message: "Moved \"\(task.title)\" to \(DurationFormatter.time(when)).",
            undo: .moveSegment(segment.id, previousStart)
        )
    }

    // MARK: - Reschedule day (always a proposal)

    private struct RescheduleDayArgs: Codable {
        let dayISO8601: String?
        let replanExisting: Bool?
    }

    /// Applies a plan the user has already confirmed.
    ///
    /// Goes through `AppEnvironment.applyPlan` so the assistant commits a plan by
    /// exactly the same path the Today screen uses — including the undo snapshot
    /// and the notification reschedule that come with it.
    private func rescheduleDay(_ argumentsJSON: String) -> AssistantToolResult {
        let args = decode(RescheduleDayArgs.self, argumentsJSON)
            ?? RescheduleDayArgs(dayISO8601: nil, replanExisting: nil)
        let replanExisting = args.replanExisting ?? false

        // Re-derive the plan at apply time: the day may have moved on since the
        // proposal was shown, and applying a stale plan would fight the schedule.
        let plan = flow.planToday(replanExisting: replanExisting)
        guard !plan.isEmpty else {
            return AssistantToolResult(
                toolName: AssistantToolName.rescheduleDay.rawValue,
                success: true,
                message: "Nothing needed rescheduling — the day already looks complete."
            )
        }

        flow.applyPlan(plan, replanExisting: replanExisting)

        return AssistantToolResult(
            toolName: AssistantToolName.rescheduleDay.rawValue,
            success: true,
            message: "Replanned your day. \(summarise(plan))",
            undo: .undoLastPlan
        )
    }

    private func summarise(_ proposal: PlanProposal) -> String {
        if proposal.isEmpty { return "Nothing needs rescheduling — the day already looks complete." }
        var parts: [String] = []
        let changed = proposal.changedBlockCount
        if changed > 0 { parts.append("\(changed) block\(changed == 1 ? "" : "s") will move or be added") }
        if !proposal.deferredTaskIDs.isEmpty {
            parts.append("\(proposal.deferredTaskIDs.count) task\(proposal.deferredTaskIDs.count == 1 ? "" : "s") will move to a later day")
        }
        if !proposal.unplaceable.isEmpty {
            parts.append("\(proposal.unplaceable.count) task\(proposal.unplaceable.count == 1 ? "" : "s") won't fit anywhere")
        }
        return parts.joined(separator: ". ") + "."
    }

    // MARK: - Projects

    private struct CreateProjectArgs: Codable {
        let title: String
        let colourToken: String?
    }

    private func createProject(_ json: String) -> AssistantToolResult {
        guard let args = decode(CreateProjectArgs.self, json) else {
            return AssistantToolResult(toolName: AssistantToolName.createProject.rawValue, success: false, message: "I need a project title.")
        }
        let title = args.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return AssistantToolResult(toolName: AssistantToolName.createProject.rawValue, success: false, message: "I need a project title.")
        }
        let token = args.colourToken.flatMap(ColourToken.init(rawValue:)) ?? .violet
        let existingCount = (try? context.fetchCount(FetchDescriptor<Project>())) ?? 0
        let project = Project(title: title, colourToken: token.rawValue, sortOrder: existingCount)
        context.insert(project)
        save()
        return AssistantToolResult(
            toolName: AssistantToolName.createProject.rawValue,
            success: true,
            message: "Created project \"\(project.title)\".",
            undo: .deleteProject(project.id)
        )
    }

    // MARK: - Notes

    private struct CreateNoteArgs: Codable {
        let title: String
        let projectTitle: String?
    }

    private func createNote(_ json: String) -> AssistantToolResult {
        guard let args = decode(CreateNoteArgs.self, json) else {
            return AssistantToolResult(toolName: AssistantToolName.createNote.rawValue, success: false, message: "I need a note title.")
        }
        let title = args.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return AssistantToolResult(toolName: AssistantToolName.createNote.rawValue, success: false, message: "I need a note title.")
        }
        let project = args.projectTitle.flatMap { findProject(matching: $0) }
        let note = Note(title: title, project: project)
        context.insert(note)
        save()
        return AssistantToolResult(
            toolName: AssistantToolName.createNote.rawValue,
            success: true,
            message: "Created note \"\(note.title)\".",
            undo: .deleteNote(note.id)
        )
    }

    private struct AppendNoteBlockArgs: Codable {
        let noteTitle: String
        let text: String
        let blockType: String?
    }

    private func appendNoteBlock(_ json: String) -> AssistantToolResult {
        guard let args = decode(AppendNoteBlockArgs.self, json) else {
            return AssistantToolResult(toolName: AssistantToolName.appendNoteBlock.rawValue, success: false, message: "I need text to append to a note.")
        }
        let text = args.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return AssistantToolResult(toolName: AssistantToolName.appendNoteBlock.rawValue, success: false, message: "I need text to append to a note.")
        }
        guard let note = findNote(matching: args.noteTitle) else {
            return AssistantToolResult(toolName: AssistantToolName.appendNoteBlock.rawValue, success: false, message: "I couldn't find a single note matching \"\(args.noteTitle)\".")
        }
        let type = args.blockType.flatMap(NoteBlockType.init(rawValue:)) ?? .paragraph
        let block = NoteBlock(type: type, text: text, sortOrder: note.orderedBlocks.count, note: note)
        context.insert(block)
        note.touch()
        save()
        return AssistantToolResult(
            toolName: AssistantToolName.appendNoteBlock.rawValue,
            success: true,
            message: "Added a block to \"\(note.title)\".",
            undo: .deleteNoteBlock(block.id)
        )
    }

    // MARK: - Read-only tools

    private struct SearchArgs: Codable { let query: String }

    private func searchAppContent(_ json: String) -> AssistantToolResult {
        guard let args = decode(SearchArgs.self, json) else {
            return AssistantToolResult(toolName: AssistantToolName.searchAppContent.rawValue, success: false, message: "I need something to search for.")
        }
        let query = args.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return AssistantToolResult(toolName: AssistantToolName.searchAppContent.rawValue, success: false, message: "I need something to search for.")
        }
        let results = flow.searchService.search(query)
        guard !results.isEmpty else {
            return AssistantToolResult(toolName: AssistantToolName.searchAppContent.rawValue, success: true, message: "No matches for \"\(query)\".")
        }
        let lines = results.prefix(8).map { "\($0.kind.displayName): \($0.title) — \($0.context)" }
        return AssistantToolResult(toolName: AssistantToolName.searchAppContent.rawValue, success: true, message: lines.joined(separator: "\n"))
    }

    private func summariseToday() -> AssistantToolResult {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: flow.now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
        let segments = flow.scheduling().allSegments().filter { $0.startDate >= dayStart && $0.startDate < dayEnd }
        let completed = segments.count { $0.state == .completed }
        let scheduled = segments.count { $0.state == .scheduled }
        let missed = segments.count { $0.state == .missed }
        let totalMinutes = segments.filter { $0.state.occupiesTimeline }.reduce(0) { $0 + $1.durationMinutes }
        var message = "\(segments.count) block\(segments.count == 1 ? "" : "s") today (\(DurationFormatter.compact(minutes: totalMinutes)))."
        message += " \(completed) completed, \(scheduled) still scheduled" + (missed > 0 ? ", \(missed) missed" : "") + "."
        return AssistantToolResult(toolName: AssistantToolName.summariseToday.rawValue, success: true, message: message)
    }

    // MARK: - Focus

    private struct StartFocusArgs: Codable {
        let taskQuery: String?
        let minutes: Int?
    }

    private func startFocus(_ json: String) -> AssistantToolResult {
        let args = decode(StartFocusArgs.self, json) ?? StartFocusArgs(taskQuery: nil, minutes: nil)
        if let query = args.taskQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            guard let task = findTask(matching: query) else {
                return AssistantToolResult(toolName: AssistantToolName.startFocus.rawValue, success: false, message: "I couldn't find a single task matching \"\(query)\".")
            }
            // The Assistant starts through the same rule as the wheel — it
            // cannot skip the compulsory planning gate for an unplanned
            // task, only report that it is blocked. `pendingGate` is now set
            // on the real, shared engine, so the gate modal is ready the
            // moment Focus is next opened.
            guard flow.focusEngine.start(task: task, minutes: args.minutes, now: flow.now) != nil else {
                if flow.focusEngine.pendingGate?.kind == .planGate {
                    return AssistantToolResult(toolName: AssistantToolName.startFocus.rawValue, success: false, message: "\"\(task.title)\" needs a Definition of Done before it can start — open Flowmap to plan it.")
                }
                return AssistantToolResult(toolName: AssistantToolName.startFocus.rawValue, success: false, message: "Focus couldn't start for \"\(task.title)\".")
            }
            return AssistantToolResult(toolName: AssistantToolName.startFocus.rawValue, success: true, message: "Focus started on \"\(task.title)\".", undo: .stopFocusSession)
        }
        guard flow.focusEngine.startFreeFocus(minutes: args.minutes, now: flow.now) != nil else {
            return AssistantToolResult(toolName: AssistantToolName.startFocus.rawValue, success: false, message: "Focus couldn't start.")
        }
        return AssistantToolResult(toolName: AssistantToolName.startFocus.rawValue, success: true, message: "Free focus started.", undo: .stopFocusSession)
    }

    // MARK: - Lookup helpers

    private func findByTitle<T: PersistentModel>(
        _ type: T.Type,
        query: String,
        title: (T) -> String,
        where predicate: (T) -> Bool = { _ in true }
    ) -> T? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let items = ((try? context.fetch(FetchDescriptor<T>())) ?? []).filter(predicate)
        let exact = items.filter { title($0).caseInsensitiveCompare(trimmed) == .orderedSame }
        if exact.count == 1 { return exact.first }
        let partial = items.filter { title($0).range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        return partial.count == 1 ? partial.first : nil
    }

    private func findTask(matching query: String) -> FlowTask? {
        findByTitle(FlowTask.self, query: query, title: { $0.title }, where: { $0.status.isOpen })
    }

    private func findProject(matching query: String) -> Project? {
        findByTitle(Project.self, query: query, title: { $0.title })
    }

    private func findNote(matching query: String) -> Note? {
        findByTitle(Note.self, query: query, title: { $0.title })
    }

    private func fetchTask(_ id: UUID) -> FlowTask? {
        var descriptor = FetchDescriptor<FlowTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func fetchProject(_ id: UUID) -> Project? {
        var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func fetchNote(_ id: UUID) -> Note? {
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func fetchNoteBlock(_ id: UUID) -> NoteBlock? {
        var descriptor = FetchDescriptor<NoteBlock>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func fetchSegment(_ id: UUID) -> TaskSegment? {
        var descriptor = FetchDescriptor<TaskSegment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - JSON / misc

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    private func date(from iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        if let date = ISO8601DateFormatter().date(from: iso) { return date }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: iso)
    }

    private func undoFailed() -> AssistantToolResult {
        AssistantToolResult(toolName: "undo", success: false, message: "That change could not be undone — it may already have been removed.")
    }

    private func save() {
        try? context.save()
    }

    /// Schemas handed to `AssistantService`, shared verbatim between providers.
    public static let toolDefinitions: [AssistantToolDefinition] = [
        AssistantToolDefinition(
            name: AssistantToolName.createTask.rawValue,
            description: "Create a new task in the Inbox.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "title":{"type":"string","description":"The task title."},
              "minutes":{"type":"integer","description":"Estimated duration in minutes."},
              "dueDateISO8601":{"type":"string","description":"ISO 8601 due date/time, if the user gave one."},
              "priority":{"type":"string","enum":["none","low","medium","high"]},
              "projectTitle":{"type":"string","description":"An existing project to file this under, if any."}
            },"required":["title"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.updateTask.rawValue,
            description: "Change a task's title, duration, priority or due date.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "taskQuery":{"type":"string","description":"Text to find the task by title."},
              "title":{"type":"string"},
              "minutes":{"type":"integer"},
              "dueDateISO8601":{"type":"string"},
              "priority":{"type":"string","enum":["none","low","medium","high"]}
            },"required":["taskQuery"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.completeTask.rawValue,
            description: "Mark a task as completed.",
            parametersSchemaJSON: """
            {"type":"object","properties":{"taskQuery":{"type":"string","description":"Text to find the task by title."}},"required":["taskQuery"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.cancelTask.rawValue,
            description: "Cancel a task.",
            parametersSchemaJSON: """
            {"type":"object","properties":{"taskQuery":{"type":"string","description":"Text to find the task by title."}},"required":["taskQuery"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.deleteTask.rawValue,
            description: "Permanently delete a task. Destructive — always confirmed first.",
            parametersSchemaJSON: """
            {"type":"object","properties":{"taskQuery":{"type":"string","description":"Text to find the task by title."}},"required":["taskQuery"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.scheduleTask.rawValue,
            description: "Place a task on the timeline at a specific date and time.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "taskQuery":{"type":"string","description":"Text to find the task by title."},
              "dateISO8601":{"type":"string","description":"ISO 8601 date/time to schedule it at."}
            },"required":["taskQuery","dateISO8601"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.rescheduleTask.rawValue,
            description: "Move a task's existing scheduled block to a specific date and time.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "taskQuery":{"type":"string","description":"Text to find the task by title."},
              "dateISO8601":{"type":"string","description":"ISO 8601 date/time to move its scheduled block to."}
            },"required":["taskQuery","dateISO8601"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.rescheduleDay.rawValue,
            description: "Re-plan a day's timeline. Always returns a preview the user must confirm before anything changes.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "dayISO8601":{"type":"string","description":"The day to plan; defaults to today."},
              "replanExisting":{"type":"boolean","description":"If true, also moves already-scheduled blocks."}
            }}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.createProject.rawValue,
            description: "Create a new project.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "title":{"type":"string"},
              "colourToken":{"type":"string"}
            },"required":["title"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.createNote.rawValue,
            description: "Create a new note.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "title":{"type":"string"},
              "projectTitle":{"type":"string","description":"An existing project to file this under, if any."}
            },"required":["title"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.appendNoteBlock.rawValue,
            description: "Append a block of text to an existing note.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "noteTitle":{"type":"string","description":"Text to find the note by title."},
              "text":{"type":"string"},
              "blockType":{"type":"string","enum":["paragraph","heading1","heading2","bullet","checklist","quote","divider"]}
            },"required":["noteTitle","text"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.searchAppContent.rawValue,
            description: "Search tasks, projects and notes for matching text. Read-only.",
            parametersSchemaJSON: """
            {"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.summariseToday.rawValue,
            description: "Summarise how today's schedule is going. Read-only.",
            parametersSchemaJSON: """
            {"type":"object","properties":{}}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.startFocus.rawValue,
            description: "Start a focus session, either on a named task or as free focus.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "taskQuery":{"type":"string","description":"Text to find the task by title; omit for free focus."},
              "minutes":{"type":"integer"}
            }}
            """
        ),

        // MARK: Calendar control API

        AssistantToolDefinition(
            name: AssistantToolName.listCalendarAccounts.rawValue,
            description: "List every calendar account (Apple, Google), whether it's connected, its calendars, which are selected, and its last error. Read-only.",
            parametersSchemaJSON: """
            {"type":"object","properties":{}}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.connectCalendarAccount.rawValue,
            description: "Start connecting a calendar account. Returns immediately; the sign-in sheet (if any) appears in the app.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "account":{"type":"string","enum":["apple","google"]}
            },"required":["account"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.disconnectCalendarAccount.rawValue,
            description: "Disconnect a calendar account and clear its selected calendars. Destructive — always confirmed first.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "account":{"type":"string","enum":["apple","google"]}
            },"required":["account"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.setCalendarSelection.rawValue,
            description: "Choose which of an account's calendars are read for busy time.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "account":{"type":"string","enum":["apple","google"]},
              "calendarIds":{"type":"array","items":{"type":"string"}}
            },"required":["account","calendarIds"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.setCalendarConfiguration.rawValue,
            description: "Change calendar configuration: whether an account is enabled, the Google OAuth client id, the write-back calendar, or whether focus blocks are written back. Never accepts or returns a secret.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "account":{"type":"string","enum":["apple","google"]},
              "enabled":{"type":"boolean"},
              "googleClientId":{"type":"string"},
              "writeBackCalendarId":{"type":"string"},
              "writesFocusBlocks":{"type":"boolean"}
            },"required":["account"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.listCalendarEvents.rawValue,
            description: "List merged busy calendar events in a date range, across one or all accounts. Read-only.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "startISO8601":{"type":"string"},
              "endISO8601":{"type":"string"},
              "account":{"type":"string","enum":["apple","google"]}
            },"required":["startISO8601","endISO8601"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.createCalendarEvent.rawValue,
            description: "Create an event on a calendar. Destructive — always confirmed first.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "account":{"type":"string","enum":["apple","google"]},
              "calendarId":{"type":"string"},
              "title":{"type":"string"},
              "startISO8601":{"type":"string"},
              "endISO8601":{"type":"string"}
            },"required":["account","calendarId","title","startISO8601","endISO8601"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.moveCalendarEvent.rawValue,
            description: "Move an existing calendar event to a new start and end time. Destructive — always confirmed first.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "account":{"type":"string","enum":["apple","google"]},
              "eventId":{"type":"string"},
              "startISO8601":{"type":"string"},
              "endISO8601":{"type":"string"}
            },"required":["account","eventId","startISO8601","endISO8601"]}
            """
        ),
        AssistantToolDefinition(
            name: AssistantToolName.deleteCalendarEvent.rawValue,
            description: "Delete a calendar event. Destructive — always confirmed first, and cannot be undone.",
            parametersSchemaJSON: """
            {"type":"object","properties":{
              "account":{"type":"string","enum":["apple","google"]},
              "eventId":{"type":"string"}
            },"required":["account","eventId"]}
            """
        ),
    ]
}

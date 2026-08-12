import Foundation
import SwiftData

/// The draft lifecycle for a task created from `TaskDetailInspector`'s
/// creation mode: a blank `FlowTask` is inserted immediately so the editor's
/// live `@Bindable` body can bind to it from the first frame, then every exit
/// path — Cancel, Done, or a swipe dismissal — either keeps it (a real title)
/// or discards it (empty/whitespace-only title). Kept as pure static
/// functions, decoupled from SwiftUI, so that rule is testable without a live
/// view or `AppEnvironment`.
@MainActor
public enum TaskDraft {
    /// Seed context applied to a freshly inserted draft, mirroring
    /// `QuickCaptureView`'s existing seeding: an explicit id always wins,
    /// otherwise the task lands in Inbox (`list == nil`) with no project —
    /// the same default `QuickCaptureView` already has today.
    public struct Seed {
        public var projectID: UUID?
        public var listID: UUID?
        public var parentTaskID: UUID?
        public var dueDate: Date?
        public var flagForTodayIfUndated: Bool

        public init(
            projectID: UUID? = nil,
            listID: UUID? = nil,
            parentTaskID: UUID? = nil,
            dueDate: Date? = nil,
            flagForTodayIfUndated: Bool = false
        ) {
            self.projectID = projectID
            self.listID = listID
            self.parentTaskID = parentTaskID
            self.dueDate = dueDate
            self.flagForTodayIfUndated = flagForTodayIfUndated
        }
    }

    /// A blank task, not yet inserted into any context. Title starts empty so
    /// the empty-title exit rule always has something real to check.
    public static func makeTask(estimatedMinutes: Int) -> FlowTask {
        FlowTask(title: "", status: .inbox, estimatedMinutes: estimatedMinutes)
    }

    /// Inserts the draft and applies its seed. `resolvedDueDate` and
    /// `shouldFlagToday` are computed by the caller — the view has access to
    /// `SchedulingService` for `dueDateForNewTask`/`isPlanSealed`, which this
    /// type deliberately does not depend on, so it stays testable with a bare
    /// `ModelContext`.
    @discardableResult
    public static func insert(
        _ task: FlowTask,
        context: ModelContext,
        seed: Seed,
        projects: [Project],
        lists: [TaskList],
        tasks: [FlowTask],
        resolvedDueDate: Date?,
        shouldFlagToday: Bool
    ) -> Bool {
        task.project = projects.first { $0.id == seed.projectID }
        task.list = lists.first { $0.id == seed.listID }
        task.dueDate = resolvedDueDate
        if shouldFlagToday {
            task.isFlaggedForToday = true
        }

        let parent = tasks.first { $0.id == seed.parentTaskID }
        guard seed.parentTaskID == nil || parent != nil else { return false }
        return TaskCreationService.insert(task, parent: parent, in: context)
    }

    /// Cancel always discards the draft, whatever the title.
    public static func cancel(_ task: FlowTask, context: ModelContext) {
        context.delete(task)
        try? context.save()
    }

    /// Done, and a swipe dismissal, keep the draft only when it has a real
    /// title. Returns whether the task survived.
    @discardableResult
    public static func finish(_ task: FlowTask, context: ModelContext) -> Bool {
        let trimmed = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            context.delete(task)
            try? context.save()
            return false
        }
        try? context.save()
        return true
    }
}

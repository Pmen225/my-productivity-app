import SwiftData

/// The single persistence seam for newly created tasks, regardless of which
/// feature presented the creation surface.
public enum TaskCreationService {
    /// Inserts and saves `task`, optionally as a child of `parent`.
    ///
    /// Child tasks inherit their parent's organising context and colour so the
    /// same branch remains recognisable in Plan, Focus and Map.
    @MainActor
    @discardableResult
    public static func insert(
        _ task: FlowTask,
        parent: FlowTask? = nil,
        in context: ModelContext
    ) -> Bool {
        guard task.assignParent(parent) else { return false }

        if let parent {
            task.project = parent.project
            task.list = parent.list
            task.workspace = parent.workspace
            task.colourToken = parent.colourToken
        }

        context.insert(task)
        do {
            try context.save()
            return true
        } catch {
            context.delete(task)
            return false
        }
    }
}

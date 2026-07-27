import Foundation
import SwiftData

/// Turns an idea on the map into real, schedulable work.
@MainActor
public enum MapNodeConversion {
    /// Converts `node` to a task, reusing the existing link if there is one.
    ///
    /// Hard requirement: tapping convert twice must never create a second
    /// `FlowTask` — the guard below is the whole of that contract.
    @discardableResult
    public static func convertToTask(_ node: MapNode, in context: ModelContext) -> FlowTask {
        if let existing = node.linkedTask { return existing }

        let task = FlowTask(
            title: node.title,
            details: node.body,
            status: .inbox,
            priority: node.priority,
            estimatedMinutes: node.estimatedMinutes,
            colourToken: node.colourToken,
            iconName: node.iconName.isEmpty ? "circle" : node.iconName,
            project: node.map?.project,
            workspace: node.map?.workspace
        )
        context.insert(task)
        // `FlowTask.mapNode` is the inverse of this relationship, so setting it
        // here is what makes the link bidirectional.
        node.linkedTask = task
        node.isTask = true
        node.touch()
        try? context.save()
        return task
    }

    /// "Schedule now": asks the planner for the next free slot and drops the
    /// task straight into it. Falls back to the Inbox when nothing is free
    /// inside the lookahead window rather than failing silently.
    public static func scheduleNow(_ task: FlowTask, using scheduling: SchedulingService, now: Date = Date()) {
        let proposal = scheduling.proposePlan(for: now, now: now)
        if let block = proposal.blocks.first(where: { $0.taskID == task.id }) {
            scheduling.schedule(task: task, at: block.start, minutes: block.minutes)
        } else {
            task.status = .inbox
        }
    }

    /// "Send to Inbox": explicit rather than implicit, so choosing it from the
    /// inspector always reads as an intentional decision.
    public static func sendToInbox(_ task: FlowTask) {
        task.status = .inbox
    }
}

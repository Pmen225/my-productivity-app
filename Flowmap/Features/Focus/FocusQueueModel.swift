import Foundation

/// Pure derivation for the Focus screen's now-bar and its queue sheet: what
/// the always-visible bar shows, and which row a freshly presented sheet
/// opens to. Kept free of SwiftUI so it is testable without a host view —
/// `FocusNowBar` and `FocusQueueSheet` both read it, never recompute the
/// fallback chain themselves.
///
/// Founder ruling 2026-08-08 (option B): replaces `FocusTaskCard`'s detent
/// card with a slim bar plus a native resizable sheet.
struct FocusQueueModel {
    let queue: [TaskSegment]
    let activeTask: FlowTask?
    let activeSegmentID: UUID?

    /// Case 4: nothing running and nothing queued — there is nothing for the
    /// bar to say, so it is not shown at all.
    var isBarVisible: Bool {
        activeTask != nil || !queue.isEmpty
    }

    /// Fallback chain:
    /// 1. active task + next incomplete subtask -> that subtask's title;
    /// 2. active task, no checklist or all complete -> the task's own title;
    /// 3. no active task, queue non-empty -> "Today's queue";
    /// 4. neither -> empty (see `isBarVisible`).
    var barTitle: String {
        if let activeTask {
            if let next = nextIncompleteSubtask(of: activeTask) {
                return next.title
            }
            return activeTask.title
        }
        if !queue.isEmpty { return "Today's queue" }
        return ""
    }

    /// Caption paired with `barTitle`, same fallback order. Case 2's "Ready
    /// to finish" reuses the old collapsed-peek wording (UK spelling kept).
    var barCaption: String {
        if let activeTask {
            if nextIncompleteSubtask(of: activeTask) != nil {
                return activeTask.subtaskProgressLabel ?? ""
            }
            return "Ready to finish"
        }
        if !queue.isEmpty { return "\(queue.count) tasks" }
        return ""
    }

    /// Seeded into the sheet's `expandedSegmentID` on present, so the active
    /// task's checklist is already open rather than making the founder
    /// re-find and re-tap it every time (controls never move).
    var initiallyExpandedSegmentID: UUID? { activeSegmentID }

    private func nextIncompleteSubtask(of task: FlowTask) -> Subtask? {
        task.orderedSubtasks.first { !$0.isCompleted }
    }
}

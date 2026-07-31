import SwiftUI

/// Unscheduled work waiting for a slot — matches `SmartView.inbox`. Rows are
/// drag sources for manual scheduling onto the timeline.
struct TodayInboxSection: View {
    let tasks: [FlowTask]

    var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.m) {
            CompactSectionHeader(title: "Inbox", count: tasks.count)

            if tasks.isEmpty {
                FlowEmptyState(
                    symbol: "tray",
                    title: "Inbox clear",
                    message: SmartView.inbox.emptyMessage
                )
            } else {
                VStack(spacing: FlowSpacing.s) {
                    ForEach(tasks) { task in
                        TaskRowView(task: task)
                            .onDrag {
                                TimelineHaptics.dragStarted()
                                let minutes = task.unscheduledMinutes > 0
                                    ? task.unscheduledMinutes
                                    : task.estimatedMinutes
                                return TimelineDragPayload(
                                    taskID: task.id,
                                    segmentID: nil,
                                    minutes: max(SchedulingEngine.snapMinutes, minutes)
                                ).itemProvider()
                            }
                    }
                }
            }
        }
    }
}

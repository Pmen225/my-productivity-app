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
                        TodayInboxRow(task: task)
                    }
                }
            }
        }
    }
}

private struct TodayInboxRow: View {
    @Environment(\.colorScheme) private var scheme
    let task: FlowTask

    private var minutes: Int {
        task.unscheduledMinutes > 0 ? task.unscheduledMinutes : task.estimatedMinutes
    }

    var body: some View {
        HStack(spacing: FlowSpacing.s) {
            Image(systemName: task.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(task.colour.onSoft)
                .frame(width: 22, height: 22)
                .background(Circle().fill(task.colour.soft))

            Text(task.title)
                .font(FlowFont.secondary)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .lineLimit(1)

            Spacer(minLength: FlowSpacing.s)
            DurationChip(minutes: minutes, tint: task.colour)
        }
        .padding(FlowSpacing.s)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                .fill(FlowTheme.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                .strokeBorder(FlowTheme.separator(scheme), lineWidth: 1)
        )
        .onDrag {
            TimelineHaptics.dragStarted()
            return TimelineDragPayload(
                taskID: task.id,
                segmentID: nil,
                minutes: max(SchedulingEngine.snapMinutes, minutes)
            ).itemProvider()
        }
    }
}

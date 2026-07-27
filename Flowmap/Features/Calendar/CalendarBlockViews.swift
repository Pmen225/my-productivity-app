import SwiftUI

/// A Flowmap task's scheduled block. Uses the task's own colour token, so it
/// reads as the same object in Calendar as it does in Today and Focus.
struct TaskSegmentBlockView: View {
    @Environment(\.colorScheme) private var scheme
    let segment: TaskSegment

    private var task: FlowTask? { segment.task }
    private var colour: ColourToken { task?.colour ?? .violet }

    var body: some View {
        HStack(spacing: FlowSpacing.xs) {
            Image(systemName: task?.iconName ?? "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colour.onSoft)
            VStack(alignment: .leading, spacing: 1) {
                Text(task?.title ?? "Untitled")
                    .font(FlowFont.caption.weight(.semibold))
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                    .lineLimit(1)
                Text(DurationFormatter.compact(minutes: segment.durationMinutes))
                    .font(FlowFont.durationChip)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }
            Spacer(minLength: 0)
            if segment.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .accessibilityLabel("Locked")
            }
        }
        .padding(.horizontal, FlowSpacing.s)
        .padding(.vertical, FlowSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                .fill(colour.soft)
        )
        .clipShape(RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [task?.title ?? "Untitled task", task?.durationAccessibilityLabel ?? ""]
        if let badge = segment.badgeText { parts.append(badge) }
        if segment.isLocked { parts.append("locked") }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// A fixed, externally-owned Apple Calendar event.
///
/// Deliberately muted (`FlowTheme.externalEvent`) so it never competes with a
/// Flowmap task's colour, and always reads as "not mine to move".
struct ExternalEventBlockView: View {
    @Environment(\.colorScheme) private var scheme
    let event: ExternalCalendarEvent

    var body: some View {
        HStack(spacing: FlowSpacing.xs) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FlowTheme.secondaryText(scheme))
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(FlowFont.caption.weight(.medium))
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .lineLimit(1)
                if !event.isAllDay {
                    Text(DurationFormatter.compact(minutes: event.durationMinutes))
                        .font(FlowFont.durationChip)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, FlowSpacing.s)
        .padding(.vertical, FlowSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                .fill(FlowTheme.externalEvent(scheme).opacity(0.4))
        )
        .clipShape(RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("External event, \(event.title), \(event.calendarTitle)")
    }
}

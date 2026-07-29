import SwiftData
import SwiftUI

/// The Calendar panel's first page: the selected day's segments and external
/// events as one quiet chronological list. The day itself is named by the month
/// grid's selection above, so this page carries no date header of its own.
struct CalendarDayAgendaView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \TaskSegment.startDate) private var allSegments: [TaskSegment]

    let day: Date

    private var calendar: Calendar {
        CalendarDateMath.calendar(firstWeekday: flow?.settings.firstWeekday ?? 2)
    }

    private var items: [AgendaLineItem] {
        let interval = CalendarDateMath.dayInterval(containing: day, calendar: calendar)
        let segments = allSegments
            .filter { $0.state.occupiesTimeline }
            .filter { $0.startDate < interval.end && $0.endDate > interval.start }
            .map(AgendaLineItem.segment)
        let events = (flow?.calendarService.events ?? [])
            .filter { $0.start < interval.end && $0.end > interval.start }
            .map(AgendaLineItem.event)
        return (segments + events).sorted { $0.start < $1.start }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                if items.isEmpty {
                    Text("Nothing planned.")
                        .font(FlowFont.secondary)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .padding(.vertical, FlowSpacing.xs)
                } else {
                    ForEach(items) { item in
                        CalendarAgendaRow(item: item)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.bottom, FlowSpacing.m)
        }
        .contentMargins(.bottom, FlowSpacing.floatingControlsInset, for: .scrollContent)
    }
}

// MARK: - Flat agenda row

/// Either half of a day's schedule — a Flowmap segment or an externally-owned
/// event — reduced to what a flat agenda line needs: a start time to sort by.
enum AgendaLineItem: Identifiable {
    case segment(TaskSegment)
    case event(ExternalCalendarEvent)

    var id: String {
        switch self {
        case .segment(let segment): segment.id.uuidString
        case .event(let event): event.id
        }
    }

    var start: Date {
        switch self {
        case .segment(let segment): segment.startDate
        case .event(let event): event.start
        }
    }
}

/// One line in a flat, chronological agenda: time, a coloured dot, the title,
/// and a trailing duration capsule — or "CAL" for an externally-owned event,
/// which isn't Flowmap's to report a duration for. Used beneath the month
/// grid, where the design calls for a quiet list rather than the card-style
/// blocks the timeline views draw.
struct CalendarAgendaRow: View {
    @Environment(\.colorScheme) private var scheme
    let item: AgendaLineItem

    private var title: String {
        switch item {
        case .segment(let segment): segment.task?.title ?? "Untitled"
        case .event(let event): event.title
        }
    }

    private var dotColour: Color {
        switch item {
        case .segment(let segment): (segment.task?.colour ?? .violet).base
        case .event: FlowTheme.externalEvent(scheme)
        }
    }

    private var durationMinutes: Int? {
        switch item {
        case .segment(let segment): segment.durationMinutes
        case .event: nil
        }
    }

    var body: some View {
        HStack(spacing: FlowSpacing.s) {
            Text(DurationFormatter.time(item.start))
                .font(.system(size: 13, design: .rounded).monospacedDigit())
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .frame(width: 52, alignment: .trailing)

            Circle()
                .fill(dotColour)
                .frame(width: 8, height: 8)

            Text(title)
                .font(FlowFont.body)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .lineLimit(1)

            Spacer(minLength: FlowSpacing.s)

            if let durationMinutes {
                Text(DurationFormatter.compact(minutes: durationMinutes))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .padding(.horizontal, FlowSpacing.s)
                    .padding(.vertical, FlowSpacing.xxs)
                    .background(Capsule().fill(FlowTheme.surfaceWell(scheme)))
            } else {
                Text("CAL")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch item {
        case .segment(let segment):
            let parts = [title, segment.task?.durationAccessibilityLabel ?? ""]
            return parts.filter { !$0.isEmpty }.joined(separator: ", ")
        case .event(let event):
            return "External event, \(event.title), \(event.calendarTitle)"
        }
    }
}

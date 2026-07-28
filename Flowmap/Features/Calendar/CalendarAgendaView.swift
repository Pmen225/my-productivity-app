import SwiftData
import SwiftUI

/// Agenda: a flat, scrollable list of days grouped by date, each showing its
/// scheduled segments and external events in time order. Alongside Day, this
/// is a default working view — quick to scan, unlike Month.
struct CalendarAgendaView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \TaskSegment.startDate) private var allSegments: [TaskSegment]

    let anchorDate: Date
    let dayCount: Int
    let onSelectDay: (Date) -> Void

    private var calendar: Calendar {
        CalendarDateMath.calendar(firstWeekday: flow?.settings.firstWeekday ?? 2)
    }

    /// Each day's start-of-day `Date` is the row identity, never an index, so
    /// scrolling and refreshing can never duplicate or misplace a day.
    private var days: [Date] {
        (0..<dayCount).compactMap {
            CalendarDateMath.addingDays($0, to: calendar.startOfDay(for: anchorDate), calendar: calendar)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: FlowSpacing.m, pinnedViews: [.sectionHeaders]) {
                ForEach(days, id: \.self) { day in
                    Section {
                        dayItems(for: day)
                    } header: {
                        dayHeader(day)
                    }
                }
            }
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.vertical, FlowSpacing.m)
        }
    }

    private func dayHeader(_ day: Date) -> some View {
        Button { onSelectDay(day) } label: {
            HStack(spacing: FlowSpacing.xs) {
                Text(dayHeaderLabel(day))
                    .font(FlowFont.cardTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                if calendar.isDateInToday(day) {
                    StatusIndicator(token: .clay, symbolName: "circle.fill", label: "Today")
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, FlowSpacing.xs)
            .background(FlowTheme.background(scheme))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func dayItems(for day: Date) -> some View {
        let interval = CalendarDateMath.dayInterval(containing: day, calendar: calendar)
        let events = (flow?.calendarService.events ?? [])
            .filter { $0.start < interval.end && $0.end > interval.start }
        let segments = allSegments
            .filter { $0.state.occupiesTimeline }
            .filter { $0.startDate < interval.end && $0.endDate > interval.start }
            .sorted { $0.startDate < $1.startDate }

        if events.isEmpty && segments.isEmpty {
            Text("Nothing scheduled")
                .font(FlowFont.secondary)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .padding(.vertical, FlowSpacing.xs)
        } else {
            VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                ForEach(events.sorted { $0.start < $1.start }) { event in
                    ExternalEventBlockView(event: event)
                }
                ForEach(segments) { segment in
                    TaskSegmentBlockView(segment: segment)
                }
            }
        }
    }

    private func dayHeaderLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        return formatter.string(from: date)
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
/// grid, where the design calls for a quieter list than the card-style blocks
/// `TaskSegmentBlockView`/`ExternalEventBlockView` draw elsewhere.
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

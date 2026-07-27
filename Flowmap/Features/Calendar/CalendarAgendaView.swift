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
                    StatusIndicator(token: .violet, symbolName: "circle.fill", label: "Today")
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

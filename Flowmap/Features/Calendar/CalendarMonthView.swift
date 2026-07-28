import SwiftData
import SwiftUI

/// Month view is for navigation, not dense editing: each cell shows a day
/// number, a busy dot if anything is scheduled, and — when it fits — a small
/// count. Tapping a day jumps into Day view for that date.
struct CalendarMonthView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \TaskSegment.startDate) private var allSegments: [TaskSegment]

    let anchorDate: Date
    let onSelectDay: (Date) -> Void

    private var calendar: Calendar {
        CalendarDateMath.calendar(firstWeekday: flow?.settings.firstWeekday ?? 2)
    }

    /// Cells are identified by `DayCell.id` (a start-of-day `Date`), never by
    /// array index, so navigating months can never crash or collide.
    private var cells: [CalendarDateMath.DayCell] {
        CalendarDateMath.monthGrid(containing: anchorDate, calendar: calendar)
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        let symbols = formatter.veryShortWeekdaySymbols ?? []
        guard !symbols.isEmpty else { return [] }
        let firstIndex = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(firstIndex + $0) % 7] }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: FlowSpacing.xs), count: 7)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowSpacing.m) {
                // Single-letter symbols can repeat (Tue/Thu, Sat/Sun both
                // read "T"/"S"), so the row is indexed by position, never by
                // the string itself.
                HStack(spacing: FlowSpacing.xs) {
                    ForEach(0..<weekdaySymbols.count, id: \.self) { index in
                        Text(weekdaySymbols[index].uppercased())
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .kerning(1)
                            .foregroundStyle(FlowTheme.tertiaryText(scheme))
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: columns, spacing: FlowSpacing.xs) {
                    // `cells` is recomputed fresh every render from `anchorDate`;
                    // stable date identity keeps SwiftUI's diff correct even
                    // though the whole array is replaced on every navigation.
                    ForEach(cells) { cell in
                        dayCell(cell)
                    }
                }

                agendaSection
            }
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.vertical, FlowSpacing.m)
        }
    }

    private func dayCell(_ cell: CalendarDateMath.DayCell) -> some View {
        let interval = CalendarDateMath.dayInterval(containing: cell.date, calendar: calendar)
        let busyCount = busyCount(in: interval)
        let isToday = calendar.isDateInToday(cell.date)
        // `anchorDate` is the month/day currently in focus, already passed in —
        // reusing it for the selection ring avoids a second piece of state.
        let isSelected = calendar.isDate(cell.date, inSameDayAs: anchorDate)

        return Button {
            onSelectDay(cell.date)
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: cell.date))")
                    .font(.system(size: 15, weight: isSelected || isToday ? .bold : .medium))
                    .foregroundStyle(
                        isSelected
                            ? .white
                            : isToday
                                ? FlowTheme.accent
                                : cell.isInCurrentMonth
                                    ? FlowTheme.primaryText(scheme)
                                    : FlowTheme.secondaryText(scheme).opacity(0.5)
                    )

                // One dot per busy day, never a count — a number here would
                // duplicate what the agenda list below already spells out.
                Circle()
                    .fill(busyCount > 0 ? (isSelected ? Color.white : FlowTheme.accent) : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: FlowRadius.field, style: .continuous)
                    .fill(isSelected ? FlowTheme.accent : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: cell.date, busyCount: busyCount))
    }

    /// Flowmap segments plus external events overlapping the day, de-duplicated
    /// by identity so the same item can never inflate the count twice.
    private func busyCount(in interval: DateInterval) -> Int {
        let segmentIDs = Set(
            allSegments
                .filter { $0.state.occupiesTimeline }
                .filter { $0.startDate < interval.end && $0.endDate > interval.start }
                .map(\.id)
        )
        let eventIDs = Set(
            (flow?.calendarService.events ?? [])
                .filter { $0.start < interval.end && $0.end > interval.start }
                .map(\.id)
        )
        return segmentIDs.count + eventIDs.count
    }

    private func accessibilityLabel(for date: Date, busyCount: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        let dayText = formatter.string(from: date)
        return busyCount > 0 ? "\(dayText), \(busyCount) scheduled" : dayText
    }

    // MARK: - Agenda

    /// The selected day's segments and external events, chronologically
    /// merged — mirrors what `CalendarAgendaView` shows per day, just for the
    /// one day currently in focus and without its section header.
    private var agendaItems: [AgendaLineItem] {
        let interval = CalendarDateMath.dayInterval(containing: anchorDate, calendar: calendar)
        let segments = allSegments
            .filter { $0.state.occupiesTimeline }
            .filter { $0.startDate < interval.end && $0.endDate > interval.start }
            .map(AgendaLineItem.segment)
        let events = (flow?.calendarService.events ?? [])
            .filter { $0.start < interval.end && $0.end > interval.start }
            .map(AgendaLineItem.event)
        return (segments + events).sorted { $0.start < $1.start }
    }

    @ViewBuilder
    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow("AGENDA")
            if agendaItems.isEmpty {
                Text("Nothing scheduled")
                    .font(FlowFont.secondary)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .padding(.vertical, FlowSpacing.xs)
            } else {
                ForEach(agendaItems) { item in
                    CalendarAgendaRow(item: item)
                }
            }
        }
        .padding(.top, FlowSpacing.s)
    }
}

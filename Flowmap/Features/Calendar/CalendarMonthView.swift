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
        let symbols = formatter.shortWeekdaySymbols ?? []
        guard !symbols.isEmpty else { return [] }
        let firstIndex = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(firstIndex + $0) % 7] }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: FlowSpacing.xs), count: 7)

    var body: some View {
        VStack(spacing: FlowSpacing.s) {
            HStack(spacing: FlowSpacing.xs) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol.uppercased())
                        .font(FlowFont.caption.weight(.semibold))
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
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
        }
        .padding(.horizontal, FlowSpacing.screen)
        .padding(.vertical, FlowSpacing.m)
    }

    private func dayCell(_ cell: CalendarDateMath.DayCell) -> some View {
        let interval = CalendarDateMath.dayInterval(containing: cell.date, calendar: calendar)
        let busyCount = busyCount(in: interval)
        let isToday = calendar.isDateInToday(cell.date)

        return Button {
            onSelectDay(cell.date)
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: cell.date))")
                    .font(FlowFont.secondary.weight(isToday ? .bold : .regular))
                    .foregroundStyle(
                        cell.isInCurrentMonth
                            ? FlowTheme.primaryText(scheme)
                            : FlowTheme.secondaryText(scheme).opacity(0.5)
                    )
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(isToday ? FlowTheme.accent.opacity(0.18) : Color.clear)
                    )

                // Never a count text stacked on top of a count text: one dot
                // (or a single small number) per day, so nothing can read as
                // duplicated events.
                if busyCount > 0 {
                    Text(busyCount > 9 ? "9+" : "\(busyCount)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(FlowTheme.accent)
                } else {
                    Color.clear.frame(height: 11)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, FlowSpacing.xs)
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
}

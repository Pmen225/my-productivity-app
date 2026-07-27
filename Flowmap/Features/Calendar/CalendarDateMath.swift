import Foundation

/// Pure date-grid maths for the calendar views.
///
/// Every boundary here comes from `Calendar`, never from adding a fixed
/// number of seconds — a day is not always 86,400 seconds across a
/// daylight-saving transition. Keeping that logic in one place means the
/// Day/Week/Month/Agenda views never have to reason about it themselves.
public enum CalendarDateMath {
    /// One cell in a month grid, identified by its start-of-day instant —
    /// never by array index, so navigating months never crashes or
    /// misidentifies a cell.
    public struct DayCell: Identifiable, Equatable, Sendable {
        public let date: Date
        public let isInCurrentMonth: Bool
        public var id: Date { date }
    }

    /// A `Calendar` matching the user's chosen first weekday.
    public static func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = max(1, min(7, firstWeekday))
        return calendar
    }

    /// The `[start, end)` instant range covering `date`'s calendar day.
    /// Correct across DST transitions, where a day is 23 or 25 hours.
    public static func dayInterval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86400)
    }

    /// Adds whole days using `Calendar`, never raw seconds.
    public static func addingDays(_ count: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: count, to: date) ?? date
    }

    public static func addingMonths(_ count: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .month, value: count, to: date) ?? date
    }

    /// The 7 days of the week containing `date`, respecting `firstWeekday`.
    public static func weekDays(containing date: Date, calendar: Calendar) -> [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// A complete-weeks grid for the month containing `date`. Leading and
    /// trailing days from adjacent months fill out the first/last row and are
    /// flagged `isInCurrentMonth == false` so the UI can mute them, without
    /// ever duplicating or dropping a day.
    public static func monthGrid(containing date: Date, calendar: Calendar) -> [DayCell] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        let firstOfMonth = monthInterval.start
        guard let lastOfMonth = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) else { return [] }

        let leadingWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingCount = (leadingWeekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leadingCount, to: firstOfMonth) else { return [] }

        let trailingWeekday = calendar.component(.weekday, from: lastOfMonth)
        let trailingCount = (calendar.firstWeekday + 6 - trailingWeekday + 7) % 7
        guard let gridEnd = calendar.date(byAdding: .day, value: trailingCount, to: lastOfMonth) else { return [] }

        var cells: [DayCell] = []
        var cursor = gridStart
        var safety = 0
        while cursor <= gridEnd, safety < 60 {
            let inMonth = calendar.isDate(cursor, equalTo: firstOfMonth, toGranularity: .month)
            cells.append(DayCell(date: cursor, isInCurrentMonth: inMonth))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            safety += 1
        }
        return cells
    }

    /// Rounds up to the next 5-minute boundary, matching the scheduler's grid.
    public static func snapUpToFiveMinutes(_ date: Date) -> Date {
        let interval: TimeInterval = 5 * 60
        let seconds = date.timeIntervalSinceReferenceDate
        let snapped = (seconds / interval).rounded(.up) * interval
        return Date(timeIntervalSinceReferenceDate: snapped)
    }
}

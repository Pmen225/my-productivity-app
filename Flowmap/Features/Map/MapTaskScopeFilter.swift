import Foundation

/// The date window shared by the Map + Today scope control and map-node emphasis.
///
/// The map never removes a node for being outside the window: this helper only
/// answers whether its linked task earns normal emphasis. That keeps the whole
/// tree available for navigation while making the chosen horizon readable.
enum MapTaskScopeFilter {
    static func interval(
        for scope: TodayScope,
        at referenceDate: Date,
        calendar: Calendar = .current
    ) -> DateInterval {
        let today = calendar.startOfDay(for: referenceDate)

        switch scope {
        case .day:
            let end = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            return DateInterval(start: today, end: end)
        case .week:
            let end = calendar.date(byAdding: .day, value: 7, to: today) ?? today
            return DateInterval(start: today, end: end)
        case .month:
            let start = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start ?? today
            let end = calendar.date(byAdding: .weekOfYear, value: 4, to: start) ?? start
            return DateInterval(start: start, end: end)
        }
    }

    /// With no scope, filtering is disabled and every node stays at normal
    /// emphasis. This makes ordinary map entry points behave exactly as before.
    static func shouldEmphasise(
        segmentStarts: [Date],
        scope: TodayScope?,
        at referenceDate: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let scope else { return true }
        let range = interval(for: scope, at: referenceDate, calendar: calendar)
        return segmentStarts.contains { range.contains($0) }
    }
}

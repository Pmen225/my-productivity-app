import Foundation
import Testing
@testable import Flowmap

@MainActor
struct MapTaskScopeFilterTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    @Test func dayScopeOnlyEmphasisesSegmentsStartingToday() {
        let now = date(12)
        #expect(MapTaskScopeFilter.shouldEmphasise(segmentStarts: [date(12, hour: 18)], scope: .day, at: now, calendar: calendar))
        #expect(!MapTaskScopeFilter.shouldEmphasise(segmentStarts: [date(13)], scope: .day, at: now, calendar: calendar))
    }

    @Test func weekScopeMatchesTheAgendaSevenDaysFromToday() {
        let now = date(12)
        #expect(MapTaskScopeFilter.shouldEmphasise(segmentStarts: [date(18)], scope: .week, at: now, calendar: calendar))
        #expect(!MapTaskScopeFilter.shouldEmphasise(segmentStarts: [date(19)], scope: .week, at: now, calendar: calendar))
    }

    @Test func monthScopeMatchesTheAgendaFourCalendarWeeks() {
        let now = date(12)
        #expect(MapTaskScopeFilter.shouldEmphasise(segmentStarts: [date(10)], scope: .month, at: now, calendar: calendar))
        #expect(MapTaskScopeFilter.shouldEmphasise(segmentStarts: [date(31)], scope: .month, at: now, calendar: calendar))
        #expect(!MapTaskScopeFilter.shouldEmphasise(segmentStarts: [date(9)], scope: .month, at: now, calendar: calendar))
    }

    @Test func disabledFilteringLeavesNodesAtNormalEmphasis() {
        #expect(MapTaskScopeFilter.shouldEmphasise(segmentStarts: [], scope: nil, at: date(12), calendar: calendar))
    }
}

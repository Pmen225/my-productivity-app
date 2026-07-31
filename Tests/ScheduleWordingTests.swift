import Foundation
import Testing
@testable import Flowmap

/// Pinned `now` and a fixed-time-zone calendar, so these never depend on the
/// wall clock or the machine running them.
@Suite("Schedule wording")
struct ScheduleWordingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Tuesday 4 August 2026, 08:00 UTC.
    private var now: Date {
        date(year: 2026, month: 8, day: 4, hour: 8, minute: 0)
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    @Test("A start later the same day reads Today")
    func today() {
        let start = date(year: 2026, month: 8, day: 4, hour: 9, minute: 0)
        #expect(ScheduleWording.startLabel(start, now: now, calendar: calendar) == "Today 09:00")
    }

    @Test("A start on the following calendar day reads Tomorrow")
    func tomorrow() {
        let start = date(year: 2026, month: 8, day: 5, hour: 9, minute: 0)
        #expect(ScheduleWording.startLabel(start, now: now, calendar: calendar) == "Tomorrow 09:00")
    }

    @Test("A start further out spells the weekday, day, and month")
    func laterDate() {
        // 10 August 2026 is a Monday.
        let start = date(year: 2026, month: 8, day: 10, hour: 14, minute: 30)
        #expect(ScheduleWording.startLabel(start, now: now, calendar: calendar) == "Mon 10 Aug 14:30")
    }

    @Test("A start early next year, from late this year, still resolves correctly")
    func yearBoundary() {
        // 30 December 2025 is a Tuesday; 5 January 2026 is a Monday.
        let boundaryNow = date(year: 2025, month: 12, day: 30, hour: 8, minute: 0)
        let start = date(year: 2026, month: 1, day: 5, hour: 14, minute: 30)
        #expect(ScheduleWording.startLabel(start, now: boundaryNow, calendar: calendar) == "Mon 5 Jan 14:30")
    }

    @Test("New Year's Eve into New Year's Day still reads Tomorrow")
    func yearBoundaryTomorrow() {
        let boundaryNow = date(year: 2025, month: 12, day: 31, hour: 8, minute: 0)
        let start = date(year: 2026, month: 1, day: 1, hour: 9, minute: 0)
        #expect(ScheduleWording.startLabel(start, now: boundaryNow, calendar: calendar) == "Tomorrow 09:00")
    }
}

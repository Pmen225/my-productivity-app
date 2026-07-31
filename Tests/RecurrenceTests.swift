import Foundation
import Testing
@testable import Flowmap

/// Pinned `now` and a fixed-time-zone calendar, so these never depend on the
/// wall clock or the machine running them (mirrors `ScheduleWordingTests`).
@Suite("Recurrence")
struct RecurrenceTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 9, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    // MARK: - nextDate

    @Test("Daily advances by exactly one day")
    func daily() {
        let start = date(year: 2026, month: 8, day: 4)
        let next = RecurrenceFrequency.daily.nextDate(after: start, calendar: calendar)
        #expect(next == date(year: 2026, month: 8, day: 5))
    }

    @Test("Weekdays skips the weekend — Friday rolls to Monday")
    func weekdaysSkipsWeekend() {
        // 7 August 2026 is a Friday.
        let friday = date(year: 2026, month: 8, day: 7)
        let next = RecurrenceFrequency.weekdays.nextDate(after: friday, calendar: calendar)
        #expect(next == date(year: 2026, month: 8, day: 10)) // Monday
    }

    @Test("Weekdays on an ordinary weekday just advances one day")
    func weekdaysOrdinaryDay() {
        // 4 August 2026 is a Tuesday.
        let tuesday = date(year: 2026, month: 8, day: 4)
        let next = RecurrenceFrequency.weekdays.nextDate(after: tuesday, calendar: calendar)
        #expect(next == date(year: 2026, month: 8, day: 5)) // Wednesday
    }

    @Test("Weekly advances by exactly seven days")
    func weekly() {
        let start = date(year: 2026, month: 8, day: 4)
        let next = RecurrenceFrequency.weekly.nextDate(after: start, calendar: calendar)
        #expect(next == date(year: 2026, month: 8, day: 11))
    }

    @Test("Monthly clamps 31 January to the last day of February")
    func monthlyClampsAtMonthEnd() {
        // 2026 is not a leap year, so February has 28 days.
        let jan31 = date(year: 2026, month: 1, day: 31)
        let next = RecurrenceFrequency.monthly.nextDate(after: jan31, calendar: calendar)
        #expect(next == date(year: 2026, month: 2, day: 28))
    }

    @Test("Monthly clamps 31 January to 29 February in a leap year")
    func monthlyClampsAtLeapFebruary() {
        let jan31 = date(year: 2028, month: 1, day: 31)
        let next = RecurrenceFrequency.monthly.nextDate(after: jan31, calendar: calendar)
        #expect(next == date(year: 2028, month: 2, day: 29))
    }

    @Test(".none never recurs")
    func noneNeverRecurs() {
        let start = date(year: 2026, month: 8, day: 4)
        #expect(RecurrenceFrequency.none.nextDate(after: start, calendar: calendar) == nil)
    }

    // MARK: - FlowTask.markCompleted

    @Test("Completing a non-recurring task leaves it completed, with no reopening")
    func noneCompletesNormally() {
        let task = FlowTask(title: "One-off", dueDate: date(year: 2026, month: 8, day: 4))
        let completedAt = date(year: 2026, month: 8, day: 4, hour: 10)

        task.markCompleted(at: completedAt)

        #expect(task.status == .completed)
        #expect(task.completedAt == completedAt)
        #expect(task.dueDate == date(year: 2026, month: 8, day: 4))
    }

    @Test("Completing a daily task reopens the same task for tomorrow")
    func dailyReopensForTomorrow() {
        let due = date(year: 2026, month: 8, day: 4)
        let task = FlowTask(title: "Journal", dueDate: due)
        task.recurrence = .daily
        task.hasBeenPlanned = true
        let completedAt = date(year: 2026, month: 8, day: 4, hour: 20)

        task.markCompleted(at: completedAt)

        #expect(task.status == .planned)
        #expect(task.dueDate == date(year: 2026, month: 8, day: 5))
        #expect(task.completedAt == completedAt)
        #expect(task.hasBeenPlanned)
    }

    @Test("An overdue recurring task catches up to its next future turn, not the day right after it was due")
    func catchUpSkipsPastOccurrences() {
        // Due Monday 3 Aug; completed three days late, on Thursday 6 Aug.
        let due = date(year: 2026, month: 8, day: 3)
        let task = FlowTask(title: "Weekly review", dueDate: due)
        task.recurrence = .daily
        let completedAt = date(year: 2026, month: 8, day: 6, hour: 9)

        task.markCompleted(at: completedAt)

        // Naively advancing once from `due` would land on 4 Aug — already in the
        // past relative to the completion. It must catch up to tomorrow
        // (7 Aug), not yesterday.
        #expect(task.dueDate == date(year: 2026, month: 8, day: 7))
    }

    @Test("Completing a recurring task resets every subtask")
    func recurrenceResetsSubtasks() {
        let due = date(year: 2026, month: 8, day: 4)
        let task = FlowTask(title: "Weekly review", dueDate: due)
        task.recurrence = .weekly
        let first = Subtask(title: "Check inbox", isCompleted: true, task: task)
        let second = Subtask(title: "Plan week", isCompleted: true, task: task)
        task.subtasks = [first, second]

        task.markCompleted(at: date(year: 2026, month: 8, day: 4, hour: 9))

        #expect(first.isCompleted == false)
        #expect(second.isCompleted == false)
    }
}

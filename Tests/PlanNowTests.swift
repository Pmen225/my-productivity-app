import Foundation
import Testing
@testable import Flowmap

/// `planNow` places one task and touches nothing else — the Plan page's
/// per-row action, as opposed to the whole-day plan that needs a preview.
@MainActor
struct PlanNowTests {
    @Test func itPlacesTheTaskAtTheFirstFreeMomentToday() throws {
        let world = try TestWorld()
        let now = world.date(hour: 9)
        let task = world.makeTask("Write copy", minutes: 30)

        let segment = world.service().planNow(task: task, now: now)

        #expect(segment != nil)
        #expect(segment?.startDate == now)
        #expect(segment?.durationMinutes == 30)
        #expect(task.status == .planned)
    }

    @Test func itSkipsPastWorkAlreadyOnTheDay() throws {
        let world = try TestWorld()
        let now = world.date(hour: 9)
        let taken = world.makeTask("Standup", minutes: 60)
        world.service().schedule(task: taken, at: now, minutes: 60)

        let task = world.makeTask("Write copy", minutes: 30)
        let segment = world.service().planNow(task: task, now: now)

        #expect(segment?.startDate == world.date(hour: 10))
    }

    @Test func itNeverOffersASlotInThePast() throws {
        let world = try TestWorld()
        // Workday starts at 08:00; it is already 14:00.
        let now = world.date(hour: 14)
        let task = world.makeTask("Write copy", minutes: 30)

        let segment = world.service().planNow(task: task, now: now)

        #expect(segment?.startDate == now)
    }

    @Test func aFullDayPushesTheTaskOntoTheNextOne() throws {
        let world = try TestWorld()
        let now = world.date(hour: 8)
        // 08:00–21:00 is 13 hours; fill all of it.
        let blocker = world.makeTask("All-day workshop", minutes: 13 * 60)
        world.service().schedule(task: blocker, at: now, minutes: 13 * 60)

        let task = world.makeTask("Write copy", minutes: 30)
        let segment = world.service().planNow(task: task, now: now)

        #expect(segment?.startDate == world.date(hour: 8, dayOffset: 1))
    }

    @Test func freeTimeCountsWhatIsLeftOfTheWorkingDay() throws {
        let world = try TestWorld()
        let now = world.date(hour: 9)
        // 09:00 to the 21:00 workday end is 12 hours, less an hour booked.
        let taken = world.makeTask("Standup", minutes: 60)
        world.service().schedule(task: taken, at: now, minutes: 60)

        #expect(world.service().freeMinutesRemainingToday(now: now) == 11 * 60)
    }
}

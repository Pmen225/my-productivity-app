import Foundation
import Testing
@testable import Flowmap

@Suite("Sealed today")
@MainActor
struct SealedTodayTests {
    @Test("Accepting a plan seals the day and excludes new work")
    func acceptedPlanSealsDay() throws {
        let world = try TestWorld()
        let now = world.date(hour: 9)
        let original = world.makeTask("Original", minutes: 30)
        world.makeSegment(for: original, start: now, minutes: 30)

        let service = world.service()
        service.sealPlan(for: now)
        let late = world.makeTask("Captured later", minutes: 30)
        let proposal = service.proposePlan(for: now, now: world.date(hour: 10))

        #expect(service.isPlanSealed(on: now))
        #expect(original.sealedForDay == world.calendar.startOfDay(for: now))
        #expect(!proposal.blocks.contains { $0.taskID == late.id })
    }

    @Test("Direct scheduling cannot bypass a sealed day")
    func directSchedulingIsGuarded() throws {
        let world = try TestWorld()
        let now = world.date(hour: 9)
        let original = world.makeTask("Original", minutes: 30)
        world.makeSegment(for: original, start: now, minutes: 30)
        let service = world.service()
        service.sealPlan(for: now)

        let late = world.makeTask("Assistant capture", minutes: 30)
        #expect(service.schedule(task: late, at: world.date(hour: 10)) == nil)
        #expect(world.liveSegments(of: late).isEmpty)
    }

    @Test("One completed original admits one replacement at the queue end")
    func completionOpensOneAdmission() throws {
        let world = try TestWorld()
        let now = world.date(hour: 9)
        let original = world.makeTask("Original", minutes: 30)
        let originalSegment = world.makeSegment(for: original, start: now, minutes: 30)
        let service = world.service()
        service.sealPlan(for: now)

        original.markCompleted(at: world.date(hour: 9, minute: 30))
        let replacement = world.makeTask("Replacement", minutes: 30)
        let replacementSegment = service.planNow(task: replacement, now: world.date(hour: 10))
        let second = world.makeTask("Second capture", minutes: 30)
        let secondSegment = service.planNow(task: second, now: world.date(hour: 10))

        #expect(originalSegment.state == .completed)
        #expect(replacementSegment != nil)
        #expect(replacement.admittedToSealedDay == world.calendar.startOfDay(for: now))
        #expect(replacementSegment?.startDate ?? .distantPast >= world.date(hour: 10))
        #expect(secondSegment?.startDate != nil)
        #expect(secondSegment.map { !world.calendar.isDate($0.startDate, inSameDayAs: now) } == true)
    }

    @Test("Rollover review marks unfinished work missed without carrying it")
    func rolloverRequiresReview() throws {
        let world = try TestWorld()
        let source = world.date(hour: 9)
        let original = world.makeTask("Unfinished", minutes: 30)
        let segment = world.makeSegment(for: original, start: source, minutes: 30)
        let service = world.service()
        service.sealPlan(for: source)

        let review = service.prepareRolloverReview(now: world.date(hour: 9, dayOffset: 1))
        #expect(review?.items.count == 1)
        #expect(segment.state == .missed)
        #expect(world.liveSegments(of: original).count == 0)

        #expect(service.moveRolloverTaskToTomorrow(
            taskID: original.id,
            sourceDay: source,
            now: world.date(hour: 9, dayOffset: 1)
        ))
        #expect(world.liveSegments(of: original).count == 1)
        #expect(world.calendar.isDate(
            world.liveSegments(of: original)[0].startDate,
            inSameDayAs: world.date(hour: 9, dayOffset: 1)
        ))
    }

    @Test("Backlog resolves a rollover item without leaving a scheduled block")
    func backlogRolloverTask() throws {
        let world = try TestWorld()
        let source = world.date(hour: 9)
        let task = world.makeTask("Park this", minutes: 30)
        world.makeSegment(for: task, start: source, minutes: 30)
        let service = world.service()
        service.sealPlan(for: source)
        _ = service.prepareRolloverReview(now: world.date(hour: 9, dayOffset: 1))

        #expect(service.backlogRolloverTask(taskID: task.id))
        #expect(task.status == .inbox)
        #expect(task.dueDate == nil)
        #expect(world.liveSegments(of: task).isEmpty)
    }
}

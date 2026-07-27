import Foundation
import SwiftData
import Testing
@testable import Flowmap

@Suite("Candidate ordering")
@MainActor
struct CandidateOrderingTests {
    @Test("Overdue work is offered before work due today, then flagged, then the rest")
    func urgencyOrdering() throws {
        let world = try TestWorld()
        let today = world.date(hour: 9)

        let plain = world.makeTask("Plain", sortOrder: 3)
        let flagged = world.makeTask("Flagged", sortOrder: 2, flaggedForToday: true)
        let dueToday = world.makeTask("Due today", due: world.date(hour: 17), sortOrder: 1)
        let overdue = world.makeTask("Overdue", due: world.date(hour: 12, dayOffset: -2), sortOrder: 0)

        let ordered = world.engine().candidates(
            from: [plain, flagged, dueToday, overdue],
            on: today,
            now: today
        )

        #expect(ordered.map(\.title) == ["Overdue", "Due today", "Flagged", "Plain"])
    }

    @Test("Within the same urgency group, higher priority comes first")
    func priorityOrdering() throws {
        let world = try TestWorld()
        let today = world.date(hour: 9)

        let low = world.makeTask("Low", priority: .low, sortOrder: 0)
        let high = world.makeTask("High", priority: .high, sortOrder: 1)
        let medium = world.makeTask("Medium", priority: .medium, sortOrder: 2)

        let ordered = world.engine().candidates(from: [low, high, medium], on: today, now: today)
        #expect(ordered.map(\.title) == ["High", "Medium", "Low"])
    }

    @Test("Equal priority falls back to the user's manual order")
    func manualOrderTiebreak() throws {
        let world = try TestWorld()
        let today = world.date(hour: 9)

        let third = world.makeTask("Third", sortOrder: 3)
        let first = world.makeTask("First", sortOrder: 1)
        let second = world.makeTask("Second", sortOrder: 2)

        let ordered = world.engine().candidates(from: [third, first, second], on: today, now: today)
        #expect(ordered.map(\.title) == ["First", "Second", "Third"])
    }

    @Test("Fully scheduled and closed tasks are not candidates")
    func excludesSatisfiedWork() throws {
        let world = try TestWorld()
        let today = world.date(hour: 9)

        let done = world.makeTask("Done", status: .completed)
        let cancelled = world.makeTask("Cancelled", status: .cancelled)
        let scheduled = world.makeTask("Scheduled", minutes: 30)
        world.makeSegment(for: scheduled, start: world.date(hour: 10), minutes: 30)
        let open = world.makeTask("Open")

        let ordered = world.engine().candidates(
            from: [done, cancelled, scheduled, open], on: today, now: today
        )
        #expect(ordered.map(\.title) == ["Open"])
    }
}

@Suite("Free slots and constraints")
@MainActor
struct FreeSlotTests {
    @Test("Busy intervals split the working day into the gaps between them")
    func slotsAroundBusyTime() throws {
        let world = try TestWorld()
        let day = world.date(hour: 0)

        let busy = [
            BusyInterval(start: world.date(hour: 10), end: world.date(hour: 11), kind: .externalEvent),
            BusyInterval(start: world.date(hour: 14), end: world.date(hour: 15), kind: .lockedSegment),
        ]

        let slots = world.engine().freeSlots(on: day, busy: busy)
        #expect(slots.count == 3)
        #expect(slots[0].start == world.date(hour: 8))
        #expect(slots[0].end == world.date(hour: 10))
        #expect(slots[1].start == world.date(hour: 11))
        #expect(slots[1].end == world.date(hour: 14))
        #expect(slots[2].end == world.date(hour: 21))
    }

    @Test("Nothing is offered before the notBefore floor, so replanning never targets the past")
    func honoursNotBefore() throws {
        let world = try TestWorld()
        let day = world.date(hour: 0)

        let slots = world.engine().freeSlots(on: day, busy: [], notBefore: world.date(hour: 13, minute: 3))
        #expect(slots.count == 1)
        // Snapped up to the next five-minute boundary.
        #expect(slots[0].start == world.date(hour: 13, minute: 5))
    }

    @Test("Overlapping busy intervals collapse instead of producing negative gaps")
    func mergesOverlappingBusyTime() throws {
        let world = try TestWorld()
        let day = world.date(hour: 0)

        let busy = [
            BusyInterval(start: world.date(hour: 10), end: world.date(hour: 12), kind: .externalEvent),
            BusyInterval(start: world.date(hour: 11), end: world.date(hour: 13), kind: .externalEvent),
        ]

        let slots = world.engine().freeSlots(on: day, busy: busy)
        #expect(slots.allSatisfy { $0.minutes > 0 })
        #expect(slots.contains { $0.start == world.date(hour: 13) })
    }

    @Test("A morning-only task cannot be placed in the afternoon")
    func preferredPeriodNarrowsTheSlot() throws {
        let world = try TestWorld()
        let day = world.date(hour: 0)
        let task = world.makeTask("Morning task")
        task.preferredPeriod = .morning

        let wholeDay = FreeSlot(start: world.date(hour: 8), end: world.date(hour: 21))
        let constrained = world.engine().constrain(slot: wholeDay, for: task, on: day)

        #expect(constrained?.end == world.date(hour: 12))
    }

    @Test("Earliest start and latest finish clip the usable window")
    func windowConstraints() throws {
        let world = try TestWorld()
        let day = world.date(hour: 0)
        let task = world.makeTask("Windowed")
        task.earliestStart = world.date(hour: 10)
        task.latestFinish = world.date(hour: 12)

        let wholeDay = FreeSlot(start: world.date(hour: 8), end: world.date(hour: 21))
        let constrained = world.engine().constrain(slot: wholeDay, for: task, on: day)

        #expect(constrained?.start == world.date(hour: 10))
        #expect(constrained?.end == world.date(hour: 12))
    }
}

@Suite("Auto-plan")
@MainActor
struct AutoPlanTests {
    @Test("Planning places every candidate without overlapping anything")
    func noOverlapInvariant() throws {
        let world = try TestWorld()
        let now = world.date(hour: 8)

        for index in 0..<6 {
            world.makeTask("Task \(index)", minutes: 45, sortOrder: index)
        }

        let service = world.service()
        let proposal = service.proposePlan(for: now, now: now)
        service.apply(proposal, for: now)

        #expect(world.allSegments.count == 6)
        #expect(hasNoOverlaps(world.allSegments))
    }

    @Test("External calendar events are preserved and never planned over")
    func preservesExternalEvents() throws {
        let world = try TestWorld()
        let now = world.date(hour: 8)

        let meeting = ExternalCalendarEvent(
            id: "meeting-1",
            title: "Standup",
            start: world.date(hour: 9),
            end: world.date(hour: 10),
            isAllDay: false,
            calendarIdentifier: "work",
            calendarTitle: "Work"
        )
        world.makeTask("Deep work", minutes: 120)

        let service = world.service(externalEvents: [meeting])
        let proposal = service.proposePlan(for: now, now: now)
        service.apply(proposal, for: now)

        for segment in world.allSegments {
            #expect(!segment.overlaps(start: meeting.start, end: meeting.end))
        }
    }

    @Test("Locked blocks never move, and nothing is planned on top of them")
    func locksArePreserved() throws {
        let world = try TestWorld()
        let now = world.date(hour: 8)

        let locked = world.makeTask("Locked", minutes: 60)
        let lockedSegment = world.makeSegment(
            for: locked, start: world.date(hour: 13), minutes: 60, locked: true
        )
        let originalStart = lockedSegment.startDate

        for index in 0..<5 { world.makeTask("Filler \(index)", minutes: 60, sortOrder: index) }

        let service = world.service()
        // Even an explicit full replan must leave a locked block alone.
        let proposal = service.proposePlan(for: now, now: now, replanExisting: true)
        service.apply(proposal, replanExisting: true, for: now)

        #expect(lockedSegment.startDate == originalStart)
        #expect(hasNoOverlaps(world.allSegments))
    }

    @Test("Plain Plan my day leaves existing placements where the user put them")
    func gapFillingLeavesManualBlocksAlone() throws {
        let world = try TestWorld()
        let now = world.date(hour: 8)

        let manual = world.makeTask("Manual", minutes: 60)
        let manualSegment = world.makeSegment(for: manual, start: world.date(hour: 15), minutes: 60)
        let originalStart = manualSegment.startDate

        world.makeTask("New work", minutes: 30)

        let service = world.service()
        let proposal = service.proposePlan(for: now, now: now)
        service.apply(proposal, for: now)

        #expect(manualSegment.startDate == originalStart)
    }

    @Test("A splittable task longer than any single gap is divided into valid chunks")
    func splitsAcrossGaps() throws {
        let world = try TestWorld()
        let now = world.date(hour: 8)

        // Two 60-minute gaps: 08:00–09:00 and 10:00–11:00.
        let blocker = world.makeTask("Blocker", minutes: 60)
        world.makeSegment(for: blocker, start: world.date(hour: 9), minutes: 60, locked: true)
        let blocker2 = world.makeTask("Blocker 2", minutes: 600)
        world.makeSegment(for: blocker2, start: world.date(hour: 11), minutes: 600, locked: true)

        let long = world.makeTask("Long", minutes: 120, splittable: true, minimumChunk: 30)

        let service = world.service()
        let proposal = service.proposePlan(for: now, now: now)
        service.apply(proposal, for: now)

        let chunks = world.liveSegments(of: long)
        #expect(chunks.count >= 2)
        #expect(chunks.allSatisfy { $0.durationMinutes >= 30 })
        #expect(chunks.reduce(0) { $0 + $1.durationMinutes } == 120)
        #expect(hasNoOverlaps(world.allSegments))
    }

    @Test("An unsplittable task takes a whole gap or waits for a later day")
    func unsplittableStaysWhole() throws {
        let world = try TestWorld()
        let now = world.date(hour: 8)

        let blocker = world.makeTask("Blocker", minutes: 690)
        world.makeSegment(for: blocker, start: world.date(hour: 9), minutes: 690, locked: true)

        let long = world.makeTask("Unsplittable", minutes: 120, splittable: false)

        let service = world.service()
        let proposal = service.proposePlan(for: now, now: now)
        service.apply(proposal, for: now)

        let chunks = world.liveSegments(of: long)
        #expect(chunks.count == 1)
        #expect(chunks[0].durationMinutes == 120)
        // Only an hour was free today, so it had to go to a later day.
        #expect(proposal.deferredTaskIDs.contains(long.id))
    }

    @Test("Work that cannot fit today is placed on a later day rather than dropped")
    func overflowsToTheNextDay() throws {
        let world = try TestWorld()
        let now = world.date(hour: 20)

        world.makeTask("Evening overflow", minutes: 120)

        let service = world.service()
        let proposal = service.proposePlan(for: now, now: now)
        service.apply(proposal, for: now)

        let segments = world.allSegments
        #expect(segments.count == 1)
        #expect(segments[0].startDate > now)
        #expect(!world.calendar.isDate(segments[0].startDate, inSameDayAs: now))
    }

    @Test("Running the planner twice creates no duplicate blocks")
    func replanningIsIdempotent() throws {
        let world = try TestWorld()
        let now = world.date(hour: 8)

        for index in 0..<4 { world.makeTask("Task \(index)", minutes: 30, sortOrder: index) }

        let service = world.service()
        service.apply(service.proposePlan(for: now, now: now), for: now)
        let afterFirst = world.allSegments.count

        service.apply(service.proposePlan(for: now, now: now), for: now)
        let afterSecond = world.allSegments.count

        #expect(afterFirst == 4)
        #expect(afterSecond == afterFirst)
        #expect(hasNoOverlaps(world.allSegments))
    }

    @Test("Undo puts the schedule back exactly as it was")
    func undoRestoresPreviousSchedule() throws {
        let world = try TestWorld()
        let now = world.date(hour: 8)

        world.makeTask("Planned", minutes: 30)

        let service = world.service()
        let snapshot = service.apply(service.proposePlan(for: now, now: now), for: now)
        #expect(world.allSegments.count == 1)

        service.undo(snapshot)
        #expect(world.allSegments.isEmpty)
    }
}

@Suite("Manual placement")
@MainActor
struct ManualPlacementTests {
    @Test("Dropping a task onto free time schedules it, snapped to five minutes")
    func schedulesAtDropPoint() throws {
        let world = try TestWorld()
        let task = world.makeTask("Dropped", minutes: 30)

        let service = world.service()
        let segment = service.schedule(task: task, at: world.date(hour: 10, minute: 3))

        #expect(segment != nil)
        #expect(segment?.startDate == world.date(hour: 10, minute: 5))
        #expect(task.status == .planned)
    }

    @Test("A drop onto occupied time is refused rather than allowed to overlap")
    func refusesOverlappingDrop() throws {
        let world = try TestWorld()
        let existing = world.makeTask("Existing", minutes: 60)
        world.makeSegment(for: existing, start: world.date(hour: 10), minutes: 60)

        let incoming = world.makeTask("Incoming", minutes: 30)
        let service = world.service()
        let segment = service.schedule(task: incoming, at: world.date(hour: 10, minute: 30))

        #expect(segment == nil)
        #expect(world.liveSegments(of: incoming).isEmpty)
    }

    @Test("Moving a block into a clash is refused and the block stays put")
    func refusesOverlappingMove() throws {
        let world = try TestWorld()
        let first = world.makeTask("First", minutes: 60)
        let firstSegment = world.makeSegment(for: first, start: world.date(hour: 10), minutes: 60)
        let second = world.makeTask("Second", minutes: 60)
        let secondSegment = world.makeSegment(for: second, start: world.date(hour: 12), minutes: 60)

        let service = world.service()
        let moved = service.move(segment: secondSegment, to: world.date(hour: 10, minute: 30))

        #expect(moved == false)
        #expect(secondSegment.startDate == world.date(hour: 12))
        #expect(firstSegment.startDate == world.date(hour: 10))
    }

    @Test("A locked block refuses to move")
    func lockedBlockWillNotMove() throws {
        let world = try TestWorld()
        let task = world.makeTask("Locked", minutes: 60)
        let segment = world.makeSegment(for: task, start: world.date(hour: 10), minutes: 60, locked: true)

        let service = world.service()
        #expect(service.move(segment: segment, to: world.date(hour: 14)) == false)
        #expect(segment.startDate == world.date(hour: 10))
    }
}

@Suite("Missed and unfinished work")
@MainActor
struct RequeueTests {
    @Test("A passed, unfinished block is marked missed and requeued later the same day")
    func sameDayRequeue() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30)
        let segment = world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30)

        let now = world.date(hour: 10)
        let outcomes = world.service().reconcileMissedWork(now: now)

        #expect(segment.state == .missed)
        #expect(outcomes.count == 1)

        let live = world.liveSegments(of: task)
        #expect(live.count == 1)
        // Starting exactly now is the earliest valid slot, so `>=` is correct here.
        #expect(live[0].startDate >= now)
        #expect(world.calendar.isDate(live[0].startDate, inSameDayAs: now))
        #expect(live[0].source == .carryover)
        #expect(task.carryoverCount == 1)
    }

    @Test("With no room left today the work moves to the next day, never vanishing")
    func nextDayCarryover() throws {
        let world = try TestWorld()
        let task = world.makeTask("Evening reading", minutes: 60)
        let segment = world.makeSegment(for: task, start: world.date(hour: 19), minutes: 60)

        // 20:30 leaves only 30 minutes before the 21:00 day end.
        let now = world.date(hour: 20, minute: 30)
        let outcomes = world.service().reconcileMissedWork(now: now)

        #expect(segment.state == .missed)
        let live = world.liveSegments(of: task)
        #expect(live.count == 1)
        #expect(!world.calendar.isDate(live[0].startDate, inSameDayAs: now))
        #expect(outcomes.first?.movedToAnotherDay == true)
    }

    @Test("Requeueing keeps one task identity — it never creates a second task")
    func neverDuplicatesTheTask() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30)
        world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30)

        world.service().reconcileMissedWork(now: world.date(hour: 10))

        let tasks = (try? world.context.fetch(FetchDescriptor<FlowTask>())) ?? []
        #expect(tasks.count == 1)
        #expect(tasks[0].id == task.id)
    }

    @Test("Reconciling repeatedly creates no duplicate continuation blocks")
    func reconciliationIsIdempotent() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30)
        world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30)

        let service = world.service()
        let now = world.date(hour: 10)
        service.reconcileMissedWork(now: now)
        let afterFirst = world.allSegments.count

        service.reconcileMissedWork(now: now)
        service.reconcileMissedWork(now: now)

        #expect(world.allSegments.count == afterFirst)
        #expect(world.liveSegments(of: task).count == 1)
        #expect(task.carryoverCount == 1)
    }

    @Test("A completed task's passed block closes without being requeued")
    func completedWorkIsNotRequeued() throws {
        let world = try TestWorld()
        let task = world.makeTask("Finished", minutes: 30)
        let segment = world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30)
        task.markCompleted(at: world.date(hour: 9, minute: 20))

        let outcomes = world.service().reconcileMissedWork(now: world.date(hour: 10))

        #expect(outcomes.isEmpty)
        #expect(segment.state == .completed)
    }

    @Test("A cancelled task is not requeued")
    func cancelledWorkIsNotRequeued() throws {
        let world = try TestWorld()
        let task = world.makeTask("Dropped", minutes: 30)
        world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30)
        task.markCancelled(at: world.date(hour: 9, minute: 10))

        let outcomes = world.service().reconcileMissedWork(now: world.date(hour: 10))
        #expect(outcomes.isEmpty)
    }

    @Test("A focus continuation is only ever created once for the same segment")
    func continuationIsClaimedOnce() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 60)
        let segment = world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30)

        let service = world.service()
        let now = world.date(hour: 9, minute: 30)
        let first = service.scheduleContinuation(for: task, after: segment, minutes: 30, now: now)
        let second = service.scheduleContinuation(for: task, after: segment, minutes: 30, now: now)

        #expect(first != nil)
        #expect(second == nil)
        #expect(world.allSegments.count(where: { $0.continuationOfSegmentID == segment.id }) == 1)
    }

    @Test("Work with nowhere to go returns to the Inbox instead of disappearing")
    func unplaceableWorkReturnsToInbox() throws {
        let world = try TestWorld()
        let task = world.makeTask("Impossible", minutes: 60, splittable: false)
        // A window that has already closed leaves the planner nowhere to put it.
        task.latestFinish = world.date(hour: 9)
        let segment = world.makeSegment(for: task, start: world.date(hour: 8), minutes: 60)

        let outcomes = world.service().reconcileMissedWork(now: world.date(hour: 10))

        #expect(segment.state == .missed)
        #expect(task.status == .inbox)
        #expect(outcomes.first?.failureReason != nil)
    }
}

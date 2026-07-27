import Foundation
import SwiftData
import Testing
@testable import Flowmap

@Suite("Focus timing")
@MainActor
struct FocusTimingTests {
    @Test("Remaining time is derived from timestamps, so a killed app loses nothing")
    func remainingDerivesFromTimestamps() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30)
        let start = world.date(hour: 9)
        let session = FocusSession(task: task, plannedSeconds: 1800, startedAt: start)
        world.context.insert(session)

        // Nothing decrements in memory — the same object answers correctly for
        // any moment, including one after a relaunch.
        #expect(session.remainingSeconds(at: start) == 1800)
        #expect(session.remainingSeconds(at: start.addingTimeInterval(600)) == 1200)
        #expect(session.remainingSeconds(at: start.addingTimeInterval(1800)) == 0)
        // Never negative, however long the app was gone.
        #expect(session.remainingSeconds(at: start.addingTimeInterval(99_999)) == 0)
    }

    @Test("A paused timer freezes and resumes without jumping")
    func pauseResumeAccounting() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30)
        let start = world.date(hour: 9)
        let session = FocusSession(task: task, plannedSeconds: 1800, startedAt: start)
        world.context.insert(session)

        // Work for 5 minutes, then pause.
        let pauseMoment = start.addingTimeInterval(300)
        session.pause(at: pauseMoment)
        #expect(session.remainingSeconds(at: pauseMoment) == 1500)

        // Ten minutes pass while paused: the countdown must not move.
        let stillPaused = pauseMoment.addingTimeInterval(600)
        #expect(session.remainingSeconds(at: stillPaused) == 1500)

        // Resuming continues from exactly where it stopped.
        session.resume(at: stillPaused)
        #expect(session.remainingSeconds(at: stillPaused) == 1500)
        #expect(session.remainingSeconds(at: stillPaused.addingTimeInterval(60)) == 1440)
    }

    @Test("Repeated pauses accumulate correctly")
    func multiplePauses() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30)
        let start = world.date(hour: 9)
        let session = FocusSession(task: task, plannedSeconds: 1800, startedAt: start)
        world.context.insert(session)

        session.pause(at: start.addingTimeInterval(60))
        session.resume(at: start.addingTimeInterval(160))   // paused 100s
        session.pause(at: start.addingTimeInterval(260))
        session.resume(at: start.addingTimeInterval(460))   // paused a further 200s

        #expect(session.accumulatedPausedSeconds == 300)
        // 460s of wall clock minus 300s paused is 160s of real work.
        #expect(session.elapsedSeconds(at: start.addingTimeInterval(460)) == 160)
    }

    @Test("Pausing twice in a row does not double-count")
    func pauseIsIdempotent() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30)
        let start = world.date(hour: 9)
        let session = FocusSession(task: task, plannedSeconds: 1800, startedAt: start)
        world.context.insert(session)

        session.pause(at: start.addingTimeInterval(60))
        session.pause(at: start.addingTimeInterval(120))
        session.resume(at: start.addingTimeInterval(160))

        #expect(session.accumulatedPausedSeconds == 100)
    }

    @Test("The elapsed transition can only ever be claimed once")
    func transitionClaimedExactlyOnce() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30)
        let session = FocusSession(task: task, plannedSeconds: 1800, startedAt: world.date(hour: 9))
        world.context.insert(session)

        #expect(session.claimTransition() == true)
        #expect(session.claimTransition() == false)
        #expect(session.claimTransition() == false)
    }

    @Test("Finishing a session is idempotent and freezes the actual time")
    func finishIsIdempotent() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30)
        let start = world.date(hour: 9)
        let session = FocusSession(task: task, plannedSeconds: 1800, startedAt: start)
        world.context.insert(session)

        session.finish(outcome: .completed, at: start.addingTimeInterval(900))
        let recorded = session.actualSeconds

        session.finish(outcome: .abandoned, at: start.addingTimeInterval(1800))
        #expect(session.outcome == .completed)
        #expect(session.actualSeconds == recorded)
        #expect(recorded == 900)
    }
}

@Suite("Focus engine behaviour")
@MainActor
struct FocusEngineTests {
    private func engine(_ world: TestWorld) -> FocusEngine {
        FocusEngine(context: world.context, settings: world.settings, calendar: world.calendar)
    }

    @Test("Time running out on an unfinished task creates exactly one continuation")
    func elapsedCreatesOneContinuation() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 60)
        let segment = world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30)

        let focus = engine(world)
        _ = focus.start(segment: segment, now: world.date(hour: 9))

        let after = world.date(hour: 9, minute: 31)
        focus.processElapsedSessionIfNeeded(now: after)
        // A second pass must not create another block.
        focus.processElapsedSessionIfNeeded(now: after)

        let continuations = world.allSegments.filter { $0.isContinuation }
        #expect(continuations.count == 1)
        #expect(segment.state == .elapsed)
    }

    @Test("A finished task is not given a continuation")
    func completedTaskIsNotContinued() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30)
        let segment = world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30)

        let focus = engine(world)
        _ = focus.start(segment: segment, now: world.date(hour: 9))
        focus.completeCurrentTask(now: world.date(hour: 9, minute: 20))

        #expect(task.status == .completed)
        #expect(world.allSegments.filter { $0.isContinuation }.isEmpty)
    }

    @Test("Completing a task records the time actually worked")
    func completionRecordsActualMinutes() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30)
        let segment = world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30)

        let focus = engine(world)
        _ = focus.start(segment: segment, now: world.date(hour: 9))
        focus.completeCurrentTask(now: world.date(hour: 9, minute: 20))

        #expect(task.actualMinutes == 20)
    }

    @Test("Skipping requeues the remaining time rather than dropping it")
    func skipRequeuesRemainder() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 60)
        let segment = world.makeSegment(for: task, start: world.date(hour: 9), minutes: 60)

        let focus = engine(world)
        _ = focus.start(segment: segment, now: world.date(hour: 9))
        focus.skipCurrentTask(now: world.date(hour: 9, minute: 15))

        #expect(task.status != .completed)
        #expect(world.allSegments.contains { $0.isContinuation })
    }

    @Test("Starting a second task closes the first session cleanly")
    func startingAnotherTaskClosesTheLast() throws {
        let world = try TestWorld()
        let first = world.makeTask("First", minutes: 30)
        let second = world.makeTask("Second", minutes: 30)
        let firstSegment = world.makeSegment(for: first, start: world.date(hour: 9), minutes: 30)
        let secondSegment = world.makeSegment(for: second, start: world.date(hour: 10), minutes: 30)

        let focus = engine(world)
        let firstSession = focus.start(segment: firstSegment, now: world.date(hour: 9))
        _ = focus.start(segment: secondSegment, now: world.date(hour: 9, minute: 10))

        #expect(firstSession?.outcome != .running)
        #expect(focus.activeSession?.task?.id == second.id)
    }

    @Test("A running session is recovered after a relaunch")
    func recoversRunningSessionOnLaunch() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30)
        let segment = world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30)

        let first = engine(world)
        _ = first.start(segment: segment, now: world.date(hour: 9))

        // A brand new engine, as if the process had died and come back.
        let recovered = FocusEngine(context: world.context, settings: world.settings, calendar: world.calendar)
        #expect(recovered.activeSession != nil)
        #expect(recovered.activeSession?.task?.id == task.id)
    }

    @Test("Today's queue is ordered by start time and excludes closed work")
    func queueOrdering() throws {
        let world = try TestWorld()
        let late = world.makeTask("Late", minutes: 30)
        let early = world.makeTask("Early", minutes: 30)
        let done = world.makeTask("Done", minutes: 30)

        world.makeSegment(for: late, start: world.date(hour: 14), minutes: 30)
        world.makeSegment(for: early, start: world.date(hour: 9), minutes: 30)
        world.makeSegment(for: done, start: world.date(hour: 11), minutes: 30)
        done.markCompleted(at: world.date(hour: 11, minute: 10))

        let queue = engine(world).queue(for: world.date(hour: 8))
        #expect(queue.compactMap { $0.task?.title } == ["Early", "Late"])
    }
}

@Suite("Focus wheel geometry")
struct FocusWheelGeometryTests {
    @Test("The active task sits at the bottom in every visibility mode")
    func activeTaskIsAlwaysAtTheBottom() {
        for visibility in WheelVisibility.allCases {
            let count = FocusWheelGeometry.visibleCount(for: visibility, queueCount: 8)
            let angle = FocusWheelGeometry.centreAngle(index: 0, visibleCount: count)
            #expect(angle == FocusWheelGeometry.bottomAngle)
        }
    }

    @Test("Upcoming tasks sit ahead of the bottom, so they arrive turning clockwise")
    func upcomingTasksApproachClockwise() {
        let count = 4
        let active = FocusWheelGeometry.centreAngle(index: 0, visibleCount: count)
        let next = FocusWheelGeometry.centreAngle(index: 1, visibleCount: count)
        // Increasing angle is clockwise, so the next task must start at a lower
        // angle and travel up to the bottom.
        #expect(next < active)
        #expect(active - next == FocusWheelGeometry.sweep(visibleCount: count))
    }

    @Test("Segments divide the circle exactly, with no gap or overlap")
    func segmentsTileTheCircle() {
        for count in 1...8 {
            let sweep = FocusWheelGeometry.sweep(visibleCount: count)
            #expect(abs(sweep * Double(count) - 360) < 0.0001)

            let first = FocusWheelGeometry.span(index: 0, visibleCount: count)
            let second = FocusWheelGeometry.span(index: 1, visibleCount: count)
            // The next segment ends exactly where the active one begins.
            #expect(abs(second.end - first.start) < 0.0001)
        }
    }

    @Test("The active task's label is horizontal, because it sits at the bottom")
    func activeLabelIsUpright() {
        #expect(FocusWheelGeometry.labelRotation(index: 0, visibleCount: 3) == 0)
    }

    @Test("Visibility never asks for more segments than there are tasks")
    func visibilityClampsToQueue() {
        #expect(FocusWheelGeometry.visibleCount(for: .three, queueCount: 2) == 2)
        #expect(FocusWheelGeometry.visibleCount(for: .all, queueCount: 5) == 5)
        #expect(FocusWheelGeometry.visibleCount(for: .two, queueCount: 9) == 2)
        // An empty queue still draws one ring rather than dividing by zero.
        #expect(FocusWheelGeometry.visibleCount(for: .all, queueCount: 0) == 1)
    }
}

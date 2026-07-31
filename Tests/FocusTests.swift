import CoreGraphics
import Foundation
import SwiftData
import Testing
#if canImport(UIKit)
import UIKit
#endif
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

    @Test("Improve later parks one follow-up on tomorrow, never today")
    func improveLaterParksTomorrowFollowUp() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30, priority: .high)
        let segment = world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30)

        let focus = engine(world)
        _ = focus.start(segment: segment, now: world.date(hour: 9))
        let finishedAt = world.date(hour: 9, minute: 20)
        focus.completeCurrentTask(now: finishedAt)

        #expect(focus.pendingTransition?.improvableTaskID == task.id)
        let followUp = focus.parkImprovement(for: task.id, now: finishedAt)
        #expect(followUp?.title == "Improve later · Reading")
        #expect(followUp?.details == "Follow-up to Reading")
        #expect(followUp?.status == .planned)
        #expect(followUp?.dueDate.map { world.calendar.isDate($0, inSameDayAs: world.date(hour: 9, dayOffset: 1)) } == true)
        #expect(followUp?.liveSegments.isEmpty == true)
        #expect(focus.pendingTransition == nil)

        let secondTap = focus.parkImprovement(for: task.id, now: finishedAt)
        #expect(secondTap?.id == followUp?.id)
        let allTasks = (try? world.context.fetch(FetchDescriptor<FlowTask>())) ?? []
        #expect(allTasks.count == 2)
    }

    @Test("Completing the final active checklist item follows the normal focus completion path")
    func finalChecklistItemCompletesActiveFocusTask() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30, planned: true)
        let first = Subtask(title: "Choose chapter", task: task)
        let second = Subtask(title: "Read notes", task: task)
        world.context.insert(first)
        world.context.insert(second)
        try world.context.save()

        let focus = engine(world)
        _ = focus.start(task: task, now: world.date(hour: 9))
        let gamification = GamificationService(
            context: world.context,
            settings: world.settings,
            onChecklistCompleted: { completedTask in
                focus.completeIfActive(task: completedTask, now: world.date(hour: 9, minute: 20))
            }
        )

        gamification.toggleSubtask(first)
        #expect(focus.activeSession?.task?.id == task.id)
        #expect(task.status != .completed)

        gamification.toggleSubtask(second)
        #expect(focus.activeSession == nil)
        #expect(task.status == .completed)
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

@Suite("Compulsory planning gate")
@MainActor
struct FocusGateTests {
    private func engine(_ world: TestWorld) -> FocusEngine {
        FocusEngine(context: world.context, settings: world.settings, calendar: world.calendar)
    }

    @Test("A never-planned task opens the gate instead of starting")
    func neverPlannedOpensGate() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30, planned: false)
        let segment = world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30)
        let focus = engine(world)

        let session = focus.start(segment: segment, now: world.date(hour: 9))

        #expect(session == nil)
        #expect(focus.activeSession == nil)
        #expect(focus.pendingGate?.kind == .planGate)
        #expect(focus.pendingGate?.task.id == task.id)
    }

    @Test("A task with no subtasks cannot start")
    func noSubtasksBlocksStart() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30, planned: false)
        let segment = world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30)
        let focus = engine(world)

        _ = focus.start(segment: segment, now: world.date(hour: 9))
        #expect(focus.pendingGate != nil)

        // No subtasks yet: the gate does not satisfy.
        let blocked = focus.resolveGate(now: world.date(hour: 9))
        #expect(blocked == nil)
        #expect(focus.activeSession == nil)
        #expect(focus.pendingGate != nil) // still blocked, not silently cleared
        #expect(task.hasBeenPlanned == false)

        // Adding a subtask resolves the same gate and starts the clock.
        let subtask = Subtask(title: "Read 10 pages", task: task)
        world.context.insert(subtask)
        try world.context.save()

        let started = focus.resolveGate(now: world.date(hour: 9))
        #expect(started != nil)
        #expect(task.hasBeenPlanned == true)
        #expect(focus.pendingGate == nil)
    }

    @Test("A fully ticked checklist cannot pass the plan gate")
    func completedChecklistBlocksStart() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30, planned: false)
        let subtask = Subtask(title: "Read chapter", task: task)
        subtask.isCompleted = true
        world.context.insert(subtask)
        try world.context.save()
        let focus = engine(world)

        _ = focus.start(task: task, now: world.date(hour: 9))
        let blocked = focus.resolveGate(now: world.date(hour: 9))

        #expect(blocked == nil)
        #expect(focus.activeSession == nil)
        #expect(focus.pendingGate?.task.id == task.id)
        #expect(task.hasBeenPlanned == false)
    }

    @Test("A planned task returning via a continuation gets clock-in, not the gate")
    func plannedTaskGetsClockIn() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30, planned: true)
        let segment = world.makeSegment(
            for: task, start: world.date(hour: 9), minutes: 30, source: .focusContinuation
        )
        let focus = engine(world)

        let session = focus.start(segment: segment, now: world.date(hour: 9))

        #expect(session == nil)
        #expect(focus.pendingGate?.kind == .clockIn)

        let resolved = focus.resolveGate(now: world.date(hour: 9))
        #expect(resolved != nil)
        #expect(focus.activeSession?.task?.id == task.id)
    }

    @Test("The gate does not fire twice for the same task")
    func gateDoesNotRefireForSameTask() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reading", minutes: 30, planned: false)
        let segment = world.makeSegment(for: task, start: world.date(hour: 9), minutes: 30)
        let focus = engine(world)

        _ = focus.start(segment: segment, now: world.date(hour: 9))
        #expect(focus.pendingGate?.kind == .planGate)

        let subtask = Subtask(title: "Read until done", task: task)
        world.context.insert(subtask)
        try world.context.save()

        _ = focus.resolveGate(now: world.date(hour: 9))
        #expect(focus.activeSession != nil)

        // Finish this run, then start a fresh (non-continuation) segment for
        // the same, now-planned task — it must not re-open the gate.
        focus.completeCurrentTask(now: world.date(hour: 9, minute: 20))
        let second = world.makeSegment(for: task, start: world.date(hour: 10), minutes: 30)
        let resumed = focus.start(segment: second, now: world.date(hour: 10))

        #expect(resumed != nil)
        #expect(focus.pendingGate == nil)
    }
}

@Suite("Focus wheel geometry")
struct FocusWheelGeometryTests {
    @Test("Close views keep the original bowl and zoom by radius")
    func closeModesUseOriginalBowlZoom() {
        let width: CGFloat = 375
        let one = FocusWheelGeometry.bowlTargetRadius(forWidth: width, visibility: .one)
        let two = FocusWheelGeometry.bowlTargetRadius(forWidth: width, visibility: .two)
        let three = FocusWheelGeometry.bowlTargetRadius(forWidth: width, visibility: .three)

        #expect(one > two)
        #expect(two > three)
        #expect(FocusWheelGeometry.bowlTargetRadiusFraction(for: .one) == 1150.0 / 375.0)
        #expect(FocusWheelGeometry.bowlTargetRadiusFraction(for: .two) == 680.0 / 375.0)
        #expect(FocusWheelGeometry.bowlTargetRadiusFraction(for: .three) == 500.0 / 375.0)
    }

    @Test("The original bowl window stays centred on the fixed pointer")
    func bowlWindowStaysCentredOnPointer() {
        let width: CGFloat = 375
        for visibility in [WheelVisibility.fiveMinute, .one, .two, .three] {
            let radius = FocusWheelGeometry.bowlTargetRadius(forWidth: width, visibility: visibility)
            let window = FocusWheelGeometry.bowlVisibleWindow(radius: radius, width: width)
            #expect(abs((window.min + window.max) / 2 - FocusWheelGeometry.bottomAngle) < 0.0001)
        }
    }

    @Test("Visibility never asks for more segments than there are tasks")
    func visibilityClampsToQueue() {
        #expect(FocusWheelGeometry.visibleCount(for: .three, queueCount: 2) == 2)
        #expect(FocusWheelGeometry.visibleCount(for: .all, queueCount: 5) == 5)
        #expect(FocusWheelGeometry.visibleCount(for: .two, queueCount: 9) == 2)
        // An empty queue still draws one ring rather than dividing by zero.
        #expect(FocusWheelGeometry.visibleCount(for: .all, queueCount: 0) == 1)
    }

    @Test("Close carousel views divide the ring into the requested visible blocks")
    func carouselSlicesMatchZoom() {
        let durations = [30, 20, 15]

        for visibility in [WheelVisibility.one, .two, .three] {
            let count = FocusWheelGeometry.visibleCount(
                for: visibility,
                queueCount: durations.count
            )
            let spans = (0..<count).map {
                FocusWheelGeometry.carouselSpan(
                    index: $0,
                    visibility: visibility,
                    durations: durations,
                    rotation: 0
                )
            }
            let widths = spans.map { $0.end - $0.start }

            #expect(widths.allSatisfy { $0 > 0 })
            if visibility == .one {
                #expect(abs(widths[0] - 300) < 0.0001)
            } else {
                #expect(abs(widths.reduce(0, +) - 360) < 0.0001)
            }
        }
    }

    @Test("Carousel rotation advances every slice clockwise by one shared angle")
    func carouselRotationIsSharedAndClockwise() {
        let durations = [30, 20, 15]
        let before = FocusWheelGeometry.carouselSpan(
            index: 0,
            visibility: .two,
            durations: durations,
            rotation: 0
        )
        let after = FocusWheelGeometry.carouselSpan(
            index: 0,
            visibility: .two,
            durations: durations,
            rotation: 18
        )

        #expect(abs((after.start - before.start) - 18) < 0.0001)
        #expect(abs((after.end - before.end) - 18) < 0.0001)
    }

    @Test("Carousel ruler counts down from full duration on the left to zero on the right")
    func carouselRulerCountsDownLeftToRight() {
        let active = FocusWheelGeometry.carouselSpan(
            index: 0,
            visibility: .two,
            durations: [30, 20],
            rotation: 0
        )
        let full = FocusWheelGeometry.carouselRulerAngle(
            minutesRemaining: 30,
            totalMinutes: 30,
            span: active
        )
        let zero = FocusWheelGeometry.carouselRulerAngle(
            minutesRemaining: 0,
            totalMinutes: 30,
            span: active
        )

        #expect(abs(full - active.end) < 0.0001)
        #expect(abs(zero - active.start) < 0.0001)

        let centre = CGPoint(x: 100, y: 100)
        let fullPoint = FocusWheelGeometry.point(centre: centre, radius: 50, angle: full)
        let zeroPoint = FocusWheelGeometry.point(centre: centre, radius: 50, angle: zero)
        #expect(fullPoint.x < centre.x)
        #expect(zeroPoint.x > centre.x)
    }

    @Test("A full-ring carousel keeps a distinct inner ruler arc")
    func fullRingRulerKeepsCountdownEnds() {
        let full = FocusWheelGeometry.carouselSpan(
            index: 0,
            visibility: .all,
            durations: [30],
            rotation: 0
        )
        let ruler = FocusWheelGeometry.carouselRulerSpan(activeSpan: full)

        #expect(ruler.end - ruler.start == 300)
        #expect(FocusWheelGeometry.carouselRulerAngle(
            minutesRemaining: 30,
            totalMinutes: 30,
            span: ruler
        ) == ruler.end)
        #expect(FocusWheelGeometry.carouselRulerAngle(
            minutesRemaining: 0,
            totalMinutes: 30,
            span: ruler
        ) == ruler.start)
    }

    @Test("A narrow overview slice widens its inner ruler instead of crowding labels")
    func narrowCarouselRulerGetsReadableArc() {
        let ruler = FocusWheelGeometry.carouselRulerSpan(activeSpan: (start: 70, end: 110))
        #expect(abs((ruler.end - ruler.start) - 180) < 0.0001)
        #expect(abs((ruler.start + ruler.end) / 2 - 90) < 0.0001)
    }

    @Test("The countdown ruler stays on the fixed lower pointer track")
    func carouselRulerDoesNotFollowRotatingWedge() {
        let ruler = FocusWheelGeometry.carouselRulerSpan(activeSpan: (start: 210, end: 390))
        #expect(abs(ruler.start - 0) < 0.0001)
        #expect(abs(ruler.end - 180) < 0.0001)

        let full = FocusWheelGeometry.carouselRulerAngle(
            minutesRemaining: 30,
            totalMinutes: 30,
            span: ruler
        )
        let zero = FocusWheelGeometry.carouselRulerAngle(
            minutesRemaining: 0,
            totalMinutes: 30,
            span: ruler
        )
        let centre = CGPoint(x: 100, y: 100)
        #expect(FocusWheelGeometry.point(centre: centre, radius: 50, angle: full).x < centre.x)
        #expect(FocusWheelGeometry.point(centre: centre, radius: 50, angle: zero).x > centre.x)
    }

    @Test("Carousel ruler keeps one-minute ticks and bends labels tangentially")
    func carouselRulerCadenceAndCurve() {
        #expect(FocusWheelGeometry.carouselRulerTickStep(totalMinutes: 30) == 1)
        #expect(FocusWheelGeometry.carouselRulerTickStep(totalMinutes: 120) == 1)
        #expect(FocusWheelGeometry.carouselRulerMajorStep(totalMinutes: 30) == 5)
        #expect(FocusWheelGeometry.carouselRulerMajorStep(totalMinutes: 120) == 10)

        // Tangents at the cardinal points: horizontal at top/bottom and
        // vertical at either side. This is the curved-text invariant.
        #expect(abs(FocusWheelGeometry.carouselRulerLabelRotation(angle: 0) - 90) < 0.0001)
        #expect(abs(FocusWheelGeometry.carouselRulerLabelRotation(angle: 90)) < 0.0001)
        #expect(abs(FocusWheelGeometry.carouselRulerLabelRotation(angle: 180) + 90) < 0.0001)
        #expect(abs(FocusWheelGeometry.carouselRulerLabelRotation(angle: 270)) < 0.0001)
    }

    @Test("Overview spans divide the full circle proportionally to duration")
    func overviewSpansSumFullCircle() {
        let durations = [30, 60, 10, 20]
        let total = Double(durations.reduce(0, +))

        var summedSpan = 0.0
        for index in durations.indices {
            let span = FocusWheelGeometry.overviewSpan(index: index, durations: durations)
            let width = span.end - span.start
            summedSpan += width
            // Each item's own share matches its proportion of total duration.
            let expected = 360 * Double(durations[index]) / total
            #expect(abs(width - expected) < 0.0001)
        }
        #expect(abs(summedSpan - 360) < 0.0001)
    }

    @Test("Overview segments earn a title only above the 26° threshold")
    func overviewLabelTierByThreshold() {
        // Above the threshold: both title and duration tiers show.
        #expect(FocusWheelGeometry.overviewShowsTitle(spanDegrees: 27) == true)
        // At or below the threshold: title is demoted, duration-only remains.
        #expect(FocusWheelGeometry.overviewShowsTitle(spanDegrees: 26) == false)
        #expect(FocusWheelGeometry.overviewShowsTitle(spanDegrees: 10) == false)
    }

    @Test("The ruler counts minutes remaining: full duration on the left, zero on the right")
    func rulerCountsMinutesRemaining() {
        let halfAngle = 40.0
        let totalMinutes = 45
        let span = FocusWheelGeometry.dialActiveSpan(halfAngle: halfAngle)

        let fullDurationAngle = FocusWheelGeometry.dialTickAngle(minutesRemaining: totalMinutes, totalMinutes: totalMinutes, halfAngle: halfAngle)
        let zeroAngle = FocusWheelGeometry.dialTickAngle(minutesRemaining: 0, totalMinutes: totalMinutes, halfAngle: halfAngle)

        // The full duration sits at the span's own LEFT end, zero at its RIGHT end.
        #expect(abs(fullDurationAngle - span.end) < 0.0001)
        #expect(abs(zeroAngle - span.start) < 0.0001)

        // Verified via actual point geometry, not by eye: in screen space
        // (0°=east, 90°=south) an angle past 90° renders left of centre, and
        // one short of 90° renders right of centre.
        let centre = CGPoint(x: 100, y: 100)
        let fullDurationPoint = FocusWheelGeometry.point(centre: centre, radius: 50, angle: fullDurationAngle)
        let zeroPoint = FocusWheelGeometry.point(centre: centre, radius: 50, angle: zeroAngle)
        #expect(fullDurationPoint.x < centre.x)
        #expect(zeroPoint.x > centre.x)
    }

    @Test("The live ruler follows the task clock and counts down left to right")
    func liveRulerUsesTaskTimeAxis() {
        let start = 600.0
        let now = 615.0
        let full = FocusWheelGeometry.bowlRulerAngle(
            elapsedMinutes: 0,
            activeStartMinutes: start,
            nowMinutes: now
        )
        let zero = FocusWheelGeometry.bowlRulerAngle(
            elapsedMinutes: 30,
            activeStartMinutes: start,
            nowMinutes: now
        )
        #expect(full > FocusWheelGeometry.bottomAngle)
        #expect(zero < FocusWheelGeometry.bottomAngle)
        #expect(FocusWheelGeometry.bowlRulerRemaining(elapsedMinutes: 0, totalMinutes: 30) == 30)
        #expect(FocusWheelGeometry.bowlRulerRemaining(elapsedMinutes: 30, totalMinutes: 30) == 0)
    }

    @Test("Ruler cadence follows the source zoom radii")
    func rulerCadenceMatchesZoom() {
        #expect(FocusWheelGeometry.bowlRulerMajorStep(radius: 9_311) == 1)
        #expect(FocusWheelGeometry.bowlRulerSubdivisions(radius: 9_311) == 6)
        #expect(FocusWheelGeometry.bowlRulerMajorStep(radius: 1_150) == 5)
        #expect(FocusWheelGeometry.bowlRulerMajorStep(radius: 680) == 10)
        #expect(FocusWheelGeometry.bowlRulerMajorStep(radius: 500) == 15)
    }

    @Test("Overview labels disappear once a wedge is too narrow to hold one, rather than overlapping its neighbour")
    func overviewHidesLabelWhenArcTooShort() {
        let labelRadius: CGFloat = 100
        let threshold = FocusWheelGeometry.overviewMinLabelArcLength

        // Just under the threshold: no label at all.
        let tinySpan = Double((threshold - 1) / labelRadius) * 180 / .pi
        #expect(FocusWheelGeometry.overviewShowsLabel(spanDegrees: tinySpan, labelRadius: labelRadius) == false)

        // Comfortably over it: the label is drawn.
        let roomySpan = Double((threshold + 10) / labelRadius) * 180 / .pi
        #expect(FocusWheelGeometry.overviewShowsLabel(spanDegrees: roomySpan, labelRadius: labelRadius) == true)

        #if canImport(UIKit)
        // The threshold must not be a guess: it has to hold the widest
        // realistic compact-duration string ("88M", two digits plus unit)
        // rendered at the ruler's own system font, or narrow wedges would
        // still clip into their neighbours.
        // Pinned to 11pt — `.caption2` at the default Dynamic Type size —
        // rather than `UIFont.preferredFont`, whose size follows the host
        // simulator's text-size setting and would fail this assertion for a
        // reason that has nothing to do with the code under test. The
        // threshold's behaviour at accessibility text sizes is a known gap,
        // recorded in the handover rather than hidden behind a flaky test.
        let base = UIFont.systemFont(ofSize: 11, weight: .bold)
        let rounded = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let font = UIFont(descriptor: rounded, size: 11)
        let measuredWidth = NSAttributedString(string: "88M", attributes: [.font: font]).size().width
        #expect(threshold >= CGFloat(measuredWidth))
        #endif
    }

    @Test("A finished segment renders left of the pointer; one still ahead renders right")
    func pastAndFutureSegmentsSitOnOppositeSides() {
        let width: CGFloat = 375
        let radius = FocusWheelGeometry.bowlTargetRadius(forWidth: width, visibility: .fiveMinute)
        let centre = CGPoint(x: 100, y: 100)
        let now = 600.0 // 10:00

        // Already finished: 09:00-09:30, well before "now".
        let past = FocusWheelGeometry.bowlSegmentSpan(start: 540, duration: 30, nowMinutes: now)
        let pastMid = (past.start + past.end) / 2
        let pastPoint = FocusWheelGeometry.point(centre: centre, radius: radius, angle: pastMid)
        #expect(pastPoint.x < centre.x)

        // Still ahead: 11:00-11:30.
        let future = FocusWheelGeometry.bowlSegmentSpan(start: 660, duration: 30, nowMinutes: now)
        let futureMid = (future.start + future.end) / 2
        let futurePoint = FocusWheelGeometry.point(centre: centre, radius: radius, angle: futureMid)
        #expect(futurePoint.x > centre.x)
    }

    @Test("The carousel advances clockwise as the clock moves")
    func carouselAdvancesClockwise() {
        let before = FocusWheelGeometry.bowlSegmentSpan(start: 600, duration: 30, nowMinutes: 600)
        let after = FocusWheelGeometry.bowlSegmentSpan(start: 600, duration: 30, nowMinutes: 601)

        #expect((after.start + after.end) / 2 > (before.start + before.end) / 2)

        let centre = CGPoint(x: 100, y: 100)
        let beforePoint = FocusWheelGeometry.point(
            centre: centre,
            radius: 80,
            angle: (before.start + before.end) / 2
        )
        let afterPoint = FocusWheelGeometry.point(
            centre: centre,
            radius: 80,
            angle: (after.start + after.end) / 2
        )
        #expect(afterPoint.x < beforePoint.x)
    }

    @Test("The overview countdown ruler runs from full duration on the left to zero on the right")
    func overviewRulerCountsDownLeftToRight() {
        #expect(FocusWheelGeometry.overviewRulerAngle(minutesRemaining: 30, totalMinutes: 30) == 180)
        #expect(FocusWheelGeometry.overviewRulerAngle(minutesRemaining: 0, totalMinutes: 30) == 360)
        #expect(FocusWheelGeometry.overviewRulerTickCount(totalMinutes: 4) == 6)
        #expect(FocusWheelGeometry.overviewRulerTickCount(totalMinutes: 45) == 30)

        // The overview shares the close dial's fixed lower track, so its
        // endpoint numerals must follow the circular tangent too.
        let fullAngle = FocusWheelGeometry.overviewRulerAngle(minutesRemaining: 30, totalMinutes: 30)
        let zeroAngle = FocusWheelGeometry.overviewRulerAngle(minutesRemaining: 0, totalMinutes: 30)
        #expect(abs(FocusWheelGeometry.carouselRulerLabelRotation(angle: fullAngle) + 90) < 0.0001)
        #expect(abs(FocusWheelGeometry.carouselRulerLabelRotation(angle: zeroAngle) - 90) < 0.0001)
    }

    @Test("A gap under 9° visible span gets no FREE label; one over it does")
    func gapFreeLabelThreshold() {
        let width: CGFloat = 375
        let radius: CGFloat = width * 2
        let window = FocusWheelGeometry.bowlVisibleWindow(radius: radius, width: width)
        let now = 600.0

        let narrowGap = FocusWheelGeometry.bowlSegmentSpan(start: 595, duration: 10, nowMinutes: now)
        #expect(FocusWheelGeometry.bowlGapShowsFreeLabel(span: narrowGap, window: window) == false)

        let wideGap = FocusWheelGeometry.bowlSegmentSpan(start: 540, duration: 120, nowMinutes: now)
        #expect(FocusWheelGeometry.bowlGapShowsFreeLabel(span: wideGap, window: window) == true)
    }

    @Test("The FREE label is placed inside the window, not at the gap's raw midpoint")
    func gapFreeLabelSitsInsideWindow() {
        let width: CGFloat = 375
        let radius: CGFloat = width * 2
        let window = FocusWheelGeometry.bowlVisibleWindow(radius: radius, width: width)
        // The demo day's real gap: 08:00 until the plan starts, here 15:00. It
        // qualifies for a label on the few degrees still on screen, but its raw
        // midpoint is three and a half hours back — far outside the window.
        let morning = FocusWheelGeometry.bowlSegmentSpan(start: 480, duration: 420, nowMinutes: 900)
        #expect(FocusWheelGeometry.bowlGapShowsFreeLabel(span: morning, window: window) == true)
        #expect((morning.start + morning.end) / 2 > window.max)

        let angle = FocusWheelGeometry.bowlGapLabelAngle(span: morning, window: window)
        #expect(angle > window.min && angle < window.max)

        // A gap straddling the pointer is unaffected: clipping cannot move a
        // midpoint that was already on screen.
        let straddling = FocusWheelGeometry.bowlSegmentSpan(start: 540, duration: 120, nowMinutes: 600)
        let straddlingAngle = FocusWheelGeometry.bowlGapLabelAngle(span: straddling, window: window)
        #expect(abs(straddlingAngle - (straddling.start + straddling.end) / 2) < 0.001)
    }

    @Test("5M's radius dwarfs view 1, so it remains the horizon magnifier")
    func fiveMinuteRadiusFarExceedsViewOne() {
        let width: CGFloat = 375
        let viewOne = FocusWheelGeometry.bowlTargetRadius(forWidth: width, visibility: .one)
        let fiveMinute = FocusWheelGeometry.bowlTargetRadius(forWidth: width, visibility: .fiveMinute)
        #expect(fiveMinute > viewOne * 5)
    }
}

@Suite("Focus card heights")
@MainActor
struct FocusCardDetentTests {
    @Test("The three heights rise in order, so a step up is always taller")
    func heightsRiseInOrder() {
        let screen: CGFloat = 852
        let hidden = FocusCardDetent.hidden.height(for: screen)
        let rest = FocusCardDetent.rest.height(for: screen)
        let open = FocusCardDetent.open.height(for: screen)

        #expect(hidden < rest)
        #expect(rest < open)
        // The mock's 18px handle is under the HIG's 44pt floor and is the only
        // thing left to grab once the card is away.
        #expect(hidden >= 44)
    }

    @Test("Stepping stops at both ends rather than wrapping")
    func steppingClampsAtTheEnds() {
        #expect(FocusCardDetent.hidden.stepped(up: true) == .rest)
        #expect(FocusCardDetent.rest.stepped(up: true) == .open)
        #expect(FocusCardDetent.open.stepped(up: true) == .open)
        #expect(FocusCardDetent.open.stepped(up: false) == .rest)
        #expect(FocusCardDetent.rest.stepped(up: false) == .hidden)
        #expect(FocusCardDetent.hidden.stepped(up: false) == .hidden)
    }

    @Test("Tapping the handle cycles round, so the card is never stuck away")
    func tappingCyclesRound() {
        #expect(FocusCardDetent.hidden.next == .rest)
        #expect(FocusCardDetent.rest.next == .open)
        #expect(FocusCardDetent.open.next == .hidden)
    }
}

@Suite("Bowl neighbour labels")
@MainActor
struct NeighbourLabelTests {
    @Test("A wide wedge keeps the full band and the full-size title")
    func wideWedgeKeepsFullSize() {
        let label = FocusWheelGeometry.neighbourLabel(spanDegrees: 60, midRadius: 200, thickness: 60)
        #expect(label.width == FocusWheelGeometry.neighbourLabelBandWidth(thickness: 60))
        #expect(label.isTight == false)
    }

    @Test("A narrow wedge steps the title down rather than truncating it")
    func narrowWedgeStepsDown() {
        let label = FocusWheelGeometry.neighbourLabel(spanDegrees: 8, midRadius: 200, thickness: 60)
        #expect(label.isTight)
        #expect(label.width < FocusWheelGeometry.neighbourLabelBandWidth(thickness: 60))
    }

    @Test("Even a sliver keeps enough width to draw something")
    func sliverKeepsAFloor() {
        let label = FocusWheelGeometry.neighbourLabel(spanDegrees: 0.5, midRadius: 120, thickness: 60)
        #expect(label.width >= 30)
    }
}

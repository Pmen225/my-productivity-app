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
    @Test("The circular dial exposes the same four states to chips and pinch")
    func carouselModesMatchEveryDeclaredState() {
        #expect(WheelVisibility.carouselModes == [.one, .two, .three, .all])
        // The legacy `5M` bowl state is gone, so the zoom axis and the model
        // are now the same list — nothing can be selectable but undrawable.
        #expect(WheelVisibility.carouselModes == WheelVisibility.allCases)
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

    @Test("A narrow overview slice keeps its ruler inside the active wedge")
    func narrowCarouselRulerGetsReadableArc() {
        let ruler = FocusWheelGeometry.carouselRulerSpan(activeSpan: (start: 70, end: 110))
        #expect(abs(ruler.start - 70) < 0.0001)
        #expect(abs(ruler.end - 110) < 0.0001)
        #expect(FocusWheelGeometry.carouselRulerLabelStep(
            totalMinutes: 30,
            spanDegrees: 40,
            numeralRadius: 125,
            fontSize: 10
        ) == 10)
    }

    @Test("The countdown ruler stays inside a rotated active wedge")
    func carouselRulerStaysInsideActiveWedge() {
        let active = (start: 30.0, end: 150.0)
        let ruler = FocusWheelGeometry.carouselRulerSpan(activeSpan: active)
        #expect(abs(ruler.start - active.start) < 0.0001)
        #expect(abs(ruler.end - active.end) < 0.0001)

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
        #expect(FocusWheelGeometry.carouselRulerLabelStep(
            totalMinutes: 30,
            spanDegrees: 180,
            numeralRadius: 125,
            fontSize: 10
        ) == 5)
        #expect(FocusWheelGeometry.carouselRulerLabelStep(
            totalMinutes: 30,
            spanDegrees: 40,
            numeralRadius: 125,
            fontSize: 10
        ) == 10)

        let angles = FocusWheelGeometry.curvedRulerCharacterAngles(
            textLength: 2,
            centreAngle: 90,
            radius: 80
        )
        #expect(angles.count == 2)
        #expect(angles[0] < 90)
        #expect(angles[1] > 90)

        // Tangents at the cardinal points: horizontal at top/bottom and
        // vertical at either side. This is the curved-text invariant.
        #expect(abs(FocusWheelGeometry.carouselRulerLabelRotation(angle: 0) - 90) < 0.0001)
        #expect(abs(FocusWheelGeometry.carouselRulerLabelRotation(angle: 90)) < 0.0001)
        #expect(abs(FocusWheelGeometry.carouselRulerLabelRotation(angle: 180) + 90) < 0.0001)
        #expect(abs(FocusWheelGeometry.carouselRulerLabelRotation(angle: 270)) < 0.0001)
        #expect(FocusWheelGeometry.carouselRulerLabelReversesCharacters(angle: 90))
        #expect(!FocusWheelGeometry.carouselRulerLabelReversesCharacters(angle: 270))
    }

    @Test("Numeral cadence follows the arc the numerals actually sit on, not the wedge's angle")
    func rulerCadenceFollowsArcLength() {
        // A phone-sized dial: ~340pt wide, numerals on the inner track at ~125.
        let radius: CGFloat = 125
        let size: CGFloat = 10
        func step(_ minutes: Int, _ span: Double, radius: CGFloat = radius, size: CGFloat = size) -> Int {
            FocusWheelGeometry.carouselRulerLabelStep(
                totalMinutes: minutes,
                spanDegrees: span,
                numeralRadius: radius,
                fontSize: size
            )
        }

        // Fully magnified (view 1, a 300° block): every five minutes, which is
        // the promise the deepest zoom exists to keep. Over an hour it relaxes
        // to ten, exactly as the major-tick cadence already does.
        #expect(step(30, 300) == 5)
        #expect(step(90, 300) == 10)
        // Never denser than the major ticks it labels.
        #expect(step(30, 300) == FocusWheelGeometry.carouselRulerMajorStep(totalMinutes: 30))

        // Zooming out shortens the arc, so numerals thin out progressively
        // rather than at one hard-coded degree threshold.
        #expect(step(30, 180) == 5)
        #expect(step(30, 48) == 10)

        // The same 48° wedge on a smaller dial has less arc, so it thins
        // further — degrees alone could not tell these two apart.
        #expect(step(30, 48, radius: 60) == 15)

        // Larger text needs more arc per numeral, so Dynamic Type thins the
        // cadence instead of letting the numbers collide.
        #expect(step(30, 48, size: 20) == 15)

        // When nothing fits, keep one interval: the two endpoints the countdown
        // exists to show.
        #expect(step(30, 1, radius: 1) == 30)

        // Degenerate inputs fall back to the major cadence rather than dividing
        // by zero.
        #expect(step(30, 0, radius: 0) == 5)
        #expect(step(0, 300) == 5)
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

    @Test("The overview countdown ruler runs from full duration on the left to zero on the right")
    func overviewRulerCountsDownLeftToRight() {
        #expect(FocusWheelGeometry.overviewRulerAngle(minutesRemaining: 30, totalMinutes: 30) == 180)
        #expect(FocusWheelGeometry.overviewRulerAngle(minutesRemaining: 0, totalMinutes: 30) == 360)
        #expect(FocusWheelGeometry.overviewRulerTickCount(totalMinutes: 4) == 6)
        #expect(FocusWheelGeometry.overviewRulerTickCount(totalMinutes: 45) == 45)

        let active = FocusWheelGeometry.overviewSpan(index: 0, durations: [30, 30, 15, 20, 45, 25, 60])
        let ruler = FocusWheelGeometry.carouselRulerSpan(activeSpan: active)
        #expect(abs(ruler.start - active.start) < 0.0001)
        #expect(abs(ruler.end - active.end) < 0.0001)

        // The overview shares the close dial's fixed lower track, so its
        // endpoint numerals must follow the circular tangent too.
        let fullAngle = FocusWheelGeometry.overviewRulerAngle(minutesRemaining: 30, totalMinutes: 30)
        let zeroAngle = FocusWheelGeometry.overviewRulerAngle(minutesRemaining: 0, totalMinutes: 30)
        #expect(abs(FocusWheelGeometry.carouselRulerLabelRotation(angle: fullAngle) + 90) < 0.0001)
        #expect(abs(FocusWheelGeometry.carouselRulerLabelRotation(angle: zeroAngle) - 90) < 0.0001)
    }

    @Test("Both ends of the countdown are major ticks; five- and one-minute marks step down")
    func rulerTickTiersReadAsAScale() {
        // 45 minutes: the major cadence is every 5.
        #expect(FocusWheelGeometry.carouselRulerTickTier(minutesRemaining: 45, totalMinutes: 45) == .major)
        #expect(FocusWheelGeometry.carouselRulerTickTier(minutesRemaining: 0, totalMinutes: 45) == .major)
        #expect(FocusWheelGeometry.carouselRulerTickTier(minutesRemaining: 30, totalMinutes: 45) == .major)
        #expect(FocusWheelGeometry.carouselRulerTickTier(minutesRemaining: 7, totalMinutes: 45) == .minor)

        // Over an hour the cadence relaxes to 10, which is what creates the
        // middle weight: 25 is still a five-minute mark but no longer a major.
        #expect(FocusWheelGeometry.carouselRulerTickTier(minutesRemaining: 30, totalMinutes: 90) == .major)
        #expect(FocusWheelGeometry.carouselRulerTickTier(minutesRemaining: 25, totalMinutes: 90) == .medium)
        #expect(FocusWheelGeometry.carouselRulerTickTier(minutesRemaining: 23, totalMinutes: 90) == .minor)
    }

    @Test("Every part of the ruler is drawn inside its own band, numerals inboard of the ticks")
    func rulerRadiiStayInsideTheBand() {
        let inner: CGFloat = 100
        let thickness: CGFloat = 50
        let radii = FocusWheelGeometry.carouselRulerRadii(innerRadius: inner, thickness: thickness)

        // Hand-computed from the contract's fractions of thickness.
        #expect(abs(radii.numeral - 111) < 0.0001)
        #expect(abs(radii.tickBase - 120) < 0.0001)
        #expect(abs(radii.minorTip - 126) < 0.0001)
        #expect(abs(radii.mediumTip - 130) < 0.0001)
        #expect(abs(radii.majorTip - 136) < 0.0001)

        // Numerals sit inboard of their ticks, and tick length rises with tier.
        #expect(radii.numeral < radii.tickBase)
        #expect(radii.tip(for: .minor) < radii.tip(for: .medium))
        #expect(radii.tip(for: .medium) < radii.tip(for: .major))

        // Nothing leaves the annulus: `radius` alone is the OUTER edge, which on
        // this dial sits under the pointer.
        #expect(radii.numeral > inner)
        #expect(radii.majorTip < inner + thickness)
    }

    @Test("Each digit bends onto its own tangent, and no digit ends up upside down")
    func curvedNumeralsBendAndStayUpright() {
        // A character offset from its label's centre takes its own tangent,
        // not the centre's — that is what bends a two-digit number onto the arc.
        let left = FocusWheelGeometry.curvedRulerCharacterRotation(characterAngle: 95, labelCentreAngle: 90)
        let right = FocusWheelGeometry.curvedRulerCharacterRotation(characterAngle: 85, labelCentreAngle: 90)
        #expect(abs(left - 5) < 0.0001)
        #expect(abs(right + 5) < 0.0001)
        #expect(left != right)

        // A single-character label is exactly the whole-label rotation.
        for angle in [0.0, 90, 180, 270, 45, 135] {
            #expect(
                FocusWheelGeometry.curvedRulerCharacterRotation(characterAngle: angle, labelCentreAngle: angle)
                    == FocusWheelGeometry.carouselRulerLabelRotation(angle: angle)
            )
        }

        // A label is never turned past the quarter turn: beyond that the flip
        // rule is what brings it back, which is the whole reason it exists.
        for angle in stride(from: 0.0, to: 360, by: 1) {
            #expect(abs(FocusWheelGeometry.carouselRulerLabelRotation(angle: angle)) <= 90.0001)
        }

        // The flip belongs to the label, so a numeral straddling a cardinal
        // point cannot stand one of its digits on its head: two characters of
        // one label differ by no more than the arc between them. Deciding the
        // flip per character instead would show up here as a ~180° jump.
        for centre in stride(from: 0.0, to: 360, by: 1) {
            let first = FocusWheelGeometry.curvedRulerCharacterRotation(
                characterAngle: centre - 4,
                labelCentreAngle: centre
            )
            let last = FocusWheelGeometry.curvedRulerCharacterRotation(
                characterAngle: centre + 4,
                labelCentreAngle: centre
            )
            #expect(abs(last - first) <= 8.0001)
        }
    }

    @Test("A numeral is clamped inside its wedge instead of spilling over the boundary")
    func rulerNumeralsStayInsideTheActiveWedge() {
        let fontSize: CGFloat = 10
        let radius: CGFloat = 100
        // Hand-computed: spacing 10 × 0.62 = 6.2pt per digit, so a two-digit
        // numeral spans 12.4pt of arc = 12.4/100 rad = 7.1047°, half = 3.5523°.
        let half = FocusWheelGeometry.curvedRulerLabelHalfWidth(
            characterCount: 2,
            fontSize: fontSize,
            radius: radius
        )
        #expect(abs(FocusWheelGeometry.curvedRulerCharacterSpacing(fontSize: fontSize) - 6.2) < 0.0001)
        #expect(abs(half - 3.5523) < 0.001)

        // The demo's narrow overview wedge. Both endpoint numerals move inward
        // by their own half-width; a numeral in the middle is left alone.
        let span = (start: 70.0, end: 110.0)
        let atStart = FocusWheelGeometry.carouselRulerLabelCentreAngle(
            tickAngle: span.start, span: span, characterCount: 2, fontSize: fontSize, radius: radius
        )
        let atEnd = FocusWheelGeometry.carouselRulerLabelCentreAngle(
            tickAngle: span.end, span: span, characterCount: 2, fontSize: fontSize, radius: radius
        )
        let middle = FocusWheelGeometry.carouselRulerLabelCentreAngle(
            tickAngle: 90, span: span, characterCount: 2, fontSize: fontSize, radius: radius
        )
        #expect(abs(atStart - (span.start + half)) < 0.0001)
        #expect(abs(atEnd - (span.end - half)) < 0.0001)
        #expect(abs(middle - 90) < 0.0001)
        #expect(atStart > span.start)
        #expect(atEnd < span.end)

        // A wedge too narrow to hold the numeral at all centres it rather than
        // clamping past itself and inverting the two bounds.
        let sliver = (start: 89.0, end: 91.0)
        let inSliver = FocusWheelGeometry.carouselRulerLabelCentreAngle(
            tickAngle: sliver.start, span: sliver, characterCount: 2, fontSize: fontSize, radius: radius
        )
        #expect(abs(inSliver - 90) < 0.0001)
    }

    @Test("The zoom axis and the chip row are the same four states in the same order")
    func zoomAxisMatchesTheChipRow() {
        #expect(FocusWheelGeometry.carouselZoom(for: .one) == 0)
        #expect(FocusWheelGeometry.carouselZoom(for: .two) == 1)
        #expect(FocusWheelGeometry.carouselZoom(for: .three) == 2)
        #expect(FocusWheelGeometry.carouselZoom(for: .all) == 3)

        // Round-trips, so a settled dial always sits exactly on its own chip.
        for mode in WheelVisibility.carouselModes {
            let zoom = FocusWheelGeometry.carouselZoom(for: mode)
            #expect(FocusWheelGeometry.settledCarouselMode(forZoom: zoom) == mode)
        }

        // Every state the model can hold is on the axis, so a pinch can reach
        // all of them and settle in none that a chip cannot also select.
        for zoom in [-4.0, -0.5, 0.4, 1.2, 2.7, 3.0, 9.0] {
            let mode = FocusWheelGeometry.settledCarouselMode(forZoom: zoom)
            #expect(WheelVisibility.carouselModes.contains(mode))
        }
    }

    @Test("Spreading the fingers magnifies: one doubling is one mode step, clamped at both ends")
    func pinchMapsOneDoublingToOneModeStep() {
        // Identity: no spread yet, no movement.
        #expect(FocusWheelGeometry.carouselZoom(base: 1, magnification: 1) == 1)
        // Spreading to twice the span is one step TOWARD `one`, the deepest
        // zoom — the same direction a map or a photo moves under the gesture.
        #expect(FocusWheelGeometry.carouselZoom(base: 1, magnification: 2) == 0)
        // Pinching inward is one step toward `all`.
        #expect(FocusWheelGeometry.carouselZoom(base: 1, magnification: 0.5) == 2)
        // √2 is half a step: log2(2^0.5) = 0.5, subtracted.
        #expect(abs(FocusWheelGeometry.carouselZoom(base: 3, magnification: 2.0.squareRoot()) - 2.5) < 0.0001)

        // Clamped, never wrapped: a hard spread from 1 cannot land back on All.
        #expect(FocusWheelGeometry.carouselZoom(base: 0, magnification: 4) == 0)
        #expect(FocusWheelGeometry.carouselZoom(base: 3, magnification: 0.25) == 3)
        #expect(FocusWheelGeometry.carouselZoom(base: 2, magnification: 4) == 0)

        // A degenerate magnification leaves the dial where it was rather than
        // sending log2 to negative infinity.
        #expect(FocusWheelGeometry.carouselZoom(base: 2, magnification: 0) == 2)
    }

    @Test("Releasing settles on the nearest view, and a dead-even tie goes to All")
    func settleRoundsToTheNearestMode() {
        #expect(FocusWheelGeometry.settledCarouselMode(forZoom: 1.4) == .two)
        #expect(FocusWheelGeometry.settledCarouselMode(forZoom: 1.6) == .three)
        #expect(FocusWheelGeometry.settledCarouselMode(forZoom: 0.49) == .one)
        // The documented tie rule: exactly halfway rounds outward, toward All.
        #expect(FocusWheelGeometry.settledCarouselMode(forZoom: 0.5) == .two)
        #expect(FocusWheelGeometry.settledCarouselMode(forZoom: 1.5) == .three)
        #expect(FocusWheelGeometry.settledCarouselMode(forZoom: 2.5) == .all)
        // Out of range still lands on a real mode.
        #expect(FocusWheelGeometry.settledCarouselMode(forZoom: -3) == .one)
        #expect(FocusWheelGeometry.settledCarouselMode(forZoom: 12) == .all)
    }

    @Test("An integer zoom draws exactly the settled layout it names")
    func integerZoomReproducesEachDiscreteLayout() {
        let durations = [30, 20, 10, 40]

        // Hand-computed against the consumption anchor: the active block's
        // LEADING edge sits on the pointer at 90°, so every block hangs
        // anticlockwise from there. `1` gives its single block the 300° window;
        // `2` and `3` split the turn evenly; `All` shares it out by duration
        // over a 100-minute queue, so 30M is 108°, 20M is 72°, 10M is 36°,
        // 40M is 144°.
        let expected: [(zoom: Double, spans: [(start: Double, end: Double)])] = [
            (0, [(-210, 90)]),
            (1, [(-90, 90), (-270, -90)]),
            (2, [(-30, 90), (-150, -30), (-270, -150)]),
            (3, [(-18, 90), (-90, -18), (-126, -90), (-270, -126)]),
        ]

        for entry in expected {
            let spans = FocusWheelGeometry.carouselSpans(
                zoom: entry.zoom,
                durations: durations,
                rotation: 0
            )
            for (index, want) in entry.spans.enumerated() {
                #expect(abs(spans[index].start - want.start) < 0.0001)
                #expect(abs(spans[index].end - want.end) < 0.0001)
            }
        }

        // And the same SHAPE the discrete layout has always produced, for every
        // mode and every block it shows — the four settled screens are the old
        // ones re-anchored by half the active block, not redrawn.
        for (index, mode) in WheelVisibility.carouselModes.enumerated() {
            let shown = FocusWheelGeometry.visibleCount(for: mode, queueCount: durations.count)
            let visible = Array(durations.prefix(shown))
            let spans = FocusWheelGeometry.carouselSpans(
                zoom: Double(index),
                durations: durations,
                rotation: 17
            )
            let active = FocusWheelGeometry.carouselSpan(
                index: 0,
                visibility: mode,
                durations: visible,
                rotation: 17
            )
            let shift = -(active.end - active.start) / 2
            for block in 0..<shown {
                let discrete = FocusWheelGeometry.carouselSpan(
                    index: block,
                    visibility: mode,
                    durations: visible,
                    rotation: 17
                )
                #expect(abs(spans[block].start - (discrete.start + shift)) < 0.0001)
                #expect(abs(spans[block].end - (discrete.end + shift)) < 0.0001)
            }
        }

        // The anchor itself: whatever the zoom, the active block's clockwise
        // edge is ON the pointer, which is the edge it is consumed into.
        for zoom in [0.0, 0.6, 1.0, 2.4, 3.0] {
            let spans = FocusWheelGeometry.carouselSpans(zoom: zoom, durations: durations, rotation: 0)
            #expect(abs(spans[0].end - FocusWheelGeometry.bottomAngle) < 0.0001)
        }
    }

    @Test("A zoom between two views draws the layout between them")
    func fractionalZoomInterpolatesBetweenTheTwoLayouts() {
        let durations = [30, 20, 10, 40]

        // Halfway from `2` (180° each) to `3` (120° each) is 150° each, so the
        // active block runs 150° back from the pointer and the next one hangs
        // off its far edge.
        let spans = FocusWheelGeometry.carouselSpans(zoom: 1.5, durations: durations, rotation: 0)
        #expect(abs(spans[0].start - (-60)) < 0.0001)
        #expect(abs(spans[0].end - 90) < 0.0001)
        #expect(abs(spans[1].start - (-210)) < 0.0001)
        #expect(abs(spans[1].end - (-60)) < 0.0001)
        // The third block is halfway into existence: 60° of an eventual 120°.
        #expect(abs((spans[2].end - spans[2].start) - 60) < 0.0001)
        #expect(abs(spans[2].end - (-210)) < 0.0001)

        // The blocks stay a contiguous ring at every fractional zoom — no gap
        // opens between one block's end and the next one's start.
        for zoom in [0.3, 1.0, 1.75, 2.5, 3.0] {
            let ring = FocusWheelGeometry.carouselSpans(zoom: zoom, durations: durations, rotation: 0)
            for index in 1..<ring.count {
                #expect(abs(ring[index].end - ring[index - 1].start) < 0.0001)
            }
        }
    }

    @Test("A block grows in from the right rather than appearing on top of its neighbour")
    func newBlockGrowsFromZeroWidth() {
        let durations = [30, 20, 10, 40]

        // At `2` exactly the third block has no width at all, and it is not
        // drawn: a slice narrower than its own two separator gaps would invert
        // its arc and paint most of the ring.
        let settled = FocusWheelGeometry.carouselSpans(zoom: 1, durations: durations, rotation: 0)
        let settledGap = FocusWheelGeometry.carouselGap(zoom: 1, durations: durations)
        #expect(settled[2].end - settled[2].start == 0)
        #expect(!FocusWheelGeometry.carouselWedgeIsDrawn(width: 0, gap: settledGap))

        // A hair into the pinch it exists but is still too narrow to draw.
        let barely = FocusWheelGeometry.carouselSpans(zoom: 1.01, durations: durations, rotation: 0)
        let barelyWidth = barely[2].end - barely[2].start
        #expect(abs(barelyWidth - 1.2) < 0.0001)
        #expect(!FocusWheelGeometry.carouselWedgeIsDrawn(
            width: barelyWidth,
            gap: FocusWheelGeometry.carouselGap(zoom: 1.01, durations: durations)
        ))

        // A tenth of the way it is 12° wide and earns its wedge.
        let opening = FocusWheelGeometry.carouselSpans(zoom: 1.1, durations: durations, rotation: 0)
        let openingWidth = opening[2].end - opening[2].start
        #expect(abs(openingWidth - 12) < 0.0001)
        #expect(FocusWheelGeometry.carouselWedgeIsDrawn(
            width: openingWidth,
            gap: FocusWheelGeometry.carouselGap(zoom: 1.1, durations: durations)
        ))
    }

    @Test("The next task rides in as the active one elapses, and is fully there at the handover")
    func handoverGrowsTheNextBlockAcrossTheTask() {
        let durations = [30, 20, 10, 40]

        // Nothing has elapsed: the layout is the settled one, to the pixel.
        for mode in WheelVisibility.carouselModes {
            let settled = FocusWheelGeometry.carouselWidths(for: mode, durations: durations)
            let atStart = FocusWheelGeometry.carouselWidths(
                for: mode,
                durations: durations,
                elapsed: 0
            )
            #expect(settled == atStart)
        }

        // View 1 keeps its 300° block and its free window; the second task
        // grows into that window from nothing to a full slice.
        #expect(FocusWheelGeometry.carouselWidths(for: .one, durations: durations) == [300, 0, 0, 0])
        #expect(FocusWheelGeometry.carouselWidths(
            for: .one,
            durations: durations,
            elapsed: 0.5
        ) == [300, 150, 0, 0])
        #expect(FocusWheelGeometry.carouselWidths(
            for: .one,
            durations: durations,
            elapsed: 1
        ) == [300, 300, 0, 0])

        // Views 2 and 3 behave the same way one place further along the queue:
        // only the FIRST block past the cap enters, never the whole tail.
        #expect(FocusWheelGeometry.carouselWidths(
            for: .two,
            durations: durations,
            elapsed: 0.5
        ) == [180, 180, 90, 0])
        #expect(FocusWheelGeometry.carouselWidths(
            for: .three,
            durations: durations,
            elapsed: 1
        ) == [120, 120, 120, 120])

        // `All` already draws every block, so the handover cannot move it.
        #expect(FocusWheelGeometry.carouselWidths(for: .all, durations: durations, elapsed: 1)
            == FocusWheelGeometry.carouselWidths(for: .all, durations: durations))

        // Out-of-range fractions clamp rather than overshooting the slice.
        #expect(FocusWheelGeometry.carouselWidths(for: .two, durations: durations, elapsed: -1)
            == FocusWheelGeometry.carouselWidths(for: .two, durations: durations))
        #expect(FocusWheelGeometry.carouselWidths(for: .two, durations: durations, elapsed: 4)
            == FocusWheelGeometry.carouselWidths(for: .two, durations: durations, elapsed: 1))

        // A pinch mid-task interpolates two layouts that already agree about
        // the entering block, so the arriving slice cannot snap back to zero.
        let mid = FocusWheelGeometry.carouselWidths(zoom: 1.5, durations: durations, elapsed: 0.5)
        for (actual, expected) in zip(mid, [150.0, 150, 105, 30]) {
            #expect(abs(actual - expected) < 0.0001)
        }

        // The entering block still arrives from the right, anticlockwise of the
        // active one — the same edge every block has always come in on.
        let spans = FocusWheelGeometry.carouselSpans(
            zoom: 1,
            durations: durations,
            rotation: 0,
            elapsed: 0.5
        )
        #expect(abs(spans[2].end - spans[1].start) < 0.0001)
        #expect(abs((spans[2].end - spans[2].start) - 90) < 0.0001)
    }

    @Test("Consuming the active block never leaves a hole in the ring")
    func consumptionKeepsTheRingFull() {
        let durations = [30, 20, 10, 40]

        // The identity the whole mechanic rests on: what the active block loses
        // at the pointer, the entering block gains on the far side, so the
        // capped modes stay exactly closed at every moment of the task.
        for elapsed in [0.0, 0.25, 0.5, 1.0] {
            for zoom in [1.0, 2.0] {
                let total = FocusWheelGeometry.carouselTotalWidth(
                    zoom: zoom,
                    durations: durations,
                    elapsed: elapsed
                )
                #expect(abs(total - 360) < 0.0001)
            }

            // View `1` deliberately keeps a 60° quiet window, so its own total
            // is 300 — but it is just as invariant, which is the property that
            // matters: consumption does not change how much ring is covered.
            let single = FocusWheelGeometry.carouselTotalWidth(
                zoom: 0,
                durations: durations,
                elapsed: elapsed
            )
            #expect(abs(single - 300) < 0.0001)

            // Blocks stay contiguous while the active one shrinks.
            let spans = FocusWheelGeometry.carouselSpans(
                zoom: 1,
                durations: durations,
                rotation: 0,
                elapsed: elapsed
            )
            for index in 1..<spans.count {
                #expect(abs(spans[index].end - spans[index - 1].start) < 0.0001)
            }
        }
    }

    @Test("The advance has no snap frame: a finished task hands over seamlessly")
    func advanceHasNoSnapFrame() {
        let durations = [30, 20, 10, 40]

        // The layout at the instant the active task ends is already the layout
        // the next task starts from, so the swap moves nothing on screen.
        for zoom in [0.0, 1.0, 2.0] {
            let finishing = FocusWheelGeometry.carouselSpans(
                zoom: zoom,
                durations: durations,
                rotation: 0,
                elapsed: 1
            )
            let starting = FocusWheelGeometry.carouselSpans(
                zoom: zoom,
                durations: Array(durations.dropFirst()),
                rotation: 0,
                elapsed: 0
            )
            #expect(finishing.count - 1 == starting.count)
            for (index, next) in starting.enumerated() {
                #expect(abs(finishing[index + 1].start - next.start) < 0.0001)
                #expect(abs(finishing[index + 1].end - next.end) < 0.0001)
            }
        }
    }

    @Test("The numeral crossing the pointer is the minutes remaining")
    func rulerReadsMinutesRemainingAtThePointer() {
        let durations = [40, 20, 10]
        let totalMinutes = 40

        for elapsed in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let spans = FocusWheelGeometry.carouselSpans(
                zoom: 1,
                durations: durations,
                rotation: 0,
                elapsed: elapsed
            )
            let settled = FocusWheelGeometry.carouselWidths(
                zoom: 1,
                durations: durations,
                elapsed: elapsed
            )[0]
            let tape = FocusWheelGeometry.carouselRulerTapeSpan(
                activeSpan: spans[0],
                settledWidth: settled
            )
            let remaining = Int((Double(totalMinutes) * (1 - elapsed)).rounded())
            let angle = FocusWheelGeometry.carouselRulerAngle(
                minutesRemaining: remaining,
                totalMinutes: totalMinutes,
                span: tape
            )
            #expect(abs(angle - FocusWheelGeometry.bottomAngle) < 0.0001)

            // Nothing above that mark is drawn — the consumed ticks have gone
            // into the pointer rather than spilling onto the queue behind it.
            #expect(FocusWheelGeometry.carouselRulerTopTick(
                totalMinutes: totalMinutes,
                elapsed: elapsed
            ) == Int((Double(totalMinutes) * (1 - elapsed)).rounded(.down)))
        }

        // The pitch is constant: the tape is exactly the task's settled width
        // however much of it is left, so a minute is the same arc throughout.
        for elapsed in [0.0, 0.6] {
            let spans = FocusWheelGeometry.carouselSpans(
                zoom: 1, durations: durations, rotation: 0, elapsed: elapsed
            )
            let settled = FocusWheelGeometry.carouselWidths(
                zoom: 1, durations: durations, elapsed: elapsed
            )[0]
            let tape = FocusWheelGeometry.carouselRulerTapeSpan(activeSpan: spans[0], settledWidth: settled)
            #expect(abs((tape.end - tape.start) - settled) < 0.0001)
        }
    }

    @Test("At day scale, spent time simply leaves a gap behind the pointer")
    func allModeOpensAGapAsTimeIsSpent() {
        let durations = [30, 20, 10, 40]
        func freeWidth(zoom: Double, elapsed: Double) -> Double? {
            FocusWheelGeometry.carouselFreeSpan(
                zoom: zoom, durations: durations, rotation: 0, elapsed: elapsed
            ).map { $0.end - $0.start }
        }

        // `All` has no hidden block to ramp in, so the active block's 108°
        // share is given up to a quiet arc rather than handed to a neighbour.
        #expect(freeWidth(zoom: 3, elapsed: 0) == nil)

        for elapsed in [0.25, 0.5, 1.0] {
            #expect(abs((freeWidth(zoom: 3, elapsed: elapsed) ?? 0) - 108 * elapsed) < 0.0001)
            // It opens on the clockwise side of the pointer, where the task
            // that has just been used up used to be.
            let free = FocusWheelGeometry.carouselFreeSpan(
                zoom: 3, durations: durations, rotation: 0, elapsed: elapsed
            )
            #expect(abs((free?.start ?? 0) - FocusWheelGeometry.bottomAngle) < 0.0001)
        }

        // The capped modes never open one: the ramp fills the budget exactly.
        for zoom in [1.0, 2.0] {
            #expect(freeWidth(zoom: zoom, elapsed: 0.5) == nil)
        }
    }

    @Test("Time travel cannot be dragged past the queue in either direction")
    func timeTravelIsClampedToTheQueue() {
        let durations = [30, 20, 10, 40]

        // Forward stops with the last block's far edge on the pointer; there is
        // no history behind the wheel, so backward is pinned at zero.
        let limit = FocusWheelGeometry.carouselTotalWidth(zoom: 1, durations: durations)
        #expect(abs(limit - 360) < 0.0001)
        #expect(FocusWheelGeometry.clampDragPreview(9_999, zoom: 1, durations: durations) == limit)
        #expect(FocusWheelGeometry.clampDragPreview(-9_999, zoom: 1, durations: durations) == 0)
        #expect(FocusWheelGeometry.clampDragPreview(-0.5, zoom: 1, durations: durations) == 0)
        #expect(abs(FocusWheelGeometry.clampDragPreview(120, zoom: 1, durations: durations) - 120) < 0.0001)

        // An empty queue has nowhere to travel to at all.
        #expect(FocusWheelGeometry.clampDragPreview(200, zoom: 1, durations: []) == 0)
        #expect(FocusWheelGeometry.clampDragPreview(-200, zoom: 1, durations: []) == 0)

        // One task keeps its own 300° window and no more.
        #expect(abs(FocusWheelGeometry.clampDragPreview(9_999, zoom: 1, durations: [30]) - 300) < 0.0001)
        // Half consumed, half the travel: the limit tracks what is still drawn.
        #expect(abs(FocusWheelGeometry.clampDragPreview(
            9_999, zoom: 1, durations: [30], elapsed: 0.5
        ) - 150) < 0.0001)

        // Dragging LEFT along the bottom of the dial is forward travel, the
        // same direction the queue already moves as time passes.
        #expect(FocusWheelGeometry.dragPreviewOffset(translationWidth: -100, radius: 100) > 0)
        #expect(FocusWheelGeometry.dragPreviewOffset(translationWidth: 100, radius: 100) < 0)
        #expect(FocusWheelGeometry.dragPreviewOffset(translationWidth: 50, radius: 0) == 0)

        // The pointer reads the active block until the drag has carried that
        // block's whole width past it, and then reads the next one.
        #expect(FocusWheelGeometry.carouselIndexAtPointer(zoom: 1, durations: durations) == 0)
        #expect(FocusWheelGeometry.carouselIndexAtPointer(
            zoom: 1, durations: durations, offset: 200
        ) == 1)
        #expect(FocusWheelGeometry.carouselIndexAtPointer(zoom: 1, durations: []) == nil)
    }

    @Test("The separator gap and the ring's turn interpolate with the layout")
    func gapAndSweepFollowTheZoom() {
        let durations = [30, 20, 10, 40]

        // `1` shows a single block, which needs no separator; every other view
        // shows more than one, so the gap is the full 1.6° from `2` onward.
        #expect(FocusWheelGeometry.carouselGap(zoom: 0, durations: durations) == 0)
        #expect(abs(FocusWheelGeometry.carouselGap(zoom: 1, durations: durations) - 1.6) < 0.0001)
        #expect(abs(FocusWheelGeometry.carouselGap(zoom: 0.5, durations: durations) - 0.8) < 0.0001)
        #expect(abs(FocusWheelGeometry.carouselGap(zoom: 2.4, durations: durations) - 1.6) < 0.0001)

        // The sweep the ring's rotation is measured in matches the settled
        // value at every view, and lerps between them in-flight.
        for (index, mode) in WheelVisibility.carouselModes.enumerated() {
            #expect(FocusWheelGeometry.carouselSweep(zoom: Double(index), queueCount: 4)
                == FocusWheelGeometry.carouselSweep(for: mode, queueCount: 4))
        }
        #expect(abs(FocusWheelGeometry.carouselSweep(zoom: 0.5, queueCount: 4) - 240) < 0.0001)
        #expect(abs(FocusWheelGeometry.carouselSweep(zoom: 2.5, queueCount: 4) - 105) < 0.0001)
    }

    @Test("A one-task queue and an empty one both survive every zoom")
    func degenerateQueuesStayInBounds() {
        // One task keeps the quiet 300° window in the close views and closes
        // into a full ring at All, exactly as the discrete layouts do.
        let single = FocusWheelGeometry.carouselSpans(zoom: 0, durations: [25], rotation: 0)
        #expect(abs((single[0].end - single[0].start) - 300) < 0.0001)
        let singleAll = FocusWheelGeometry.carouselSpans(zoom: 3, durations: [25], rotation: 0)
        #expect(abs((singleAll[0].end - singleAll[0].start) - 360) < 0.0001)

        #expect(FocusWheelGeometry.carouselSpans(zoom: 1.5, durations: [], rotation: 0).isEmpty)
        #expect(FocusWheelGeometry.carouselWidths(zoom: 1.5, durations: []).isEmpty)
        #expect(FocusWheelGeometry.carouselGap(zoom: 1.5, durations: []) == 0)
    }
}

@Suite("Focus wheel zoom styles")
struct FocusWheelZoomStyleTests {
    /// The dial's own container on an iPhone 17 Pro with the card at rest.
    private let viewport = CGSize(width: 361, height: 405)
    private var radius: CGFloat { FocusWheelGeometry.carouselDiameter(in: viewport) / 2 }

    @Test("The close-up is the default style, so pinching in hides the rest of the wheel")
    func closeUpIsTheDefault() {
        #expect(WheelZoomStyle.pickerOrder == [.magnify, .reform])
        #expect(WheelZoomStyle.pickerOrder.first == .magnify)
        // A settings row that has never been written, or that holds a value
        // from a build that did not have this enum, must land on the founder's
        // default rather than on whichever case happens to be declared first.
        #expect((WheelZoomStyle(rawValue: "nonsense") ?? .magnify) == .magnify)
        #expect(WheelZoomStyle.allCases.count == 2)
    }

    @Test("Spreading the fingers magnifies one-for-one, clamped to a readable range")
    func magnifyFactorTracksTheFingers() {
        #expect(FocusWheelGeometry.magnifyFactor(base: 1, magnification: 1) == 1)
        #expect(FocusWheelGeometry.magnifyFactor(base: 1, magnification: 3) == 3)
        #expect(FocusWheelGeometry.magnifyFactor(base: 2, magnification: 2) == 4)
        // Never below the whole circle, never past the point where a single
        // block fills the screen.
        #expect(FocusWheelGeometry.magnifyFactor(base: 1, magnification: 0.25) == 1)
        #expect(FocusWheelGeometry.magnifyFactor(base: 4, magnification: 8) == 8)
        #expect(FocusWheelGeometry.magnifyFactor(base: 4, magnification: 0) == 4)
    }

    @Test("VoiceOver steps the close-up through the same doublings the haptic marks")
    func magnifyStepsThroughDoublings() {
        #expect(FocusWheelGeometry.steppedMagnifyFactor(from: 1, delta: 1) == 2)
        #expect(FocusWheelGeometry.steppedMagnifyFactor(from: 2, delta: 1) == 4)
        #expect(FocusWheelGeometry.steppedMagnifyFactor(from: 4, delta: 1) == 8)
        #expect(FocusWheelGeometry.steppedMagnifyFactor(from: 8, delta: 1) == 8)
        #expect(FocusWheelGeometry.steppedMagnifyFactor(from: 1, delta: -1) == 1)
        // A factor left mid-way by a pinch steps from the nearest stop, so the
        // rotor never lands somewhere the haptic has no name for.
        #expect(FocusWheelGeometry.steppedMagnifyFactor(from: 3.6, delta: -1) == 2)

        #expect(FocusWheelGeometry.magnifyHapticBucket(factor: 1) == 0)
        #expect(FocusWheelGeometry.magnifyHapticBucket(factor: 1.9) == 0)
        #expect(FocusWheelGeometry.magnifyHapticBucket(factor: 2) == 1)
        #expect(FocusWheelGeometry.magnifyHapticBucket(factor: 4) == 2)
        #expect(FocusWheelGeometry.magnifyHapticBucket(factor: 8) == 3)
    }

    @Test("At rest the whole circle shows; magnifying closes the window onto the pointer")
    func visibleWindowNarrowsWithMagnification() {
        let whole = FocusWheelGeometry.magnifyVisibleHalfAngle(
            radius: radius, factor: 1, viewport: viewport
        )
        #expect(whole == 180)

        let four = FocusWheelGeometry.magnifyVisibleHalfAngle(
            radius: radius, factor: 4, viewport: viewport
        )
        let eight = FocusWheelGeometry.magnifyVisibleHalfAngle(
            radius: radius, factor: 8, viewport: viewport
        )
        // This is the founder's ruling made measurable: zoomed in, most of the
        // ring is off screen, and further in shows less of it still.
        #expect(four < 90)
        #expect(eight < four)
        #expect(eight > 0)

        let window = FocusWheelGeometry.magnifyVisibleWindow(
            radius: radius, factor: 4, viewport: viewport
        )
        #expect(abs((window.start + window.end) / 2 - FocusWheelGeometry.bottomAngle) < 0.0001)
        #expect(abs((window.end - window.start) / 2 - four) < 0.0001)
    }

    @Test("The ruler's numerals densify as the close-up grows, because the arc they sit on does")
    func rulerCadenceFollowsTheEffectiveRadius() {
        let numeralRadius: CGFloat = 120
        let atRest = FocusWheelGeometry.carouselRulerLabelStep(
            totalMinutes: 60,
            spanDegrees: 60,
            numeralRadius: numeralRadius,
            fontSize: 10
        )
        let magnified = FocusWheelGeometry.carouselRulerLabelStep(
            totalMinutes: 60,
            spanDegrees: 60,
            numeralRadius: FocusWheelGeometry.magnifiedRadius(numeralRadius, factor: 4),
            fontSize: 10
        )
        #expect(FocusWheelGeometry.magnifiedRadius(numeralRadius, factor: 4) == 480)
        #expect(magnified < atRest)
    }

    @Test("A wedge with only a sliver on screen still labels itself inside the window")
    func labelIsClippedToTheWindowBeforeItsMidpointIsTaken() throws {
        let window = FocusWheelGeometry.magnifyVisibleWindow(
            radius: radius, factor: 4, viewport: viewport
        )
        // A long block reaching the pointer from far anticlockwise: its raw
        // midpoint is most of a turn away from the visible slice.
        let start = FocusWheelGeometry.bottomAngle - 200
        let end = FocusWheelGeometry.bottomAngle - 2
        let rawMid = (start + end) / 2
        #expect(rawMid < window.start)

        let clipped = FocusWheelGeometry.clippedSpanMidAngle(start: start, end: end, window: window)
        let angle = try #require(clipped)
        #expect(angle >= window.start)
        #expect(angle <= window.end)

        // A block that is entirely off screen earns no label at all rather
        // than one drawn at the window's edge.
        #expect(FocusWheelGeometry.clippedSpanMidAngle(
            start: FocusWheelGeometry.bottomAngle - 200,
            end: FocusWheelGeometry.bottomAngle - 150,
            window: window
        ) == nil)

        // A block laid a whole turn away is still the one at the pointer, so
        // it must not be mistaken for an off-screen one.
        let wrapped = FocusWheelGeometry.clippedSpanMidAngle(
            start: FocusWheelGeometry.bottomAngle - 358,
            end: FocusWheelGeometry.bottomAngle - 350,
            window: window
        )
        #expect(wrapped != nil)

        // At rest nothing is clipped: the midpoint is exactly what it always
        // was, so the whole-circle layout is untouched by any of this.
        let restWindow = FocusWheelGeometry.magnifyVisibleWindow(
            radius: radius, factor: 1, viewport: viewport
        )
        let atRest = FocusWheelGeometry.clippedSpanMidAngle(start: -30, end: 30, window: restWindow)
        #expect(atRest == 0)
    }

    @Test("The re-forming swell answers the fingers but never runs away with the dial")
    func reformScaleIsDampedAndClamped() {
        #expect(FocusWheelGeometry.reformScale(magnification: 1) == 1)
        #expect(FocusWheelGeometry.reformScale(magnification: 2) > 1)
        #expect(FocusWheelGeometry.reformScale(magnification: 0.5) < 1)
        #expect(FocusWheelGeometry.reformScale(magnification: 100) == FocusWheelGeometry.reformScaleRange.upperBound)
        #expect(FocusWheelGeometry.reformScale(magnification: 0.001) == FocusWheelGeometry.reformScaleRange.lowerBound)
        #expect(FocusWheelGeometry.reformScale(magnification: 0) == 1)
    }

    @Test("The close-up is anchored on the pointer, not the dial's centre")
    func magnifyAnchorSitsOnThePointer() {
        let anchor = FocusWheelGeometry.magnifyAnchorUnit(in: viewport)
        let centre = FocusWheelGeometry.carouselCentre(in: viewport)
        let pointer = FocusWheelGeometry.point(
            centre: centre,
            radius: radius,
            angle: FocusWheelGeometry.bottomAngle
        )
        #expect(abs(anchor.x - pointer.x / viewport.width) < 0.0001)
        #expect(abs(anchor.y - pointer.y / viewport.height) < 0.0001)
        // Below the middle of the container: scaling about it is what keeps
        // the band being read on screen while the far side leaves.
        #expect(anchor.y > 0.5)
    }

    @Test("A tick is visible only when its angle actually falls inside the magnify window")
    func tickVisibilityRespectsTheMagnifyWindow() {
        let window = (start: 80.0, end: 100.0)
        #expect(FocusWheelGeometry.carouselRulerTickIsVisible(angle: 90, window: window))
        #expect(FocusWheelGeometry.carouselRulerTickIsVisible(angle: 80, window: window))
        #expect(FocusWheelGeometry.carouselRulerTickIsVisible(angle: 100, window: window))
        #expect(!FocusWheelGeometry.carouselRulerTickIsVisible(angle: 200, window: window))
        // The same physical tick expressed a full turn away must still read as
        // visible — spans are laid out across many turns, but the screen only
        // has one.
        #expect(FocusWheelGeometry.carouselRulerTickIsVisible(angle: 90 + 360, window: window))
        #expect(FocusWheelGeometry.carouselRulerTickIsVisible(angle: 90 - 720, window: window))
        // A window straddling the 0°/360° seam still catches a tick just past it.
        let seam = (start: 350.0, end: 370.0)
        #expect(FocusWheelGeometry.carouselRulerTickIsVisible(angle: 5, window: seam))
    }

    @Test("The active title sits a fixed offset above the centre control, at every dial size")
    func activeTitleCentreSitsAboveTheHub() {
        let dialCentre = CGPoint(x: 100, y: 200)
        let title = FocusWheelGeometry.carouselActiveTitleCentre(dialCentre: dialCentre)
        #expect(title.x == dialCentre.x)
        #expect(title.y == dialCentre.y - (FlowControlSize.hero / 2 + FlowSpacing.l))
    }

    @Test("The hub's remaining minutes count down from the total as the task runs")
    func remainingMinutesCountDownAsTheTaskRuns() {
        #expect(FocusWheelGeometry.carouselActiveRemainingMinutes(totalMinutes: 30, elapsed: 0) == 30)
        #expect(FocusWheelGeometry.carouselActiveRemainingMinutes(totalMinutes: 30, elapsed: 0.5) == 15)
        #expect(FocusWheelGeometry.carouselActiveRemainingMinutes(totalMinutes: 30, elapsed: 1) == 0)
        // Clamped at both ends, so a stray out-of-range fraction never reads as
        // negative minutes or more than the block actually holds.
        #expect(FocusWheelGeometry.carouselActiveRemainingMinutes(totalMinutes: 30, elapsed: -0.2) == 30)
        #expect(FocusWheelGeometry.carouselActiveRemainingMinutes(totalMinutes: 30, elapsed: 1.2) == 0)
    }

    @Test("A representative single-task close-up at 8x still leaves one legible numeral on screen")
    func deepCloseUpKeepsALegibleNumeralOnScreen() throws {
        // Mirrors FocusWheelView.carousel(in:) exactly: the magnify style pins
        // the layout to the `.all` widths, so a single active task fills the
        // whole ring and its ruler tape wraps the full circle.
        let totalMinutes = 30
        let elapsed = 0.0
        let durations = [totalMinutes]
        let zoom = FocusWheelGeometry.carouselZoom(for: .all)
        let magnification = 8.0

        let activeSpan = try #require(FocusWheelGeometry.carouselSpans(
            zoom: zoom, durations: durations, rotation: 0, elapsed: elapsed
        ).first)
        let settledWidth = try #require(FocusWheelGeometry.carouselWidths(
            zoom: zoom, durations: durations, elapsed: elapsed
        ).first)
        let tapeSpan = FocusWheelGeometry.carouselRulerTapeSpan(activeSpan: activeSpan, settledWidth: settledWidth)
        let topTick = FocusWheelGeometry.carouselRulerTopTick(totalMinutes: totalMinutes, elapsed: elapsed)
        let window = FocusWheelGeometry.magnifyVisibleWindow(radius: radius, factor: magnification, viewport: viewport)

        let fontSize: CGFloat = 10
        let labelStep = FocusWheelGeometry.carouselRulerLabelStep(
            totalMinutes: totalMinutes,
            spanDegrees: activeSpan.end - activeSpan.start,
            numeralRadius: FocusWheelGeometry.magnifiedRadius(120, factor: magnification),
            fontSize: fontSize
        )

        var sawAVisibleNumeral = false
        for remaining in stride(from: topTick, through: 0, by: -1) {
            let showsLabel = remaining == totalMinutes || remaining == 0 || remaining % labelStep == 0
            guard showsLabel else { continue }
            let angle = FocusWheelGeometry.carouselRulerAngle(
                minutesRemaining: remaining, totalMinutes: totalMinutes, span: tapeSpan
            )
            if FocusWheelGeometry.carouselRulerTickIsVisible(angle: angle, window: window) {
                sawAVisibleNumeral = true
            }
        }
        // Legibility is structural now — numerals are drawn outside the scaled
        // group at their own native size — so the gate is the cadence itself:
        // the label step must still put at least one numeral in the window.
        #expect(sawAVisibleNumeral)
    }

    @Test("A representative single-task close-up at 8x still leaves one legible numeral on screen moments after the task starts")
    func deepCloseUpKeepsALegibleNumeralOnScreenShortlyAfterStart() throws {
        // Same scenario as `deepCloseUpKeepsALegibleNumeralOnScreen`, but one
        // minute into a 30-minute task (`elapsed = 1/30`), matching the
        // coordinator's own repro screenshot (p3-raw-m8.png, active title
        // "29M"). Elapsed `0` is the ONLY instant at which the tape's
        // `0`/`totalMinutes` endpoints coincide with the pointer inside the
        // visible window at 8x (half-angle ~7.52° for this viewport, crossover
        // at elapsed ~0.0209) — `1/30 ≈ 0.0333` is past that crossover with
        // clear margin, so both endpoints have rotated out of the window and
        // the label cadence (every 5 minutes on a 30-minute block) provides no
        // replacement numeral until several more minutes have passed. This is
        // Task 53: the ruler renders zero numerals once the active task is
        // actually running.
        let totalMinutes = 30
        let elapsed = 1.0 / 30.0
        let durations = [totalMinutes]
        let zoom = FocusWheelGeometry.carouselZoom(for: .all)
        let magnification = 8.0

        let activeSpan = try #require(FocusWheelGeometry.carouselSpans(
            zoom: zoom, durations: durations, rotation: 0, elapsed: elapsed
        ).first)
        let settledWidth = try #require(FocusWheelGeometry.carouselWidths(
            zoom: zoom, durations: durations, elapsed: elapsed
        ).first)
        let tapeSpan = FocusWheelGeometry.carouselRulerTapeSpan(activeSpan: activeSpan, settledWidth: settledWidth)
        let topTick = FocusWheelGeometry.carouselRulerTopTick(totalMinutes: totalMinutes, elapsed: elapsed)
        let window = FocusWheelGeometry.magnifyVisibleWindow(radius: radius, factor: magnification, viewport: viewport)

        let fontSize: CGFloat = 10
        // `spanDegrees` and `visibleWindowDegrees` mirror the production call
        // site (`FocusWheelView.rulerPlan`) exactly: the settled width
        // (not the shrinking active span) and the close-up's own visible
        // window, which is what starves the cadence at deep magnification.
        let labelStep = FocusWheelGeometry.carouselRulerLabelStep(
            totalMinutes: totalMinutes,
            spanDegrees: settledWidth,
            numeralRadius: FocusWheelGeometry.magnifiedRadius(120, factor: magnification),
            fontSize: fontSize,
            visibleWindowDegrees: window.end - window.start
        )

        var sawAVisibleNumeral = false
        for remaining in stride(from: topTick, through: 0, by: -1) {
            let showsLabel = remaining == totalMinutes || remaining == 0 || remaining % labelStep == 0
            guard showsLabel else { continue }
            let angle = FocusWheelGeometry.carouselRulerAngle(
                minutesRemaining: remaining, totalMinutes: totalMinutes, span: tapeSpan
            )
            if FocusWheelGeometry.carouselRulerTickIsVisible(angle: angle, window: window) {
                sawAVisibleNumeral = true
            }
        }
        #expect(sawAVisibleNumeral)
    }

    @Test("The dial centre's close-up image leaves the pointer exactly where it was")
    func magnifiedDialCentreKeepsThePointerFixed() {
        // At rest the text layer sits exactly where the drawing does.
        let centre = FocusWheelGeometry.carouselCentre(in: viewport)
        let rest = FocusWheelGeometry.magnifiedDialCentre(in: viewport, factor: 1)
        #expect(abs(rest.x - centre.x) < 0.0001)
        #expect(abs(rest.y - centre.y) < 0.0001)

        // The pointer is the close-up transform's fixed point: text placed at
        // the pointer's angle on the magnified wheel must land on the same
        // screen point at every factor, or the crisp text layer would drift
        // off the scaled drawing beneath it.
        let restPointer = FocusWheelGeometry.point(
            centre: centre, radius: radius, angle: FocusWheelGeometry.bottomAngle
        )
        for m in [2.0, 4.0, 8.0] {
            let magCentre = FocusWheelGeometry.magnifiedDialCentre(in: viewport, factor: m)
            let magPointer = FocusWheelGeometry.point(
                centre: magCentre,
                radius: FocusWheelGeometry.magnifiedRadius(radius, factor: m),
                angle: FocusWheelGeometry.bottomAngle
            )
            #expect(abs(magPointer.x - restPointer.x) < 0.001)
            #expect(abs(magPointer.y - restPointer.y) < 0.001)
            // The centre itself retreats upward as the ring grows past the top.
            #expect(magCentre.y < centre.y)
        }
    }

    @Test("A span's visible width is the clipped arc, by the labels' own clipping rule")
    func clippedSpanVisibleWidthMatchesTheWindow() throws {
        let window = FocusWheelGeometry.magnifyVisibleWindow(
            radius: radius, factor: 4, viewport: viewport
        )
        // Fully on screen: the width comes back untouched.
        let width = FocusWheelGeometry.clippedSpanVisibleWidth(
            start: window.start + 1, end: window.start + 5, window: window
        )
        #expect(width == 4)

        // A long block reaching the pointer from far anticlockwise: only the
        // on-screen part counts, and the label's midpoint is that part's centre.
        let start = FocusWheelGeometry.bottomAngle - 200
        let end = FocusWheelGeometry.bottomAngle - 2
        let visible = try #require(FocusWheelGeometry.clippedSpanVisibleWidth(
            start: start, end: end, window: window
        ))
        #expect(visible < end - start)
        let mid = try #require(FocusWheelGeometry.clippedSpanMidAngle(
            start: start, end: end, window: window
        ))
        #expect(abs((mid - window.start) - visible / 2) < 0.0001)

        // Entirely off screen: no width at all.
        #expect(FocusWheelGeometry.clippedSpanVisibleWidth(
            start: FocusWheelGeometry.bottomAngle - 200,
            end: FocusWheelGeometry.bottomAngle - 150,
            window: window
        ) == nil)

        // At rest nothing is clipped, so the whole-circle layout is untouched.
        let restWindow = FocusWheelGeometry.magnifyVisibleWindow(
            radius: radius, factor: 1, viewport: viewport
        )
        #expect(FocusWheelGeometry.clippedSpanVisibleWidth(
            start: -30, end: 30, window: restWindow
        ) == 60)
    }

    @Test("The FREE caption's minimum span shrinks with the close-up, because its arc on screen grows")
    func freeCaptionMinimumSpanScalesWithTheCloseUp() {
        #expect(FocusWheelGeometry.minimumFreeLabelSpanDegrees(factor: 1) == 18)
        #expect(FocusWheelGeometry.minimumFreeLabelSpanDegrees(factor: 4) == 4.5)
        // Clamped with the magnification itself, at both ends.
        #expect(FocusWheelGeometry.minimumFreeLabelSpanDegrees(factor: 0.2) == 18)
        #expect(FocusWheelGeometry.minimumFreeLabelSpanDegrees(factor: 100) == 18.0 / 8)
    }

    @Test("The ruler's radii magnify as one set, so crisp ticks land on the scaled band")
    func rulerRadiiMagnifyAsOneSet() {
        let radii = FocusWheelGeometry.carouselRulerRadii(innerRadius: 120, thickness: 60)
        let magnified = radii.magnified(factor: 4)
        // Every track scales by the same clamped factor as the drawing — a
        // tick painted between magnified base and tip sits exactly on the
        // close-up band while its stroke stays native-width.
        #expect(magnified.numeral == FocusWheelGeometry.magnifiedRadius(radii.numeral, factor: 4))
        #expect(magnified.tickBase == FocusWheelGeometry.magnifiedRadius(radii.tickBase, factor: 4))
        #expect(magnified.minorTip == FocusWheelGeometry.magnifiedRadius(radii.minorTip, factor: 4))
        #expect(magnified.mediumTip == FocusWheelGeometry.magnifiedRadius(radii.mediumTip, factor: 4))
        #expect(magnified.majorTip == FocusWheelGeometry.magnifiedRadius(radii.majorTip, factor: 4))
        // Tier lookup survives the scaling untouched.
        #expect(magnified.tip(for: .major) == magnified.majorTip)
        // At rest the set is the identity, and a wild factor clamps like
        // every other close-up input.
        #expect(radii.magnified(factor: 1).tickBase == radii.tickBase)
        #expect(radii.magnified(factor: 100).majorTip == radii.majorTip * 8)
    }
}

@Suite("Neighbour labels")
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

// MARK: - Empty-state signposting (Task 61)

@Suite("Focus empty-state signposting")
@MainActor
struct FocusEmptyStateTests {
    @Test("Waiting inbox tasks flip the empty screen to the plan prompt")
    func inboxTasksSelectThePlanPrompt() {
        #expect(FocusScreen.emptyState(inboxCount: 0) == .dayDone)
        #expect(FocusScreen.emptyState(inboxCount: 1) == .planPrompt(inboxCount: 1))
        #expect(FocusScreen.emptyState(inboxCount: 7) == .planPrompt(inboxCount: 7))
    }

    @Test("The prompt's count reads as a sentence in singular and plural")
    func planPromptMessageMatchesTheCount() {
        #expect(FocusScreen.planPromptMessage(inboxCount: 1) == "1 task in your Inbox is waiting to be planned.")
        #expect(FocusScreen.planPromptMessage(inboxCount: 3) == "3 tasks in your Inbox are waiting to be planned.")
    }
}

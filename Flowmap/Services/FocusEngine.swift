import Foundation
import Observation
import SwiftData

/// What the app should tell the user after a task's time ran out.
public struct FocusTransition: Identifiable, Sendable {
    public let id = UUID()
    public let finishedTaskTitle: String
    public let requeue: RequeueOutcome?
    public let nextTaskTitle: String?
    /// Whether adding more time to the finished task is still possible.
    public let canExtend: Bool

    /// `Reading requeued for 20 minutes at 16:10`
    public var bannerText: String {
        if let requeue { return requeue.bannerText }
        return "\(finishedTaskTitle) finished"
    }
}

/// What the compulsory planning phase demands before a task's clock can
/// start: a Definition of Done the first time a task is ever started, a
/// lighter re-confirmation whenever unfinished work comes back around.
public enum TaskGate: Equatable, Sendable {
    case planGate
    case clockIn
}

/// The task (and, for a scheduled start, the segment) currently waiting on a
/// `TaskGate`. Any view can render this; nothing may start the session it
/// describes until `FocusEngine.resolveGate` is called.
public struct PendingGate {
    public let task: FlowTask
    public let segment: TaskSegment?
    public let kind: TaskGate
    /// The caller's requested length for a non-timeline start, carried
    /// through the gate so resolving it starts the same length that was
    /// asked for rather than falling back to the task's default.
    public let minutes: Int?
}

/// Drives the focus timer and the automatic hand-off between tasks.
///
/// All timing lives in `FocusSession` as timestamps; this type only decides
/// *when* to act on them. That keeps the timer correct across backgrounding,
/// sleep, relaunch and a second device.
@Observable
@MainActor
public final class FocusEngine {
    private let context: ModelContext
    private let settings: AppSettings
    private let calendar: Calendar
    /// Speaks task-start, time-left and wind-down announcements. Optional so
    /// existing call sites (tests, App Intents) need not supply one.
    private let voiceService: FocusVoiceService?
    /// Raises the `COMPLETE` band when a task finishes. Optional for the same
    /// reason `voiceService` is.
    private let moments: FlowMomentService?
    /// The tick, the time-up bell and the completion chime. Stateless, so it
    /// is built here rather than injected.
    private let sounds = FlowSoundService()
    /// Read fresh on every use. A continuation placed by the focus timer must
    /// respect the user's real calendar, and a snapshot taken at init would be
    /// empty at launch and stale forever after.
    public var externalEventsProvider: () -> [ExternalCalendarEvent] = { [] }

    /// The session currently on screen, if any.
    public private(set) var activeSession: FocusSession?
    /// Set when a task's time has just run out, for the non-blocking banner.
    public var pendingTransition: FocusTransition?
    /// Set instead of starting, when the compulsory planning phase blocks a
    /// start. The view renders the plan gate or the clock-in dialog from
    /// this; resolve it via `resolveGate`, never by calling `start` again.
    public var pendingGate: PendingGate?
    /// Drives the countdown redraw. Bumped by the view's timer tick.
    public var tick: Date = Date()

    public init(
        context: ModelContext,
        settings: AppSettings,
        externalEvents: [ExternalCalendarEvent] = [],
        calendar: Calendar = .current,
        voiceService: FocusVoiceService? = nil,
        moments: FlowMomentService? = nil
    ) {
        self.context = context
        self.settings = settings
        self.calendar = calendar
        self.voiceService = voiceService
        self.moments = moments
        self.externalEventsProvider = { externalEvents }
        self.activeSession = Self.findRunningSession(in: context)
    }

    // MARK: - Session lookup

    /// The session left running by a previous launch, if there is one.
    public static func findRunningSession(in context: ModelContext) -> FocusSession? {
        let running = FocusOutcome.running.rawValue
        var descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.outcomeRaw == running },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func schedulingService() -> SchedulingService {
        SchedulingService(
            context: context,
            settings: settings,
            externalEvents: externalEventsProvider(),
            calendar: calendar
        )
    }

    private func gamificationService() -> GamificationService {
        GamificationService(context: context, settings: settings)
    }

    // MARK: - Today's queue

    /// Every segment starting on `day`, in any state — the day-cleared check
    /// needs the terminal ones too, which `queue(for:)` deliberately excludes.
    private func segments(on day: Date) -> [TaskSegment] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let segments = (try? context.fetch(FetchDescriptor<TaskSegment>())) ?? []
        return segments.filter { $0.startDate >= dayStart && $0.startDate < dayEnd }
    }

    /// Scheduled segments for `day`, earliest first — the order the wheel walks.
    public func queue(for day: Date = Date()) -> [TaskSegment] {
        segments(on: day)
            .filter { $0.state == .scheduled || $0.state == .elapsed }
            .filter { $0.task?.status.isOpen ?? false }
            .sorted { $0.startDate < $1.startDate }
    }

    /// The segment that should be running at `date`, else the next one due.
    public func currentSegment(at date: Date = Date()) -> TaskSegment? {
        let today = queue(for: date)
        return today.first { $0.contains(date) } ?? today.first { $0.startDate >= date }
    }

    /// Upcoming segments after the active one.
    public func upcomingSegments(after segment: TaskSegment?, at date: Date = Date()) -> [TaskSegment] {
        let today = queue(for: date)
        guard let segment, let index = today.firstIndex(where: { $0.id == segment.id }) else {
            return today
        }
        return Array(today.dropFirst(index + 1))
    }

    // MARK: - Starting

    /// Starts focus on a scheduled block, using the time it has left.
    ///
    /// Returns `nil` and sets `pendingGate` instead of starting when the
    /// compulsory planning phase blocks this task — the caller must not
    /// treat a `nil` result the same as a failure to find a session.
    @discardableResult
    public func start(segment: TaskSegment, now: Date = Date()) -> FocusSession? {
        guard let task = segment.task else { return nil }
        // Resume rather than restart if this block is already running.
        if let existing = activeSession, existing.segment?.id == segment.id, existing.outcome == .running {
            existing.resume(at: now)
            return existing
        }
        if let kind = gateDecision(for: task, segment: segment) {
            pendingGate = PendingGate(task: task, segment: segment, kind: kind, minutes: nil)
            return nil
        }
        return beginSegment(segment, task: task, now: now)
    }

    /// Starts focus on a task that is not on the timeline. Subject to the
    /// same gate as `start(segment:)` — see that method's note on `nil`.
    @discardableResult
    public func start(task: FlowTask, minutes: Int? = nil, now: Date = Date()) -> FocusSession? {
        if let kind = gateDecision(for: task, segment: nil) {
            pendingGate = PendingGate(task: task, segment: nil, kind: kind, minutes: minutes)
            return nil
        }
        return beginTask(task, minutes: minutes, now: now)
    }

    private func beginSegment(_ segment: TaskSegment, task: FlowTask, now: Date) -> FocusSession {
        finishActiveSession(outcome: .skipped, now: now)
        let remaining = segment.remainingSeconds(at: now)
        let planned = remaining > 0 ? remaining : Double(segment.durationMinutes) * 60
        return begin(task: task, segment: segment, seconds: planned, now: now)
    }

    private func beginTask(_ task: FlowTask, minutes: Int?, now: Date) -> FocusSession {
        finishActiveSession(outcome: .skipped, now: now)
        let length = minutes ?? max(SchedulingEngine.snapMinutes, task.unscheduledMinutes > 0 ? task.unscheduledMinutes : task.estimatedMinutes)
        return begin(task: task, segment: task.segment(at: now), seconds: Double(length) * 60, now: now)
    }

    // MARK: - Compulsory planning gate

    /// The gate decision for starting `task`, or `nil` to start immediately.
    ///
    /// A task never starts, by any path, without a Definition of Done —
    /// that is the product's "compulsory planning phase" and applies to the
    /// Assistant and App Intents exactly as it does to a tap on the wheel.
    /// Once planned, only a task RETURNING via a requeued/carried-over
    /// segment (`isContinuation`) asks for a conscious clock-in — the
    /// design's own words are "unfinished work always comes around again".
    /// A first-ever segment for an already-planned task, or an ad hoc
    /// (non-timeline) start, proceeds without any modal.
    private func gateDecision(for task: FlowTask, segment: TaskSegment?) -> TaskGate? {
        if !task.hasBeenPlanned { return .planGate }
        if segment?.isContinuation == true { return .clockIn }
        return nil
    }

    /// Resolves `pendingGate`: records the Definition of Done and marks the
    /// task planned (first-time gate only), then starts the segment or task
    /// it was blocking. This call IS the gate's resolution, so it starts via
    /// the private `begin…` helpers directly rather than asking
    /// `gateDecision` again — asking again would just re-block on a task
    /// this same call is about to mark planned.
    ///
    /// Enforced here, not just in the view: an empty Definition of Done
    /// leaves `pendingGate` untouched and returns `nil` — "blocked" means
    /// blocked even for a caller that skips `PlanGateDialog` entirely.
    @discardableResult
    public func resolveGate(definitionOfDone: String? = nil, now: Date = Date()) -> FocusSession? {
        guard let pending = pendingGate else { return nil }
        if pending.kind == .planGate {
            let trimmed = (definitionOfDone ?? pending.task.definitionOfDone)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            pending.task.definitionOfDone = trimmed
            pending.task.hasBeenPlanned = true
            try? context.save()
            gamificationService().award(.taskPlanned)
        }
        pendingGate = nil
        if let segment = pending.segment {
            return beginSegment(segment, task: pending.task, now: now)
        }
        return beginTask(pending.task, minutes: pending.minutes, now: now)
    }

    /// Free focus with no task attached. Defaults to 30 minutes.
    @discardableResult
    public func startFreeFocus(minutes: Int? = nil, now: Date = Date()) -> FocusSession? {
        finishActiveSession(outcome: .skipped, now: now)
        let length = minutes ?? settings.defaultFreeFocusMinutes
        return begin(task: nil, segment: nil, seconds: Double(length) * 60, now: now)
    }

    private func begin(task: FlowTask?, segment: TaskSegment?, seconds: Double, now: Date) -> FocusSession {
        let session = FocusSession(
            task: task,
            segment: segment,
            plannedSeconds: max(60, seconds),
            startedAt: now
        )
        context.insert(session)
        if let task, task.status.isOpen { task.status = .active }
        try? context.save()
        activeSession = session
        if let task {
            voiceService?.announceTaskStart(title: task.title, settings: settings)
        }
        return session
    }

    // MARK: - Controls

    public func pause(now: Date = Date()) {
        guard let session = activeSession else { return }
        session.pause(at: now)
        session.task?.status = .paused
        try? context.save()
    }

    public func resume(now: Date = Date()) {
        guard let session = activeSession else { return }
        session.resume(at: now)
        if let task = session.task, task.status == .paused { task.status = .active }
        try? context.save()
    }

    public func togglePause(now: Date = Date()) {
        guard let session = activeSession else { return }
        session.isPaused ? resume(now: now) : pause(now: now)
    }

    /// Marks the task done and moves on.
    public func completeCurrentTask(now: Date = Date()) {
        guard let session = activeSession else { return }
        let title = session.task?.title ?? "Focus"
        session.finish(outcome: .completed, at: now)
        _ = session.claimTransition()

        if let task = session.task {
            task.actualMinutes += session.actualMinutes
            task.markCompleted(at: now)
            moments?.show(.done(taskTitle: task.title))
            sounds.play(.chime, settings: settings)
            gamificationService().award(.taskCompleted(estimatedMinutes: task.estimatedMinutes))
        }
        if let segment = session.segment { segment.state = .completed }
        try? context.save()

        activeSession = nil
        voiceService?.sessionEnded(sessionID: session.id)
        advanceToNextTask(now: now, finishedTitle: title, requeue: nil)
    }

    /// Skips the rest of this block without completing the task. The remaining
    /// work is requeued — skipping is not the same as abandoning.
    public func skipCurrentTask(now: Date = Date()) {
        guard let session = activeSession else { return }
        let title = session.task?.title ?? "Focus"
        let remainingMinutes = Int((session.remainingSeconds(at: now) / 60).rounded())
        session.finish(outcome: .skipped, at: now)
        let claimed = session.claimTransition()

        if let task = session.task {
            task.actualMinutes += session.actualMinutes
            if task.status == .active || task.status == .paused { task.status = .planned }
        }
        if let segment = session.segment { segment.state = .missed }
        try? context.save()

        var requeue: RequeueOutcome?
        if claimed, let task = session.task, remainingMinutes >= SchedulingEngine.snapMinutes {
            requeue = schedulingService().scheduleContinuation(
                for: task, after: session.segment, minutes: remainingMinutes, now: now
            )
        }

        activeSession = nil
        voiceService?.sessionEnded(sessionID: session.id)
        advanceToNextTask(now: now, finishedTitle: title, requeue: requeue)
    }

    /// Adds time to the task currently on screen without restarting it.
    public func extendCurrentTask(byMinutes minutes: Int, now: Date = Date()) {
        guard let session = activeSession else { return }
        session.plannedSeconds += Double(minutes) * 60
        session.touch(now)
        if let segment = session.segment, !segment.isLocked {
            let service = schedulingService()
            _ = service.resize(segment: segment, toMinutes: segment.durationMinutes + minutes)
        }
        try? context.save()
    }

    /// Abandons the session entirely, leaving the task where it was.
    public func stop(now: Date = Date()) {
        guard let session = activeSession else { return }
        session.finish(outcome: .abandoned, at: now)
        _ = session.claimTransition()
        if let task = session.task {
            task.actualMinutes += session.actualMinutes
            if task.status == .active || task.status == .paused { task.status = .planned }
        }
        try? context.save()
        activeSession = nil
        voiceService?.sessionEnded(sessionID: session.id)
    }

    private func finishActiveSession(outcome: FocusOutcome, now: Date) {
        guard let session = activeSession, session.outcome == .running else { return }
        session.finish(outcome: outcome, at: now)
        _ = session.claimTransition()
        if let task = session.task {
            task.actualMinutes += session.actualMinutes
            if task.status == .active || task.status == .paused { task.status = .planned }
        }
        activeSession = nil
        voiceService?.sessionEnded(sessionID: session.id)
    }

    // MARK: - Elapsed transition

    /// Called on every tick and on app activation.
    ///
    /// Runs the elapsed hand-off at most once per session — `claimTransition()`
    /// is the guard, so two activations or two devices cannot both requeue.
    public func processElapsedSessionIfNeeded(now: Date = Date()) {
        guard let session = activeSession, session.hasElapsed(at: now) else { return }

        let title = session.task?.title ?? "Focus"
        let task = session.task
        let segment = session.segment
        let plannedMinutes = Int((session.plannedSeconds / 60).rounded())

        session.finish(outcome: .elapsed, at: now)
        guard session.claimTransition() else {
            activeSession = nil
            voiceService?.sessionEnded(sessionID: session.id)
            return
        }

        if let task {
            task.actualMinutes += session.actualMinutes
        }
        if let segment { segment.state = .elapsed }
        try? context.save()

        // The bell belongs to this path only — the task's own time ran out. A
        // task the user finished or skipped by hand gets no bell.
        sounds.play(.bell, settings: settings)

        var requeue: RequeueOutcome?
        if let task, task.status != .completed, task.status != .cancelled {
            // Not finished: it needs another block rather than disappearing.
            if task.status == .active || task.status == .paused { task.status = .planned }
            let outstanding = max(SchedulingEngine.snapMinutes, min(plannedMinutes, task.unscheduledMinutes))
            if task.unscheduledMinutes > 0 || task.subtaskProgressLabel != nil {
                requeue = schedulingService().scheduleContinuation(
                    for: task, after: segment, minutes: outstanding, now: now
                )
            }
        }

        activeSession = nil
        voiceService?.sessionEnded(sessionID: session.id)
        advanceToNextTask(now: now, finishedTitle: title, requeue: requeue)
    }

    // MARK: - Voice coach

    /// Speaks the next due time-left, countdown or wind-down announcement for
    /// the active session, if any is newly due. Driven by the app's existing
    /// tick — this adds no timer of its own.
    public func checkVoiceAnnouncements(now: Date = Date()) {
        guard let session = activeSession, session.isRunning else { return }
        // The app's ticker fires once a second, so one tick per call is one
        // tick per second — no second timer needed to pace the sound.
        sounds.play(.tick, settings: settings)
        voiceService?.tick(
            sessionID: session.id,
            taskTitle: session.task?.title ?? "Focus",
            duration: session.plannedSeconds,
            elapsed: session.elapsedSeconds(at: now),
            settings: settings
        )
    }

    /// Rotates to the next scheduled task without asking a blocking question.
    private func advanceToNextTask(now: Date, finishedTitle: String, requeue: RequeueOutcome?) {
        let next = currentSegment(at: now)
        var nextTitle: String?

        if settings.autoStartNextTask, let next, let nextTask = next.task, nextTask.status.isOpen {
            nextTitle = nextTask.title
            _ = start(segment: next, now: now)
        } else {
            nextTitle = next?.task?.title
        }

        pendingTransition = FocusTransition(
            finishedTaskTitle: finishedTitle,
            requeue: requeue,
            nextTaskTitle: nextTitle,
            canExtend: requeue != nil
        )
        awardDayClearedIfNeeded(now: now)
    }

    /// Awards the day-cleared bonus the first time every one of today's
    /// segments has reached a terminal state (completed, missed or
    /// cancelled — `.elapsed` is excluded, since it means a task's time ran
    /// out without being resolved either way) with at least one completed.
    /// Guarded by `lastDayClearedAwardDay` so re-checking after every later
    /// transition on the same day, or a second device doing the same, cannot
    /// award it twice.
    private func awardDayClearedIfNeeded(now: Date) {
        let dayStart = calendar.startOfDay(for: now)
        if let last = settings.lastDayClearedAwardDay, calendar.isDate(last, inSameDayAs: now) { return }
        let today = segments(on: now)
        guard !today.isEmpty else { return }
        let terminal: Set<SegmentState> = [.completed, .missed, .cancelled]
        guard today.allSatisfy({ terminal.contains($0.state) }) else { return }
        guard today.contains(where: { $0.state == .completed }) else { return }
        gamificationService().award(.dayCleared)
        settings.lastDayClearedAwardDay = dayStart
        try? context.save()
    }

    /// Undoes a requeue the user rejected from the banner.
    public func undoRequeue(_ outcome: RequeueOutcome) {
        let segments = (try? context.fetch(FetchDescriptor<TaskSegment>())) ?? []
        let tasks = (try? context.fetch(FetchDescriptor<FlowTask>())) ?? []
        guard let task = tasks.first(where: { $0.id == outcome.taskID }) else { return }

        for segment in segments
        where segment.task?.id == task.id
            && segment.isContinuation
            && segment.state == .scheduled
            && segment.startDate == outcome.newStart {
            context.delete(segment)
        }
        task.carryoverCount = max(0, task.carryoverCount - 1)
        try? context.save()
        pendingTransition = nil
    }

    /// Marks the finished task complete straight from the banner.
    public func completeFromBanner(_ outcome: RequeueOutcome) {
        let tasks = (try? context.fetch(FetchDescriptor<FlowTask>())) ?? []
        guard let task = tasks.first(where: { $0.id == outcome.taskID }) else { return }
        // Remove the continuation the requeue just created: the work is done.
        for segment in task.liveSegments where segment.isContinuation && segment.state == .scheduled {
            context.delete(segment)
        }
        task.markCompleted()
        moments?.show(.done(taskTitle: task.title))
        sounds.play(.chime, settings: settings)
        gamificationService().award(.taskCompleted(estimatedMinutes: task.estimatedMinutes))
        try? context.save()
        pendingTransition = nil
        awardDayClearedIfNeeded(now: Date())
    }
}

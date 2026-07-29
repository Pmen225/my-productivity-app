import Foundation
import SwiftData

/// What happened to one task during reconciliation, so the UI can show a
/// non-blocking banner such as `Reading requeued for 20 minutes at 16:10`.
public struct RequeueOutcome: Identifiable, Sendable {
    public let id = UUID()
    public let taskID: UUID
    public let taskTitle: String
    public let minutes: Int
    public let newStart: Date?
    public let movedToAnotherDay: Bool
    /// Set when the work could not be placed anywhere in the lookahead window.
    public let failureReason: String?

    public var bannerText: String {
        if let failureReason { return failureReason }
        guard let newStart else { return "\(taskTitle) is waiting in your Inbox." }
        let time = DurationFormatter.time(newStart)
        let duration = DurationFormatter.compact(minutes: minutes)
        return movedToAnotherDay
            ? "\(taskTitle) requeued for \(duration) tomorrow at \(time)"
            : "\(taskTitle) requeued for \(duration) at \(time)"
    }
}

/// Bridges the pure `SchedulingEngine` to the SwiftData store: reads the current
/// schedule, applies proposals, undoes them, and reconciles missed work.
@MainActor
public struct SchedulingService {
    /// How far ahead the planner will look for a home for outstanding work.
    public static let lookaheadDays = 14

    private let context: ModelContext
    private let settings: AppSettings
    private let engine: SchedulingEngine
    private let calendar: Calendar
    /// External calendar events, supplied by `CalendarService` when integration is on.
    private let externalEvents: [ExternalCalendarEvent]

    public init(
        context: ModelContext,
        settings: AppSettings,
        externalEvents: [ExternalCalendarEvent] = [],
        calendar: Calendar = .current
    ) {
        self.context = context
        self.settings = settings
        self.externalEvents = externalEvents
        self.calendar = calendar
        self.engine = SchedulingEngine(settings: settings, calendar: calendar)
    }

    // MARK: - Reading the current schedule

    public func allSegments() -> [TaskSegment] {
        (try? context.fetch(FetchDescriptor<TaskSegment>())) ?? []
    }

    public func allTasks() -> [FlowTask] {
        (try? context.fetch(FetchDescriptor<FlowTask>())) ?? []
    }

    /// Everything already occupying time, keyed by day.
    ///
    /// - Parameter movableSegmentIDs: segments the caller intends to reposition;
    ///   they are excluded so the planner can reuse their time.
    public func busyMap(
        from day: Date,
        dayCount: Int,
        excluding movableSegmentIDs: Set<UUID> = []
    ) -> [Date: [BusyInterval]] {
        var map: [Date: [BusyInterval]] = [:]
        let firstDay = calendar.startOfDay(for: day)
        guard let lastDay = calendar.date(byAdding: .day, value: dayCount, to: firstDay) else {
            return map
        }

        for segment in allSegments() {
            guard segment.state.occupiesTimeline else { continue }
            guard segment.startDate < lastDay, segment.endDate > firstDay else { continue }
            guard !movableSegmentIDs.contains(segment.id) else { continue }
            let key = calendar.startOfDay(for: segment.startDate)
            map[key, default: []].append(
                BusyInterval(
                    start: segment.startDate,
                    end: segment.endDate,
                    kind: segment.isLocked ? .lockedSegment : .movableSegment,
                    segmentID: segment.id
                )
            )
        }

        // External events are fixed. They are never moved and never overwritten.
        for event in externalEvents {
            guard event.start < lastDay, event.end > firstDay else { continue }
            let key = calendar.startOfDay(for: event.start)
            map[key, default: []].append(
                BusyInterval(start: event.start, end: event.end, kind: .externalEvent)
            )
        }

        return map
    }

    // MARK: - Planning

    /// Builds a plan for `day` without writing anything.
    ///
    /// - Parameter replanExisting: when `true`, unlocked blocks already on the day
    ///   may be picked up and moved. When `false` — the default `Plan my day`
    ///   behaviour — existing placements are respected and only gaps are filled.
    public func proposePlan(
        for day: Date,
        now: Date = Date(),
        replanExisting: Bool = false
    ) -> PlanProposal {
        var proposal = PlanProposal()
        let dayStart = calendar.startOfDay(for: day)
        let isToday = calendar.isDate(day, inSameDayAs: now)
        // Never propose a slot in the past.
        let floor = isToday ? now : nil

        // Blocks that may be lifted and re-placed.
        var movableSegmentIDs: Set<UUID> = []
        if replanExisting {
            for segment in allSegments()
            where segment.state == .scheduled
                && !segment.isLocked
                && calendar.isDate(segment.startDate, inSameDayAs: day)
                && segment.startDate >= (floor ?? .distantPast) {
                movableSegmentIDs.insert(segment.id)
            }
        }

        var busyByDay = busyMap(
            from: dayStart,
            dayCount: Self.lookaheadDays,
            excluding: movableSegmentIDs
        )

        // Segments left in place are reported so the preview can show them as unchanged.
        for segment in allSegments()
        where segment.state == .scheduled
            && calendar.isDate(segment.startDate, inSameDayAs: day)
            && !movableSegmentIDs.contains(segment.id) {
            proposal.unchangedSegmentIDs.insert(segment.id)
        }

        // Tasks whose lifted segments now count as unscheduled again.
        let liftedMinutesByTask = liftedMinutes(for: movableSegmentIDs)

        for task in engine.candidates(from: allTasks(), on: day, now: now) {
            let outstanding = task.unscheduledMinutes + (liftedMinutesByTask[task.id] ?? 0)
            guard outstanding > 0 else { continue }

            let result = place(
                task: task,
                outstandingMinutes: outstanding,
                day: day,
                busyByDay: &busyByDay,
                notBefore: floor,
                source: .autoPlanned,
                startingSequenceIndex: task.liveSegments.count
            )

            proposal.blocks.append(contentsOf: result.blocks)
            if result.usedFutureDay { proposal.deferredTaskIDs.insert(task.id) }
            if result.remainingMinutes > 0 {
                proposal.unplaceable[task.id] = engine.unplaceableReason(
                    for: task, remainingMinutes: result.remainingMinutes
                )
            }
        }

        return proposal
    }

    /// Runs `SchedulingEngine.placeTask` with a temporarily overridden outstanding
    /// figure, used when existing blocks were lifted for a full replan.
    private func place(
        task: FlowTask,
        outstandingMinutes: Int,
        day: Date,
        busyByDay: inout [Date: [BusyInterval]],
        notBefore: Date?,
        source: SegmentSource,
        startingSequenceIndex: Int
    ) -> (blocks: [PlannedBlock], remainingMinutes: Int, usedFutureDay: Bool) {
        let originalEstimate = task.estimatedMinutes
        let alreadyScheduled = task.scheduledMinutes
        // `placeTask` reads `unscheduledMinutes`; align the estimate so the figure
        // it sees is exactly the work we want placed.
        task.estimatedMinutes = alreadyScheduled + outstandingMinutes
        defer { task.estimatedMinutes = originalEstimate }

        return engine.placeTask(
            task,
            startingOn: day,
            busyByDay: &busyByDay,
            notBefore: notBefore,
            lookaheadDays: Self.lookaheadDays,
            source: source,
            startingSequenceIndex: startingSequenceIndex
        )
    }

    private func liftedMinutes(for segmentIDs: Set<UUID>) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for segment in allSegments() where segmentIDs.contains(segment.id) {
            guard let taskID = segment.task?.id else { continue }
            result[taskID, default: 0] += segment.durationMinutes
        }
        return result
    }

    // MARK: - Applying and undoing

    /// Writes a proposal to the store and returns everything needed to undo it.
    @discardableResult
    public func apply(_ proposal: PlanProposal, replanExisting: Bool = false, for day: Date) -> ScheduleSnapshot {
        let tasksByID = Dictionary(allTasks().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Snapshot before touching anything.
        var previous: [ScheduleSnapshot.SegmentState] = []
        var taskStatuses: [UUID: String] = [:]
        for segment in allSegments() {
            previous.append(
                ScheduleSnapshot.SegmentState(
                    id: segment.id,
                    start: segment.startDate,
                    end: segment.endDate,
                    stateRaw: segment.stateRaw,
                    sourceRaw: segment.sourceRaw,
                    sequenceIndex: segment.sequenceIndex
                )
            )
        }
        for task in tasksByID.values { taskStatuses[task.id] = task.statusRaw }

        // A full replan releases the unlocked blocks it lifted.
        if replanExisting {
            for segment in allSegments()
            where segment.state == .scheduled
                && !segment.isLocked
                && calendar.isDate(segment.startDate, inSameDayAs: day)
                && !proposal.unchangedSegmentIDs.contains(segment.id) {
                context.delete(segment)
            }
        }

        var created: Set<UUID> = []
        for block in proposal.blocks {
            guard let task = tasksByID[block.taskID] else { continue }
            let segment = TaskSegment(
                task: task,
                startDate: block.start,
                endDate: block.end,
                state: .scheduled,
                isLocked: false,
                sequenceIndex: block.sequenceIndex,
                source: block.source
            )
            context.insert(segment)
            created.insert(segment.id)
            if task.status == .inbox { task.status = .planned }
        }

        // Saved first so pending deletes are actually applied: until then a
        // lifted segment still shows up in `task.liveSegments` and the sweep
        // below would see nothing to do.
        try? context.save()

        // A full replan lifts existing blocks before re-placing them. Anything
        // that could not be re-placed must land back in the Inbox — a task left
        // `.planned` with no segments matches neither Inbox nor Today, which is
        // exactly the silent disappearance the product forbids.
        var strandedAny = false
        for task in tasksByID.values
        where task.status == .planned && task.liveSegments.isEmpty {
            task.status = .inbox
            strandedAny = true
        }
        if strandedAny { try? context.save() }

        return ScheduleSnapshot(
            existing: previous,
            createdSegmentIDs: created,
            taskStatuses: taskStatuses
        )
    }

    /// Restores the schedule captured in `snapshot`.
    public func undo(_ snapshot: ScheduleSnapshot) {
        let segmentsByID = Dictionary(
            allSegments().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }
        )

        for id in snapshot.createdSegmentIDs {
            if let segment = segmentsByID[id] { context.delete(segment) }
        }

        for state in snapshot.existing {
            if let segment = segmentsByID[state.id] {
                segment.startDate = state.start
                segment.endDate = state.end
                segment.stateRaw = state.stateRaw
                segment.sourceRaw = state.sourceRaw
                segment.sequenceIndex = state.sequenceIndex
                segment.touch()
            } else {
                // The segment was deleted by the change being undone; recreate it.
                // Its task is found through the recorded status map below.
                continue
            }
        }

        for task in allTasks() {
            if let raw = snapshot.taskStatuses[task.id] { task.statusRaw = raw }
        }

        try? context.save()
    }

    // MARK: - Missed work

    /// Marks passed-but-unfinished segments missed and gives their tasks a new slot.
    ///
    /// Idempotent: a missed segment is only ever continued once, keyed by
    /// `continuationOfSegmentID`, so running this twice creates no duplicates.
    @discardableResult
    public func reconcileMissedWork(now: Date = Date()) -> [RequeueOutcome] {
        var outcomes: [RequeueOutcome] = []

        let expired = allSegments()
            .filter { $0.state == .scheduled && $0.endDate <= now }
            .sorted { $0.startDate < $1.startDate }
        guard !expired.isEmpty else { return [] }

        // Continuations that already exist, so we never create a second one.
        var alreadyContinued = Set(
            allSegments().compactMap(\.continuationOfSegmentID)
        )

        var busyByDay = busyMap(from: now, dayCount: Self.lookaheadDays)

        for segment in expired {
            guard let task = segment.task else {
                segment.state = .elapsed
                continue
            }

            if task.status == .completed || task.status == .cancelled {
                segment.state = task.status == .completed ? .completed : .cancelled
                continue
            }

            segment.state = .missed

            guard !alreadyContinued.contains(segment.id) else { continue }

            let minutes = max(SchedulingEngine.snapMinutes, segment.durationMinutes)
            let searchStart = settings.requeuePrefersLaterToday
                ? now
                : (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now)

            let result = place(
                task: task,
                outstandingMinutes: minutes,
                day: searchStart,
                busyByDay: &busyByDay,
                notBefore: settings.requeuePrefersLaterToday ? now : nil,
                source: .carryover,
                startingSequenceIndex: task.liveSegments.count
            )

            if let first = result.blocks.first {
                for block in result.blocks {
                    let continuation = TaskSegment(
                        task: task,
                        startDate: block.start,
                        endDate: block.end,
                        state: .scheduled,
                        isLocked: false,
                        sequenceIndex: block.sequenceIndex,
                        source: .carryover,
                        continuationOfSegmentID: segment.id
                    )
                    context.insert(continuation)
                }
                alreadyContinued.insert(segment.id)

                task.carryoverCount += 1
                task.lastCarriedAt = now
                if task.status == .inbox { task.status = .planned }

                outcomes.append(
                    RequeueOutcome(
                        taskID: task.id,
                        taskTitle: task.title,
                        minutes: result.blocks.reduce(0) { $0 + $1.minutes },
                        newStart: first.start,
                        movedToAnotherDay: !calendar.isDate(first.start, inSameDayAs: now),
                        failureReason: nil
                    )
                )
            } else {
                // Nowhere to put it: the task returns to the Inbox rather than
                // silently disappearing.
                task.status = .inbox
                task.carryoverCount += 1
                task.lastCarriedAt = now
                outcomes.append(
                    RequeueOutcome(
                        taskID: task.id,
                        taskTitle: task.title,
                        minutes: minutes,
                        newStart: nil,
                        movedToAnotherDay: false,
                        failureReason: engine.unplaceableReason(
                            for: task, remainingMinutes: result.remainingMinutes
                        )
                    )
                )
            }
        }

        try? context.save()
        return outcomes
    }

    /// Gives an unfinished focus task another block, used when the timer runs out.
    ///
    /// Returns `nil` when the work could not be placed anywhere.
    @discardableResult
    public func scheduleContinuation(
        for task: FlowTask,
        after segment: TaskSegment?,
        minutes: Int,
        now: Date = Date()
    ) -> RequeueOutcome? {
        // Never continue the same segment twice, even across devices.
        if let segment {
            let existing = allSegments().contains { $0.continuationOfSegmentID == segment.id }
            if existing { return nil }
        }

        var busyByDay = busyMap(from: now, dayCount: Self.lookaheadDays)
        let result = place(
            task: task,
            outstandingMinutes: max(SchedulingEngine.snapMinutes, minutes),
            day: now,
            busyByDay: &busyByDay,
            notBefore: now,
            source: .focusContinuation,
            startingSequenceIndex: task.liveSegments.count
        )

        guard let first = result.blocks.first else {
            task.status = .inbox
            try? context.save()
            return RequeueOutcome(
                taskID: task.id,
                taskTitle: task.title,
                minutes: minutes,
                newStart: nil,
                movedToAnotherDay: false,
                failureReason: engine.unplaceableReason(
                    for: task, remainingMinutes: result.remainingMinutes
                )
            )
        }

        for block in result.blocks {
            let continuation = TaskSegment(
                task: task,
                startDate: block.start,
                endDate: block.end,
                state: .scheduled,
                isLocked: false,
                sequenceIndex: block.sequenceIndex,
                source: .focusContinuation,
                continuationOfSegmentID: segment?.id
            )
            context.insert(continuation)
        }

        task.carryoverCount += 1
        task.lastCarriedAt = now
        if task.status == .inbox { task.status = .planned }
        try? context.save()

        return RequeueOutcome(
            taskID: task.id,
            taskTitle: task.title,
            minutes: result.blocks.reduce(0) { $0 + $1.minutes },
            newStart: first.start,
            movedToAnotherDay: !calendar.isDate(first.start, inSameDayAs: now),
            failureReason: nil
        )
    }

    // MARK: - Manual placement

    /// Whether a block may sit at `start` for `minutes`, ignoring itself.
    public func canPlace(
        minutes: Int,
        at start: Date,
        ignoring segmentID: UUID? = nil
    ) -> Bool {
        let end = start.addingTimeInterval(Double(minutes) * 60)
        let dayKey = calendar.startOfDay(for: start)
        // Start a day early and take two days: a block running through midnight
        // is bucketed under the day it started, and the candidate itself may end
        // after midnight. Overlap is then judged on real dates, not day keys.
        let searchStart = calendar.date(byAdding: .day, value: -1, to: dayKey) ?? dayKey
        let busy = busyMap(from: searchStart, dayCount: 3).values.flatMap { $0 }
        return !busy.contains { interval in
            if let segmentID, interval.segmentID == segmentID { return false }
            return interval.overlaps(start: start, end: end)
        }
    }

    /// Drops a task onto the timeline at `start`. Returns the new segment, or
    /// `nil` when the slot is taken.
    @discardableResult
    public func schedule(
        task: FlowTask,
        at start: Date,
        minutes: Int? = nil
    ) -> TaskSegment? {
        let snapped = engine.snapNearest(start)
        let length = minutes ?? max(SchedulingEngine.snapMinutes, task.unscheduledMinutes)
        guard canPlace(minutes: length, at: snapped) else { return nil }

        let segment = TaskSegment(
            task: task,
            startDate: snapped,
            endDate: snapped.addingTimeInterval(Double(length) * 60),
            state: .scheduled,
            sequenceIndex: task.liveSegments.count,
            source: .manual
        )
        context.insert(segment)
        if task.status == .inbox { task.status = .planned }
        try? context.save()
        return segment
    }

    /// Places one task in the earliest free slot that fits it today, or the
    /// first following day that has room.
    ///
    /// Deliberately narrower than `proposePlan`: the Plan page's "Plan now"
    /// answers for a single task the user is looking at, so it needs no
    /// preview — nothing else on the day moves.
    @discardableResult
    public func planNow(
        task: FlowTask,
        now: Date = Date(),
        lookaheadDays: Int = SchedulingService.lookaheadDays
    ) -> TaskSegment? {
        let minutes = max(SchedulingEngine.snapMinutes, task.unscheduledMinutes)
        let firstDay = calendar.startOfDay(for: now)
        // Starts a day early and takes one more: busy intervals are bucketed by
        // the day a block STARTS, so the search below reads each day plus the
        // one before it, and the very first of those would otherwise be missing.
        // Not a correctness fix — `schedule` re-checks through `canPlace`, which
        // has its own ±1-day window and refuses — but without this the search
        // offers a slot that is then rejected and silently skipped.
        let searchStart = calendar.date(byAdding: .day, value: -1, to: firstDay) ?? firstDay
        let map = busyMap(from: searchStart, dayCount: lookaheadDays + 1)

        for offset in 0..<lookaheadDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { continue }
            // Adjacent days too: a block starting yesterday can still be
            // running into this one, and busyMap buckets it under its start.
            let previous = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            let busy = (map[day] ?? []) + (map[previous] ?? [])
            let slots = engine.freeSlots(on: day, busy: busy, notBefore: offset == 0 ? now : nil)
            for slot in slots {
                guard let usable = engine.constrain(slot: slot, for: task, on: day),
                      usable.minutes >= minutes
                else { continue }
                if let segment = schedule(task: task, at: usable.start, minutes: minutes) {
                    return segment
                }
            }
        }
        return nil
    }

    /// Minutes still free between `now` and the end of the working day — what
    /// the Plan page's capacity line reports.
    public func freeMinutesRemainingToday(now: Date = Date()) -> Int {
        let day = calendar.startOfDay(for: now)
        let previous = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let map = busyMap(from: previous, dayCount: 2)
        let busy = (map[day] ?? []) + (map[previous] ?? [])
        return engine.freeSlots(on: day, busy: busy, notBefore: now).reduce(0) { $0 + $1.minutes }
    }

    /// Moves an existing block. Refuses if the destination overlaps or the block is locked.
    @discardableResult
    public func move(segment: TaskSegment, to start: Date) -> Bool {
        guard !segment.isLocked else { return false }
        let snapped = engine.snapNearest(start)
        guard canPlace(minutes: segment.durationMinutes, at: snapped, ignoring: segment.id) else {
            return false
        }
        segment.move(to: snapped)
        try? context.save()
        return true
    }

    /// Changes a block's length in place.
    @discardableResult
    public func resize(segment: TaskSegment, toMinutes minutes: Int) -> Bool {
        guard !segment.isLocked else { return false }
        let clamped = max(SchedulingEngine.snapMinutes, minutes)
        guard canPlace(minutes: clamped, at: segment.startDate, ignoring: segment.id) else {
            return false
        }
        segment.endDate = segment.startDate.addingTimeInterval(Double(clamped) * 60)
        segment.touch()
        try? context.save()
        return true
    }

    public func unschedule(segment: TaskSegment) {
        let task = segment.task
        context.delete(segment)
        if let task, task.liveSegments.isEmpty, task.status == .planned {
            task.status = .inbox
        }
        try? context.save()
    }
}

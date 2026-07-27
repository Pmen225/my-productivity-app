import Foundation
import SwiftData

// MARK: - Value types

/// A block of time that is already spoken for.
public struct BusyInterval: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// An external calendar event. Never moved.
        case externalEvent
        /// A Flowmap segment the user locked. Never moved automatically.
        case lockedSegment
        /// A Flowmap segment that may be replanned.
        case movableSegment
    }

    public let start: Date
    public let end: Date
    public let kind: Kind
    /// Segment identity, when this interval came from a Flowmap segment.
    public let segmentID: UUID?

    public init(start: Date, end: Date, kind: Kind, segmentID: UUID? = nil) {
        self.start = start
        self.end = end
        self.kind = kind
        self.segmentID = segmentID
    }

    public func overlaps(start otherStart: Date, end otherEnd: Date) -> Bool {
        start < otherEnd && otherStart < end
    }
}

/// An uninterrupted stretch of free time inside the working day.
public struct FreeSlot: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
}

/// One block the planner wants to place.
public struct PlannedBlock: Equatable, Sendable {
    public let taskID: UUID
    public let start: Date
    public let end: Date
    /// Set when this moves an existing segment rather than creating one.
    public let existingSegmentID: UUID?
    public let source: SegmentSource
    public let sequenceIndex: Int

    public var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
}

/// The planner's answer, previewable before anything is written.
public struct PlanProposal: Sendable {
    public var blocks: [PlannedBlock] = []
    /// Tasks that had no room today and were placed on a later day.
    public var deferredTaskIDs: Set<UUID> = []
    /// Tasks that could not be placed at all, with the reason to show the user.
    public var unplaceable: [UUID: String] = [:]
    /// Segment ids that already sat in the right place — highlighted as unchanged.
    public var unchangedSegmentIDs: Set<UUID> = []

    public var isEmpty: Bool { blocks.isEmpty && unplaceable.isEmpty }

    public var changedBlockCount: Int {
        blocks.count { block in
            guard let id = block.existingSegmentID else { return true }
            return !unchangedSegmentIDs.contains(id)
        }
    }
}

/// Enough state to put the schedule back exactly as it was.
public struct ScheduleSnapshot: Sendable {
    public struct SegmentState: Sendable {
        public let id: UUID
        public let start: Date
        public let end: Date
        public let stateRaw: String
        public let sourceRaw: String
        public let sequenceIndex: Int
    }

    public let existing: [SegmentState]
    /// Segments that did not exist before the change and must be deleted on undo.
    public let createdSegmentIDs: Set<UUID>
    public let taskStatuses: [UUID: String]
}

// MARK: - Engine

/// Deterministic planner.
///
/// Everything takes an explicit `now` and `Calendar` so behaviour is reproducible
/// in tests and correct across time-zone and daylight-saving changes.
@MainActor
public struct SchedulingEngine {
    public static let snapMinutes = 5

    private let calendar: Calendar
    private let settings: AppSettings

    public init(settings: AppSettings, calendar: Calendar = .current) {
        self.settings = settings
        self.calendar = calendar
    }

    // MARK: Slot maths

    /// Rounds up to the next 5-minute boundary.
    public func snapUp(_ date: Date) -> Date {
        let interval = Double(Self.snapMinutes * 60)
        let seconds = date.timeIntervalSinceReferenceDate
        let snapped = (seconds / interval).rounded(.up) * interval
        return Date(timeIntervalSinceReferenceDate: snapped)
    }

    /// Rounds to the nearest 5-minute boundary — used when dragging a block.
    public func snapNearest(_ date: Date) -> Date {
        let interval = Double(Self.snapMinutes * 60)
        let seconds = date.timeIntervalSinceReferenceDate
        let snapped = (seconds / interval).rounded() * interval
        return Date(timeIntervalSinceReferenceDate: snapped)
    }

    /// Free stretches inside the working day, in chronological order.
    ///
    /// - Parameter notBefore: nothing is offered earlier than this, so replanning
    ///   today never proposes a slot in the past.
    public func freeSlots(
        on day: Date,
        busy: [BusyInterval],
        notBefore: Date? = nil
    ) -> [FreeSlot] {
        let dayStart = settings.workdayStart(on: day, calendar: calendar)
        let dayEnd = settings.workdayEnd(on: day, calendar: calendar)

        var cursor = dayStart
        if let notBefore, notBefore > cursor { cursor = snapUp(notBefore) }
        guard cursor < dayEnd else { return [] }

        // Only intervals that actually intersect this day's window matter.
        let relevant = busy
            .filter { $0.end > cursor && $0.start < dayEnd }
            .sorted { $0.start < $1.start }

        var slots: [FreeSlot] = []
        for interval in relevant {
            if interval.start > cursor {
                slots.append(FreeSlot(start: cursor, end: min(interval.start, dayEnd)))
            }
            cursor = max(cursor, interval.end)
            if cursor >= dayEnd { break }
        }
        if cursor < dayEnd {
            slots.append(FreeSlot(start: cursor, end: dayEnd))
        }
        return slots.filter { $0.minutes > 0 }
    }

    /// Narrows a slot to the task's own constraints: preferred period, earliest
    /// start and latest finish. Returns `nil` when nothing usable is left.
    public func constrain(slot: FreeSlot, for task: FlowTask, on day: Date) -> FreeSlot? {
        var start = slot.start
        var end = slot.end

        if let earliest = task.earliestStart, earliest > start { start = snapUp(earliest) }
        if let latest = task.latestFinish, latest < end { end = latest }

        if let hours = task.preferredPeriod.hourRange {
            let periodStart = calendar.date(
                bySettingHour: hours.lowerBound, minute: 0, second: 0, of: day
            ) ?? start
            let periodEnd = hours.upperBound >= 24
                ? calendar.startOfDay(for: day).addingTimeInterval(24 * 3600)
                : (calendar.date(bySettingHour: hours.upperBound, minute: 0, second: 0, of: day) ?? end)
            start = max(start, periodStart)
            end = min(end, periodEnd)
        }

        guard end > start else { return nil }
        return FreeSlot(start: start, end: end)
    }

    // MARK: Candidate ordering

    /// Tasks the planner should try to place today, most urgent first.
    ///
    /// Order: overdue, then due today, then flagged for today, then everything
    /// else — each group sorted by priority and then the user's manual order.
    public func candidates(from tasks: [FlowTask], on day: Date, now: Date) -> [FlowTask] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        func rank(_ task: FlowTask) -> Int {
            if let due = task.dueDate, due < dayStart { return 0 }        // overdue
            if let due = task.dueDate, due < dayEnd { return 1 }          // due today
            if task.isFlaggedForToday { return 2 }
            if task.carryoverCount > 0 { return 3 }                       // already carried
            return 4
        }

        return tasks
            .filter { $0.status.isOpen && $0.unscheduledMinutes > 0 }
            .sorted { lhs, rhs in
                let lhsRank = rank(lhs), rhsRank = rank(rhs)
                if lhsRank != rhsRank { return lhsRank < rhsRank }

                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?) where l != r: return l < r
                case (nil, _?): return false
                case (_?, nil): return true
                default: break
                }

                if lhs.priority.weight != rhs.priority.weight {
                    return lhs.priority.weight > rhs.priority.weight
                }
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
    }

    // MARK: Placement

    /// Places one task's outstanding minutes, searching `day` and then up to
    /// `lookaheadDays` following days.
    ///
    /// Returns the blocks it wants plus how many minutes it could not place.
    public func placeTask(
        _ task: FlowTask,
        startingOn day: Date,
        busyByDay: inout [Date: [BusyInterval]],
        notBefore: Date?,
        lookaheadDays: Int,
        source: SegmentSource,
        startingSequenceIndex: Int
    ) -> (blocks: [PlannedBlock], remainingMinutes: Int, usedFutureDay: Bool) {
        var remaining = task.unscheduledMinutes
        guard remaining > 0 else { return ([], 0, false) }

        var blocks: [PlannedBlock] = []
        var sequence = startingSequenceIndex
        var usedFutureDay = false
        let minimumChunk = task.isSplittable
            ? max(Self.snapMinutes, task.minimumChunkMinutes)
            : remaining

        for offset in 0...max(0, lookaheadDays) {
            guard remaining > 0 else { break }
            guard let currentDay = calendar.date(byAdding: .day, value: offset, to: day) else { break }
            let dayKey = calendar.startOfDay(for: currentDay)
            // Busy intervals are bucketed by the day they *start*, so a block
            // running through midnight lives in the previous day's bucket. Both
            // are pulled in; `freeSlots` then clips by real overlap.
            let previousKey = calendar.date(byAdding: .day, value: -1, to: dayKey) ?? dayKey
            let busy = (busyByDay[dayKey] ?? []) + (busyByDay[previousKey] ?? [])
            let floor = offset == 0 ? notBefore : nil

            for slot in freeSlots(on: currentDay, busy: busy, notBefore: floor) {
                guard remaining > 0 else { break }
                guard let usable = constrain(slot: slot, for: task, on: currentDay) else { continue }
                guard usable.minutes >= minimumChunk else { continue }

                let take = min(remaining, usable.minutes)
                // An unsplittable task takes all its minutes or none.
                guard task.isSplittable || take == remaining else { continue }
                // A split must not leave a stub smaller than the minimum chunk.
                let leftover = remaining - take
                if task.isSplittable, leftover > 0, leftover < minimumChunk { continue }

                let end = usable.start.addingTimeInterval(Double(take) * 60)
                blocks.append(
                    PlannedBlock(
                        taskID: task.id,
                        start: usable.start,
                        end: end,
                        existingSegmentID: nil,
                        source: offset == 0 ? source : (source == .manual ? .autoPlanned : source),
                        sequenceIndex: sequence
                    )
                )
                sequence += 1
                remaining -= take
                if offset > 0 { usedFutureDay = true }

                // Claim the time so later tasks in this same run cannot overlap it.
                busyByDay[dayKey, default: []].append(
                    BusyInterval(start: usable.start, end: end, kind: .movableSegment)
                )
            }
        }

        return (blocks, remaining, usedFutureDay)
    }

    // MARK: Reasons

    /// Why a task could not be placed, in the user's words.
    public func unplaceableReason(for task: FlowTask, remainingMinutes: Int) -> String {
        if !task.isSplittable, task.estimatedMinutes > minutesInWorkday {
            return "\(task.title) is longer than your whole working day. Shorten it or allow it to be split."
        }
        if task.latestFinish != nil || task.earliestStart != nil {
            return "\(task.title) has no free time inside its start and finish window."
        }
        if task.preferredPeriod != .anytime {
            return "\(task.title) has no free \(task.preferredPeriod.displayName.lowercased()) time in the days ahead."
        }
        return "\(task.title) still needs \(DurationFormatter.compact(minutes: remainingMinutes)) and there is no free time in the days ahead."
    }

    public var minutesInWorkday: Int {
        let reference = Date()
        let start = settings.workdayStart(on: reference, calendar: calendar)
        let end = settings.workdayEnd(on: reference, calendar: calendar)
        return max(0, Int(end.timeIntervalSince(start) / 60))
    }
}

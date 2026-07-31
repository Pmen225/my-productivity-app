import Foundation

/// The three ways Progress can be sliced. Each resolves to a concrete date
/// range only when asked, since "today" and "this week" depend on the moment
/// of the request and on the user's first-day-of-week preference.
public enum ProgressPeriod: String, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case month

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .today: "Today"
        case .week: "Week"
        case .month: "Month"
        }
    }

    /// The half-open range `[start, end)` this period covers, anchored at
    /// `date`. Half-open so a segment ending exactly at midnight never counts
    /// twice, matching the convention `TaskSegment.contains(_:)` already uses.
    public func range(containing date: Date, calendar: Calendar) -> Range<Date> {
        switch self {
        case .today:
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            return start..<end
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: date)
                ?? DateInterval(start: date, duration: 0)
            return interval.start..<interval.end
        case .month:
            let interval = calendar.dateInterval(of: .month, for: date)
                ?? DateInterval(start: date, duration: 0)
            return interval.start..<interval.end
        }
    }
}

/// The four primary numbers Progress shows — never a fifth. Every value here
/// is derived, not stored: recomputing this struct is always cheap enough to
/// do on demand from the arrays SwiftData already holds.
public struct ProgressSummary: Equatable, Sendable {
    public var completedTaskCount: Int
    public var plannedMinutes: Int
    public var actualMinutes: Int
    public var carryoverCount: Int
    /// `0...1`, or `nil` when nothing in range was schedulable to complete —
    /// so the UI can say "Nothing planned" instead of a misleading 0%.
    public var completionRate: Double?

    public init(
        completedTaskCount: Int = 0,
        plannedMinutes: Int = 0,
        actualMinutes: Int = 0,
        carryoverCount: Int = 0,
        completionRate: Double? = nil
    ) {
        self.completedTaskCount = completedTaskCount
        self.plannedMinutes = plannedMinutes
        self.actualMinutes = actualMinutes
        self.carryoverCount = carryoverCount
        self.completionRate = completionRate
    }
}

/// Pure maths over persisted `FlowTask` / `TaskSegment` / `FocusSession`
/// arrays. Nothing here touches SwiftData, a `ModelContext` or the UI, so
/// every function is unit-testable with plain model instances.
public enum ProgressMetrics {
    /// The four headline numbers for `range`.
    public static func summary(
        tasks: [FlowTask],
        segments: [TaskSegment],
        sessions: [FocusSession],
        range: Range<Date>
    ) -> ProgressSummary {
        let completed = tasks.filter { task in
            task.status == .completed && task.completedAt.map(range.contains) == true
        }

        let plannedMinutes = segments
            .filter { range.contains($0.startDate) }
            .reduce(0) { $0 + $1.durationMinutes }

        let actualMinutes = sessions
            .filter { range.contains($0.startedAt) }
            .reduce(0) { $0 + $1.actualMinutes }

        let carryoverCount = tasks.filter { task in
            task.carryoverCount > 0 && task.lastCarriedAt.map(range.contains) == true
        }.count

        // "Relevant" work for the completion rate: anything not cancelled that
        // touched this range, either by finishing in it or by holding a
        // scheduled slot in it. Cancelled work never distorts the ratio.
        let relevant = tasks.filter { task in
            guard task.status != .cancelled else { return false }
            if let completedAt = task.completedAt, range.contains(completedAt) { return true }
            return task.liveSegments.contains { range.contains($0.startDate) }
        }
        let completionRate: Double? = relevant.isEmpty
            ? nil
            : Double(completed.count) / Double(relevant.count)

        return ProgressSummary(
            completedTaskCount: completed.count,
            plannedMinutes: plannedMinutes,
            actualMinutes: actualMinutes,
            carryoverCount: carryoverCount,
            completionRate: completionRate
        )
    }

    /// The initiative card counts only tracked work: a task under a project
    /// with `isTrackedInStats == false` is excluded from both `completed` and
    /// `total`. A task with no project at all is never untracked, so it is
    /// always counted.
    public static func initiativeTaskCounts(tasks: [FlowTask]) -> (completed: Int, total: Int) {
        let tracked = tasks.filter { $0.project?.isTrackedInStats ?? true }
        return (tracked.count { $0.status == .completed }, tracked.count)
    }
}

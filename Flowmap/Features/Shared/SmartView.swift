import Foundation
import SwiftData

/// The built-in task views.
///
/// These are queries over the one task store, not extra containers — a task is
/// never copied into Today or Upcoming, it simply matches them.
public enum SmartView: String, CaseIterable, Identifiable, Sendable {
    case inbox
    case today
    case upcoming
    case anytime
    case allTasks
    case completed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .inbox: "Inbox"
        case .today: "Today"
        case .upcoming: "Upcoming"
        case .anytime: "Anytime"
        case .allTasks: "All Tasks"
        case .completed: "Completed"
        }
    }

    public var symbolName: String {
        switch self {
        case .inbox: "tray"
        case .today: "sun.max"
        case .upcoming: "calendar"
        case .anytime: "square.stack"
        case .allTasks: "list.bullet"
        case .completed: "checkmark.circle"
        }
    }

    public var colour: ColourToken {
        switch self {
        case .inbox: .violet
        case .today: .peach
        case .upcoming: .blue
        case .anytime: .teal
        case .allTasks: .green
        case .completed: .yellow
        }
    }

    public var emptyMessage: String {
        switch self {
        case .inbox: "Anything you capture without a home lands here."
        case .today: "Nothing is scheduled yet. Plan your day to fill it in."
        case .upcoming: "Nothing is dated beyond today."
        case .anytime: "No undated work waiting."
        case .allTasks: "No tasks yet."
        case .completed: "Nothing completed yet."
        }
    }

    /// Filters `tasks` down to this view.
    ///
    /// Kept in Swift rather than `#Predicate` because several of these depend on
    /// segment relationships, which predicates cannot reach.
    public func matches(_ tasks: [FlowTask], now: Date = Date(), calendar: Calendar = .current) -> [FlowTask] {
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        switch self {
        case .inbox:
            return tasks.filter { !$0.isScheduled && ($0.status == .inbox || ($0.status.isOpen && $0.dueDate == nil)) }

        case .today:
            return tasks.filter { task in
                guard task.status.isOpen else { return false }
                if task.isFlaggedForToday { return true }
                if let due = task.dueDate, due < dayEnd { return true }
                return task.liveSegments.contains { $0.startDate < dayEnd && $0.endDate > dayStart }
            }

        case .upcoming:
            return tasks.filter { task in
                guard task.status.isOpen else { return false }
                if let due = task.dueDate, due >= dayEnd { return true }
                return task.liveSegments.contains { $0.startDate >= dayEnd }
            }

        case .anytime:
            return tasks.filter { $0.status.isOpen && $0.dueDate == nil && $0.isScheduled }

        case .allTasks:
            return tasks.filter { $0.status != .cancelled }

        case .completed:
            return tasks.filter { $0.status == .completed }
        }
    }

    /// Sorts a view's tasks according to a list's grouping mode.
    public func sorted(_ tasks: [FlowTask], grouping: GroupingMode) -> [FlowTask] {
        switch grouping {
        case .manual:
            return tasks.sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
        case .priority:
            return tasks.sorted { lhs, rhs in
                if lhs.priority.weight != rhs.priority.weight {
                    return lhs.priority.weight > rhs.priority.weight
                }
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
        }
    }

    /// Groups tasks into titled sections for the given mode.
    public func sections(_ tasks: [FlowTask], grouping: GroupingMode) -> [(title: String, tasks: [FlowTask])] {
        switch grouping {
        case .manual:
            return [("", sorted(tasks, grouping: .manual))]
        case .priority:
            return TaskPriority.allCases
                .sorted { $0.weight > $1.weight }
                .compactMap { priority in
                    let matching = tasks.filter { $0.priority == priority }
                    guard !matching.isEmpty else { return nil }
                    return (priority.displayName, sorted(matching, grouping: .manual))
                }
        }
    }
}

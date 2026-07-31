import Foundation
import SwiftData

/// The central unit of work.
///
/// A task has one identity for its whole life. When it is moved, missed or
/// continued, its `TaskSegment`s change — the task itself is never duplicated.
@Model
public final class FlowTask {
    public var id: UUID = UUID()
    public var title: String = ""
    public var details: String = ""
    public var statusRaw: String = TaskStatus.inbox.rawValue
    public var priorityRaw: String = TaskPriority.none.rawValue
    public var estimatedMinutes: Int = 30
    public var actualMinutes: Int = 0
    public var dueDate: Date?
    public var earliestStart: Date?
    public var latestFinish: Date?
    public var preferredPeriodRaw: String = DayPeriod.anytime.rawValue
    public var isLockedInSchedule: Bool = false
    public var isSplittable: Bool = false
    public var minimumChunkMinutes: Int = 15
    public var sortOrder: Int = 0
    public var colourToken: String = ColourToken.violet.rawValue
    public var iconName: String = "circle"
    public var recurrenceFrequencyRaw: String = RecurrenceFrequency.none.rawValue
    /// Set when the user explicitly wants this task planned today regardless of due date.
    public var isFlaggedForToday: Bool = false
    public var completedAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    // Carryover metadata — surfaced as neutral copy, never as a scolding.
    public var carryoverCount: Int = 0
    public var lastCarriedAt: Date?

    // MARK: - Compulsory planning phase

    /// Free text written before this task's clock can first start — the
    /// Definition of Done. Empty until planned.
    public var definitionOfDone: String = ""
    /// Set the moment a Definition of Done is recorded. `FocusEngine` reads
    /// this to decide between the full planning gate and a lighter clock-in.
    public var hasBeenPlanned: Bool = false

    // MARK: - Relationships

    public var workspace: Workspace?
    public var list: TaskList?
    public var project: Project?

    @Relationship(deleteRule: .nullify, inverse: \MapNode.linkedTask)
    public var mapNode: MapNode?

    @Relationship(deleteRule: .nullify, inverse: \Note.task)
    public var notes: [Note]?

    @Relationship(deleteRule: .cascade, inverse: \Subtask.task)
    public var subtasks: [Subtask]?

    @Relationship(deleteRule: .cascade, inverse: \TaskSegment.task)
    public var segments: [TaskSegment]?

    @Relationship(deleteRule: .cascade, inverse: \FocusSession.task)
    public var focusSessions: [FocusSession]?

    // MARK: - Computed enum accessors

    public var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .inbox }
        set { statusRaw = newValue.rawValue; touch() }
    }

    public var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue; touch() }
    }

    public var preferredPeriod: DayPeriod {
        get { DayPeriod(rawValue: preferredPeriodRaw) ?? .anytime }
        set { preferredPeriodRaw = newValue.rawValue; touch() }
    }

    public var recurrence: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: recurrenceFrequencyRaw) ?? .none }
        set { recurrenceFrequencyRaw = newValue.rawValue; touch() }
    }

    public var colour: ColourToken { ColourToken.token(colourToken) }

    public init(
        title: String,
        details: String = "",
        status: TaskStatus = .inbox,
        priority: TaskPriority = .none,
        estimatedMinutes: Int = 30,
        dueDate: Date? = nil,
        colourToken: String = ColourToken.violet.rawValue,
        iconName: String = "circle",
        sortOrder: Int = 0,
        list: TaskList? = nil,
        project: Project? = nil,
        workspace: Workspace? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.details = details
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.estimatedMinutes = max(5, estimatedMinutes)
        self.dueDate = dueDate
        self.colourToken = colourToken
        self.iconName = iconName
        self.sortOrder = sortOrder
        self.list = list
        self.project = project
        self.workspace = workspace ?? project?.workspace ?? list?.workspace
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func touch(_ date: Date = Date()) { updatedAt = date }

    // MARK: - Derived

    /// `30M`, `1H`, `1H 30M`. Duration is always visible in this compact form.
    public var durationLabel: String { DurationFormatter.compact(minutes: estimatedMinutes) }

    /// Long-form label for VoiceOver, where `30M` would be read as letters.
    public var durationAccessibilityLabel: String {
        DurationFormatter.spoken(minutes: estimatedMinutes)
    }

    public var orderedSubtasks: [Subtask] {
        (subtasks ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    public var completedSubtaskCount: Int {
        (subtasks ?? []).count { $0.isCompleted }
    }

    /// `2 of 4`, shown on the focus card.
    public var subtaskProgressLabel: String? {
        let all = subtasks ?? []
        guard !all.isEmpty else { return nil }
        return "\(all.count { $0.isCompleted }) of \(all.count)"
    }

    /// Segments that still hold time on the timeline, earliest first.
    public var liveSegments: [TaskSegment] {
        (segments ?? [])
            .filter { $0.state.occupiesTimeline }
            .sorted { $0.startDate < $1.startDate }
    }

    public var allSegmentsOrdered: [TaskSegment] {
        (segments ?? []).sorted { $0.startDate < $1.startDate }
    }

    /// Minutes already covered by segments that have run or are running.
    public var scheduledMinutes: Int {
        liveSegments.reduce(0) { $0 + $1.durationMinutes }
    }

    /// Work still needing a slot. Drives splitting and continuation.
    public var unscheduledMinutes: Int {
        max(0, estimatedMinutes - scheduledMinutes)
    }

    public var isScheduled: Bool { !liveSegments.isEmpty }

    /// The segment covering `date`, if any.
    public func segment(at date: Date) -> TaskSegment? {
        liveSegments.first { $0.contains(date) }
    }

    /// The next segment starting at or after `date`.
    public func nextSegment(after date: Date) -> TaskSegment? {
        liveSegments.first { $0.startDate >= date }
    }

    public var isOverdue: Bool {
        guard let dueDate, status.isOpen else { return false }
        return dueDate < Date()
    }

    // MARK: - Mutation

    public func markCompleted(at date: Date = Date()) {
        status = .completed
        completedAt = date
        // Close any segment still holding time so the slot is released.
        for segment in (segments ?? []) where segment.state == .scheduled || segment.state == .elapsed {
            segment.state = .completed
        }
        touch(date)
        if recurrence != .none {
            reopenForNextOccurrence(after: date)
            // `status = .planned` above re-triggers its own `touch()` with the
            // real wall clock; re-pin to the passed `date` so this call stays
            // deterministic, same as the non-recurring path.
            touch(date)
        }
    }

    /// A recurring task never leaves — completing it reopens the SAME task for its
    /// next turn rather than spawning a copy (see the type header). `completedAt`
    /// is left as the last completion, and `hasBeenPlanned` is left true so the
    /// planning gate is not re-imposed every cycle.
    private func reopenForNextOccurrence(after date: Date) {
        let base = dueDate ?? date
        guard var next = recurrence.nextDate(after: base) else { return }
        // Catch up an overdue recurring task to its next FUTURE turn.
        while next <= date {
            guard let following = recurrence.nextDate(after: next) else { return }
            next = following
        }
        dueDate = next
        status = .planned
        for subtask in subtasks ?? [] {
            subtask.isCompleted = false
        }
    }

    public func markCancelled(at date: Date = Date()) {
        status = .cancelled
        for segment in (segments ?? []) where segment.state.occupiesTimeline {
            segment.state = .cancelled
        }
        touch(date)
    }

    public func reopen(at date: Date = Date()) {
        status = isScheduled ? .planned : .inbox
        completedAt = nil
        touch(date)
    }
}

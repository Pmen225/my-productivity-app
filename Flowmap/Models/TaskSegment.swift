import Foundation
import SwiftData

/// One scheduled block of time belonging to exactly one `FlowTask`.
///
/// Moving, missing or continuing a task creates or edits segments. It must never
/// create a second task.
@Model
public final class TaskSegment {
    public var id: UUID = UUID()
    public var startDate: Date = Date()
    public var endDate: Date = Date()
    public var stateRaw: String = SegmentState.scheduled.rawValue
    public var isLocked: Bool = false
    public var sequenceIndex: Int = 0
    public var sourceRaw: String = SegmentSource.manual.rawValue
    /// EventKit identifier when this block was written to an external calendar.
    public var externalEventIdentifier: String?
    /// The segment this one continues, so repeated replanning stays idempotent.
    public var continuationOfSegmentID: UUID?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var task: FlowTask?

    @Relationship(deleteRule: .nullify, inverse: \FocusSession.segment)
    public var focusSessions: [FocusSession]?

    public var state: SegmentState {
        get { SegmentState(rawValue: stateRaw) ?? .scheduled }
        set { stateRaw = newValue.rawValue; touch() }
    }

    public var source: SegmentSource {
        get { SegmentSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue; touch() }
    }

    public init(
        task: FlowTask?,
        startDate: Date,
        endDate: Date,
        state: SegmentState = .scheduled,
        isLocked: Bool = false,
        sequenceIndex: Int = 0,
        source: SegmentSource = .manual,
        continuationOfSegmentID: UUID? = nil
    ) {
        self.id = UUID()
        self.task = task
        self.startDate = startDate
        self.endDate = max(endDate, startDate)
        self.stateRaw = state.rawValue
        self.isLocked = isLocked
        self.sequenceIndex = sequenceIndex
        self.sourceRaw = source.rawValue
        self.continuationOfSegmentID = continuationOfSegmentID
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func touch(_ date: Date = Date()) { updatedAt = date }

    // MARK: - Derived

    public var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

    public var durationMinutes: Int { Int((duration / 60).rounded()) }

    public var durationLabel: String { DurationFormatter.compact(minutes: durationMinutes) }

    /// Half-open interval: a block ending at 10:00 does not clash with one starting at 10:00.
    public func contains(_ date: Date) -> Bool {
        date >= startDate && date < endDate
    }

    public func overlaps(start: Date, end: Date) -> Bool {
        startDate < end && start < endDate
    }

    public func overlaps(_ other: TaskSegment) -> Bool {
        overlaps(start: other.startDate, end: other.endDate)
    }

    /// Time left in this block at `date`, never negative.
    public func remainingSeconds(at date: Date) -> TimeInterval {
        max(0, endDate.timeIntervalSince(max(date, startDate)))
    }

    /// Neutral badge such as `Carried from earlier`.
    public var badgeText: String? { source.badgeText }

    public var isContinuation: Bool {
        source == .carryover || source == .focusContinuation
    }

    /// Moves the block while preserving its length.
    public func move(to newStart: Date) {
        let length = duration
        startDate = newStart
        endDate = newStart.addingTimeInterval(length)
        touch()
    }
}

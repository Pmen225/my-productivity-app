import Foundation
import SwiftData

/// A run of the focus timer.
///
/// Every value here is a timestamp or an accumulated total. Nothing counts down
/// in memory, so the session survives backgrounding, screen lock, process death,
/// device sleep, and being observed from a second device.
@Model
public final class FocusSession {
    public var id: UUID = UUID()
    public var plannedSeconds: Double = 1800
    public var startedAt: Date = Date()
    /// Set while paused, cleared on resume.
    public var pausedAt: Date?
    /// Total time spent paused across all pauses in this session.
    public var accumulatedPausedSeconds: Double = 0
    public var endedAt: Date?
    public var outcomeRaw: String = FocusOutcome.running.rawValue
    /// Frozen at completion; before that, read `actualSeconds(at:)`.
    public var actualSeconds: Double = 0
    /// Set exactly once when the elapsed transition has been handled, so two
    /// devices — or two app activations — cannot both requeue the same session.
    public var transitionProcessed: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var task: FlowTask?
    public var segment: TaskSegment?

    public var outcome: FocusOutcome {
        get { FocusOutcome(rawValue: outcomeRaw) ?? .running }
        set { outcomeRaw = newValue.rawValue; touch() }
    }

    public init(
        task: FlowTask?,
        segment: TaskSegment? = nil,
        plannedSeconds: Double,
        startedAt: Date = Date()
    ) {
        self.id = UUID()
        self.task = task
        self.segment = segment
        self.plannedSeconds = max(0, plannedSeconds)
        self.startedAt = startedAt
        self.outcomeRaw = FocusOutcome.running.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public func touch(_ date: Date = Date()) { updatedAt = date }

    // MARK: - Derived timing

    public var isPaused: Bool { pausedAt != nil }

    public var isRunning: Bool { outcome == .running && !isPaused }

    /// Seconds of *active* work at `date`: wall-clock elapsed minus all paused time.
    public func elapsedSeconds(at date: Date = Date()) -> Double {
        let reference = endedAt ?? date
        let wallClock = max(0, reference.timeIntervalSince(startedAt))
        var paused = accumulatedPausedSeconds
        if let pausedAt {
            // Currently paused: include the still-open pause.
            paused += max(0, reference.timeIntervalSince(pausedAt))
        }
        return max(0, wallClock - paused)
    }

    /// What the countdown shows. Freezes while paused because `elapsedSeconds`
    /// stops advancing.
    public func remainingSeconds(at date: Date = Date()) -> Double {
        max(0, plannedSeconds - elapsedSeconds(at: date))
    }

    /// 0...1, for the ring and progress readouts.
    public func progress(at date: Date = Date()) -> Double {
        guard plannedSeconds > 0 else { return 1 }
        return min(1, elapsedSeconds(at: date) / plannedSeconds)
    }

    /// True once the planned time is used up and the transition is still pending.
    public func hasElapsed(at date: Date = Date()) -> Bool {
        outcome == .running && remainingSeconds(at: date) <= 0
    }

    public func countdownLabel(at date: Date = Date()) -> String {
        DurationFormatter.countdown(seconds: remainingSeconds(at: date))
    }

    // MARK: - Transitions

    public func pause(at date: Date = Date()) {
        guard outcome == .running, pausedAt == nil else { return }
        pausedAt = date
        touch(date)
    }

    public func resume(at date: Date = Date()) {
        guard let pausedAt else { return }
        accumulatedPausedSeconds += max(0, date.timeIntervalSince(pausedAt))
        self.pausedAt = nil
        touch(date)
    }

    /// Closes the session. Idempotent: a second call on a finished session is ignored.
    public func finish(outcome newOutcome: FocusOutcome, at date: Date = Date()) {
        guard outcome == .running else { return }
        if let pausedAt {
            accumulatedPausedSeconds += max(0, date.timeIntervalSince(pausedAt))
            self.pausedAt = nil
        }
        actualSeconds = elapsedSeconds(at: date)
        endedAt = date
        outcome = newOutcome
        touch(date)
    }

    /// Marks the elapsed transition handled. Returns `false` if another device or
    /// activation already claimed it, so the caller knows not to requeue again.
    public func claimTransition() -> Bool {
        guard !transitionProcessed else { return false }
        transitionProcessed = true
        touch()
        return true
    }

    public var actualMinutes: Int { Int((actualSeconds / 60).rounded()) }
}

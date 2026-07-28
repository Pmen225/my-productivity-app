import Foundation

/// One point in a focus session worth telling the user about, expressed
/// without any wording — `FocusVoiceService` turns this into speech.
public enum FocusVoiceMilestone: Hashable, Sendable {
    /// Remaining time crossed the 75%, 50% or 25%-elapsed mark, rounded to
    /// the nearest 5 minutes.
    case timeLeft(minutes: Int)
    /// The final 5·4·3·2·1 minute countdown.
    case countdown(minutesLeft: Int)
    /// Entering the reflection window before the task's official end.
    case windDown(minutes: Int)
}

/// Decides which milestone, if any, is due for a focus session — from a
/// duration and an elapsed time alone.
///
/// This type does not import `AVFoundation` and does not know that time is
/// passing: it is handed two numbers and a set of what has already been said,
/// and returns what (if anything) is newly due. That is what makes the
/// schedule testable without a simulator; `FocusVoiceService` owns the
/// `AVSpeechSynthesizer` and the wall clock around it.
public enum FocusVoiceSchedule {
    /// The wind-down length for a task of this length, per the design's rule:
    /// 5 minutes for tasks 45 minutes or longer, 3 for 20 or longer, 1 otherwise.
    public static func windDownMinutes(forTaskMinutes minutes: Double) -> Int {
        if minutes >= 45 { return 5 }
        if minutes >= 20 { return 3 }
        return 1
    }

    /// The milestone to speak right now, or nil if nothing new is due.
    ///
    /// When a session is picked up already partway through — a relaunch, or a
    /// task started late — several milestones can be due at once. This
    /// returns only the most recently crossed one, so nothing stale gets read
    /// aloud; the caller is expected to mark every milestone in
    /// `dueMilestones` as announced (not just the one returned), so the
    /// skipped ones never surface later out of order.
    public static func nextAnnouncement(
        duration: TimeInterval,
        elapsed: TimeInterval,
        alreadyAnnounced: Set<FocusVoiceMilestone>
    ) -> FocusVoiceMilestone? {
        dueMilestones(duration: duration, elapsed: elapsed)
            .filter { !alreadyAnnounced.contains($0) }
            .last
    }

    /// Every milestone whose threshold has been reached, oldest first.
    public static func dueMilestones(duration: TimeInterval, elapsed: TimeInterval) -> [FocusVoiceMilestone] {
        points(duration: duration)
            .filter { $0.thresholdElapsed <= elapsed }
            .sorted {
                // The wind-down window always lands on the same threshold as a
                // countdown point — its length (5/3/1) is by definition one of
                // the countdown minutes. Since only the last due milestone is
                // spoken, an unordered tie would let the countdown swallow the
                // reflection prompt, which is the more useful of the two.
                if $0.thresholdElapsed == $1.thresholdElapsed {
                    return $0.priority < $1.priority
                }
                return $0.thresholdElapsed < $1.thresholdElapsed
            }
            .map(\.milestone)
    }

    // MARK: - Points

    /// A milestone paired with the elapsed time (from session start) at
    /// which it becomes due. Internal only — callers never see the threshold,
    /// just the milestone.
    private struct Point {
        let milestone: FocusVoiceMilestone
        let thresholdElapsed: TimeInterval

        /// Breaks a threshold tie: the higher the number, the later it sorts
        /// and so the more likely it is to be the one actually spoken. Only
        /// the wind-down prompt needs to win a tie — see `dueMilestones`.
        var priority: Int {
            switch milestone {
            case .windDown: 2
            case .countdown: 1
            case .timeLeft: 0
            }
        }
    }

    private static func points(duration: TimeInterval) -> [Point] {
        guard duration > 0 else { return [] }
        var points: [Point] = []

        for fraction in [0.75, 0.50, 0.25] {
            let thresholdElapsed = duration * fraction
            let minutesLeft = roundedToNearestFive((duration - thresholdElapsed) / 60)
            guard minutesLeft > 0 else { continue }
            points.append(Point(milestone: .timeLeft(minutes: minutesLeft), thresholdElapsed: thresholdElapsed))
        }

        for minutesLeft in [5, 4, 3, 2, 1] {
            let thresholdElapsed = duration - Double(minutesLeft) * 60
            guard thresholdElapsed >= 0 else { continue }
            points.append(Point(milestone: .countdown(minutesLeft: minutesLeft), thresholdElapsed: thresholdElapsed))
        }

        let windDown = windDownMinutes(forTaskMinutes: duration / 60)
        let windDownThreshold = duration - Double(windDown) * 60
        if windDownThreshold >= 0 {
            points.append(Point(milestone: .windDown(minutes: windDown), thresholdElapsed: windDownThreshold))
        }

        return points
    }

    private static func roundedToNearestFive(_ minutes: Double) -> Int {
        Int((minutes / 5).rounded()) * 5
    }
}

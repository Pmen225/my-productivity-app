import Foundation
import Testing
@testable import Flowmap

/// `FocusVoiceSchedule` is pure — no `AVFoundation`, no wall clock — so every
/// case here is just numbers in, milestone out.
@Suite("Focus voice schedule")
struct FocusVoiceScheduleTests {
    private let fortyMinutes: TimeInterval = 40 * 60

    @Test("The three percentage milestones fire once each, rounded to the nearest 5 minutes")
    func percentageMilestonesFireOnce() {
        var announced: Set<FocusVoiceMilestone> = []

        // 25% elapsed (600s) of a 40-minute task leaves 30 minutes.
        let first = FocusVoiceSchedule.nextAnnouncement(duration: fortyMinutes, elapsed: 600, alreadyAnnounced: announced)
        #expect(first == .timeLeft(minutes: 30))
        announced.insert(first!)
        // Calling again at the same elapsed must not repeat it.
        #expect(FocusVoiceSchedule.nextAnnouncement(duration: fortyMinutes, elapsed: 600, alreadyAnnounced: announced) == nil)

        // 50% elapsed (1200s) leaves 20 minutes.
        let second = FocusVoiceSchedule.nextAnnouncement(duration: fortyMinutes, elapsed: 1200, alreadyAnnounced: announced)
        #expect(second == .timeLeft(minutes: 20))
        announced.insert(second!)

        // 75% elapsed (1800s) leaves 10 minutes.
        let third = FocusVoiceSchedule.nextAnnouncement(duration: fortyMinutes, elapsed: 1800, alreadyAnnounced: announced)
        #expect(third == .timeLeft(minutes: 10))
        announced.insert(third!)

        // All three said — nothing left to say at this point in time.
        #expect(FocusVoiceSchedule.nextAnnouncement(duration: fortyMinutes, elapsed: 1800, alreadyAnnounced: announced) == nil)
    }

    @Test("The final 5·4·3·2·1 countdown fires in order")
    func countdownFires() {
        var announced: Set<FocusVoiceMilestone> = []

        // 3 minutes left coincides with wind-down for this task length (see
        // the dedicated coincidence test below), so wind-down — not the
        // countdown step — is what gets spoken there. The real caller marks
        // every due milestone as announced when it speaks one, so this loop
        // does the same rather than inserting only the value returned.
        let steps: [(TimeInterval, FocusVoiceMilestone)] = [
            (2100, .countdown(minutesLeft: 5)),
            (2160, .countdown(minutesLeft: 4)),
            (2220, .windDown(minutes: 3)),
            (2280, .countdown(minutesLeft: 2)),
            (2340, .countdown(minutesLeft: 1)),
        ]

        for (elapsed, expected) in steps {
            let due = FocusVoiceSchedule.nextAnnouncement(duration: fortyMinutes, elapsed: elapsed, alreadyAnnounced: announced)
            #expect(due == expected)
            announced.formUnion(FocusVoiceSchedule.dueMilestones(duration: fortyMinutes, elapsed: elapsed))
        }

        // Repeating the last elapsed value must not speak anything twice.
        #expect(FocusVoiceSchedule.nextAnnouncement(duration: fortyMinutes, elapsed: 2340, alreadyAnnounced: announced) == nil)
    }

    @Test("3 minutes left coincides with wind-down for a 40-minute task; both are due, only the latest is spoken")
    func countdownAndWindDownCanCoincide() {
        // A 40-minute task's wind-down window is 3 minutes (>= 20, < 45),
        // which lands on the same elapsed instant as the "3 minutes left"
        // countdown step — by design, the reflection window opens exactly
        // when the final countdown for this task length begins.
        let elapsed: TimeInterval = 2220
        let due = FocusVoiceSchedule.dueMilestones(duration: fortyMinutes, elapsed: elapsed)
        #expect(due.contains(.countdown(minutesLeft: 3)))
        #expect(due.contains(.windDown(minutes: 3)))

        // Only the most recent of everything due is spoken...
        let spoken = FocusVoiceSchedule.nextAnnouncement(duration: fortyMinutes, elapsed: elapsed, alreadyAnnounced: [])
        #expect(spoken == .windDown(minutes: 3))

        // ...and the caller marks every due milestone as announced, not just
        // the spoken one, so the coincident countdown step never surfaces
        // later out of order.
        let announced = Set(due)
        #expect(FocusVoiceSchedule.nextAnnouncement(duration: fortyMinutes, elapsed: elapsed, alreadyAnnounced: announced) == nil)
    }

    @Test("A task started mid-way does not announce milestones already passed")
    func midwayStartSkipsPassedMilestones() {
        // Picked up at 1500s elapsed into a 40-minute task: the 25%-elapsed
        // mark (30 minutes left, at 600s) and the 50%-elapsed mark (20
        // minutes left, at 1200s) have both already passed. Only the freshest
        // one should ever be spoken — never a catch-up of the older one.
        let due = FocusVoiceSchedule.nextAnnouncement(duration: fortyMinutes, elapsed: 1500, alreadyAnnounced: [])
        #expect(due == .timeLeft(minutes: 20))
        #expect(due != .timeLeft(minutes: 30))
    }

    @Test("Pausing and resuming does not repeat an announcement already made")
    func pauseResumeDoesNotRepeat() {
        var announced: Set<FocusVoiceMilestone> = []

        // The milestone at 1800s elapsed fires once...
        let due = FocusVoiceSchedule.nextAnnouncement(duration: fortyMinutes, elapsed: 1800, alreadyAnnounced: announced)
        #expect(due == .timeLeft(minutes: 10))
        announced.formUnion(FocusVoiceSchedule.dueMilestones(duration: fortyMinutes, elapsed: 1800))

        // ...and while paused, elapsed time is frozen (the timer contributes
        // nothing), so calling again at the same instant must stay silent.
        #expect(FocusVoiceSchedule.nextAnnouncement(duration: fortyMinutes, elapsed: 1800, alreadyAnnounced: announced) == nil)

        // Resuming and continuing on, with no new threshold crossed yet,
        // must also stay silent.
        #expect(FocusVoiceSchedule.nextAnnouncement(duration: fortyMinutes, elapsed: 1950, alreadyAnnounced: announced) == nil)
    }

    @Test("Wind-down length is 5 / 3 / 1 minutes, tested exactly on the 45 and 20-minute boundaries")
    func windDownBoundaries() {
        #expect(FocusVoiceSchedule.windDownMinutes(forTaskMinutes: 45) == 5)
        #expect(FocusVoiceSchedule.windDownMinutes(forTaskMinutes: 44.999) == 3)
        #expect(FocusVoiceSchedule.windDownMinutes(forTaskMinutes: 60) == 5)

        #expect(FocusVoiceSchedule.windDownMinutes(forTaskMinutes: 20) == 3)
        #expect(FocusVoiceSchedule.windDownMinutes(forTaskMinutes: 19.999) == 1)
        #expect(FocusVoiceSchedule.windDownMinutes(forTaskMinutes: 30) == 3)

        #expect(FocusVoiceSchedule.windDownMinutes(forTaskMinutes: 5) == 1)
    }

    @Test("The wind-down prompt wins its tie with the countdown, so reflection is never swallowed")
    func windDownBeatsCountdownOnTheSameThreshold() {
        // A wind-down window is 5, 3 or 1 minutes, and every one of those is
        // also a countdown minute — so the two ALWAYS fall on the same
        // threshold. Only the last due milestone is spoken, so without an
        // explicit tie-break the reflection prompt can be lost entirely.
        for taskMinutes in [60.0, 45.0, 30.0, 20.0, 10.0] {
            let duration = taskMinutes * 60
            let windDown = FocusVoiceSchedule.windDownMinutes(forTaskMinutes: taskMinutes)
            let atWindDown = duration - Double(windDown) * 60

            let spoken = FocusVoiceSchedule.nextAnnouncement(
                duration: duration,
                elapsed: atWindDown,
                alreadyAnnounced: []
            )
            #expect(spoken == .windDown(minutes: windDown), "task of \(taskMinutes) min spoke \(String(describing: spoken))")
        }
    }
}

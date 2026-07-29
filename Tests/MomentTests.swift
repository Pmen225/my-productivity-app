import Testing
@testable import Flowmap

/// The moment layer decides two things worth pinning: which award becomes
/// which moment, and which moment wins when two land in the same run loop.
@MainActor
struct MomentTests {
    @Test func plainAwardShowsXPToast() {
        let service = FlowMomentService()
        service.show(GamificationAwardResult(xpAwarded: 10, totalXP: 10, levelBefore: 1, levelAfter: 1))
        #expect(service.current == .xp(10))
    }

    @Test func levellingUpReplacesTheXPToastWithTheRankStamp() {
        let service = FlowMomentService()
        service.show(GamificationAwardResult(xpAwarded: 25, totalXP: 120, levelBefore: 1, levelAfter: 2))
        #expect(service.current == .rankUp(level: 2, xp: 25))
    }

    @Test func awardWorthNoXPShowsNothing() {
        let service = FlowMomentService()
        service.show(GamificationAwardResult(xpAwarded: 0, totalXP: 10, levelBefore: 1, levelAfter: 1))
        #expect(service.current == nil)
    }

    /// Finishing a task raises the `COMPLETE` band and then awards XP. The
    /// band has to survive that, or the user never sees which task finished.
    @Test func theCompleteBandIsNotWipedOutByTheXPToastBehindIt() {
        let service = FlowMomentService()
        service.show(.done(taskTitle: "Reading"))
        service.show(GamificationAwardResult(xpAwarded: 30, totalXP: 60, levelBefore: 1, levelAfter: 1))
        #expect(service.current == .done(taskTitle: "Reading"))
    }

    /// A rank crossing still outranks the band, because it is the rarer news.
    @Test func aRankCrossingStillWinsOverTheCompleteBand() {
        let service = FlowMomentService()
        service.show(.done(taskTitle: "Reading"))
        service.show(GamificationAwardResult(xpAwarded: 30, totalXP: 260, levelBefore: 2, levelAfter: 3))
        #expect(service.current == .rankUp(level: 3, xp: 30))
    }

    @Test func dismissClearsTheSlot() {
        let service = FlowMomentService()
        service.show(.hud("Task added — Inbox"))
        #expect(service.current == .hud("Task added — Inbox"))
        service.dismiss()
        #expect(service.current == nil)
    }
}

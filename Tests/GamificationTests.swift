import Foundation
import Testing
@testable import Flowmap

@Suite("Gamification curve")
struct GamificationCurveTests {
    @Test("Level 1 costs exactly 100 XP")
    func level1Cost() {
        #expect(GamificationCurve.cost(ofLevel: 1) == 100)
    }

    @Test("Level 2's raw cost (282.84) actually needs the nearest-10 rounding")
    func level2CostBitesRounding() {
        // 100 × 2^1.5 = 282.84…, which is NOT a multiple of 10 — a naive
        // "already rounded" assumption would silently keep 282 or 283.
        #expect(GamificationCurve.cost(ofLevel: 2) == 280)
    }

    @Test("Level 5's raw cost (1118.03) also rounds to the nearest 10")
    func level5Cost() {
        #expect(GamificationCurve.cost(ofLevel: 5) == 1120)
    }

    @Test("Level 0 and below cost nothing — there is no level 0 to buy into")
    func nonPositiveLevelCostsNothing() {
        #expect(GamificationCurve.cost(ofLevel: 0) == 0)
        #expect(GamificationCurve.cost(ofLevel: -3) == 0)
    }

    @Test("Zero XP is level 1 with nothing earned into it")
    func zeroXPIsLevelOne() {
        let level = GamificationCurve.level(forTotalXP: 0)
        #expect(level.level == 1)
        #expect(level.xpIntoLevel == 0)
        #expect(level.xpForLevel == 100)
    }

    @Test("XP one short of level 1's cost stays at level 1")
    func justBelowThresholdStays() {
        let level = GamificationCurve.level(forTotalXP: 99)
        #expect(level.level == 1)
        #expect(level.xpIntoLevel == 99)
    }

    @Test("XP that exactly meets level 1's cost rolls over to level 2")
    func exactThresholdRollsOver() {
        let level = GamificationCurve.level(forTotalXP: 100)
        #expect(level.level == 2)
        #expect(level.xpIntoLevel == 0)
        #expect(level.xpForLevel == 280)
    }

    @Test("XP that clears levels 1 and 2's cost (380) reaches level 3")
    func multipleLevelsRollOver() {
        let level = GamificationCurve.level(forTotalXP: 380)
        #expect(level.level == 3)
        #expect(level.xpIntoLevel == 0)
        #expect(level.xpForLevel == 520)
    }

    @Test("A total that only partly covers level 2's cost stays at level 2")
    func partialSecondLevel() {
        let level = GamificationCurve.level(forTotalXP: 379)
        #expect(level.level == 2)
        #expect(level.xpIntoLevel == 279)
    }
}

@Suite("Gamification award table")
struct GamificationAwardTests {
    @Test("Per-minute task award, at several lengths")
    func taskCompletedAward() {
        #expect(GamificationAward.taskCompleted(estimatedMinutes: 1).xp == 1)
        #expect(GamificationAward.taskCompleted(estimatedMinutes: 42).xp == 42)
        #expect(GamificationAward.taskCompleted(estimatedMinutes: 0).xp == 0)
    }

    @Test("Subtask completed is worth a flat 5 XP")
    func subtaskAward() {
        #expect(GamificationAward.subtaskCompleted.xp == 5)
    }

    @Test("Planning a task (Definition of Done) is worth 10 XP")
    func plannedAward() {
        #expect(GamificationAward.taskPlanned.xp == 10)
    }

    @Test("A closed project is worth 25 XP per task it held")
    func projectClosedAward() {
        #expect(GamificationAward.projectClosed(taskCount: 4).xp == 100)
        #expect(GamificationAward.projectClosed(taskCount: 0).xp == 0)
    }

    @Test("Clearing the whole day is a flat 50 XP")
    func dayClearedAward() {
        #expect(GamificationAward.dayCleared.xp == 50)
    }
}

@Suite("Gamification service")
@MainActor
struct GamificationServiceTests {
    @Test("Awarding XP that stays within the level does not report a level-up")
    func noLevelUpWithinLevel() throws {
        let world = try TestWorld()
        let service = world.gamification()
        let result = service.award(.subtaskCompleted)
        #expect(result.didLevelUp == false)
        #expect(result.totalXP == 5)
        #expect(world.settings.totalXP == 5)
    }

    @Test("Crossing exactly one boundary reports a level-up exactly once")
    func levelUpReportedOnce() throws {
        let world = try TestWorld()
        world.settings.totalXP = 90
        let service = world.gamification()
        let result = service.award(.taskCompleted(estimatedMinutes: 15))
        #expect(result.levelBefore == 1)
        #expect(result.levelAfter == 2)
        #expect(result.didLevelUp == true)
    }

    @Test("Crossing two boundaries in one award still reports a single level-up flag")
    func multiLevelJumpStillOneFlag() throws {
        let world = try TestWorld()
        world.settings.totalXP = 90
        let service = world.gamification()
        // 90 + 300 = 390: clears level 1 (100) and level 2 (280), landing partway into level 3.
        let result = service.award(.taskCompleted(estimatedMinutes: 300))
        #expect(result.levelBefore == 1)
        #expect(result.levelAfter == 3)
        #expect(result.didLevelUp == true)
    }

    @Test("Toggling a subtask complete awards XP once; un-completing it does not refund or re-award")
    func toggleSubtaskAwardsOnlyOnCompletion() throws {
        let world = try TestWorld()
        let task = world.makeTask("Write chapter")
        let subtask = Subtask(title: "Draft outline", task: task)
        world.context.insert(subtask)
        try world.context.save()

        world.gamification().toggleSubtask(subtask)
        #expect(subtask.isCompleted == true)
        #expect(world.settings.totalXP == 5)

        world.gamification().toggleSubtask(subtask)
        #expect(subtask.isCompleted == false)
        #expect(world.settings.totalXP == 5)
    }

    @Test("MapNodeView and ProgressScreen read the same service and so cannot disagree")
    func twoConstructionsAgree() throws {
        let world = try TestWorld()
        world.settings.totalXP = 250
        let a = GamificationService(context: world.context, settings: world.settings)
        let b = GamificationService(context: world.context, settings: world.settings)
        #expect(a.level == b.level)
    }
}

@Suite("Gamification wired to real events")
@MainActor
struct GamificationWiringTests {
    @Test("Resolving the compulsory planning gate awards +10 exactly once")
    func planningGateAwardsOnce() throws {
        let world = try TestWorld()
        let task = world.makeTask("Read paper", planned: false)
        let engine = world.focusEngine()

        let blocked = engine.start(task: task)
        #expect(blocked == nil)
        #expect(engine.pendingGate?.kind == .planGate)

        let subtask = Subtask(title: "Summarise in 5 bullets", task: task)
        world.context.insert(subtask)
        try world.context.save()

        let session = engine.resolveGate()
        #expect(session != nil)
        #expect(world.settings.totalXP == 10)

        // A later start of the same, now-planned task must not re-award.
        engine.stop()
        _ = engine.start(task: task)
        #expect(world.settings.totalXP == 10)
    }

    @Test("Completing a focus session awards +1 XP per estimated minute")
    func completingTaskAwardsPerEstimatedMinute() throws {
        let world = try TestWorld()
        let task = world.makeTask("Write report", minutes: 42)
        let engine = world.focusEngine()

        _ = engine.start(task: task, now: world.date(hour: 9))
        engine.completeCurrentTask(now: world.date(hour: 9, minute: 20))

        #expect(world.settings.totalXP == 42)
        #expect(task.status == .completed)
    }

    @Test("Clearing every one of today's segments, with at least one completed, awards the +50 day bonus exactly once")
    func dayClearedAwardsOnce() throws {
        let world = try TestWorld()
        let task = world.makeTask("Morning admin", minutes: 30)
        let engine = world.focusEngine()
        let start = world.date(hour: 9)
        world.makeSegment(for: task, start: start, minutes: 30)

        _ = engine.start(task: task, now: start)
        engine.completeCurrentTask(now: start.addingTimeInterval(30 * 60))

        // The task's own +30 XP plus the day-cleared +50 bonus.
        #expect(world.settings.totalXP == 80)
        #expect(world.settings.lastDayClearedAwardDay != nil)

        // A second task finishing later the same day re-runs the day-cleared
        // check (every completion does), but must not grant the +50 again —
        // only that second task's own +10 should land.
        let second = world.makeTask("Quick email", minutes: 10)
        world.makeSegment(for: second, start: start.addingTimeInterval(30 * 60), minutes: 10)
        _ = engine.start(task: second, now: start.addingTimeInterval(30 * 60))
        engine.completeCurrentTask(now: start.addingTimeInterval(40 * 60))

        #expect(world.settings.totalXP == 90)
    }

    @Test("Completing a task straight from the requeue banner also awards its per-minute XP")
    func completingFromBannerAwardsPerEstimatedMinute() throws {
        let world = try TestWorld()
        let task = world.makeTask("Reply to emails", minutes: 20)
        let engine = world.focusEngine()

        let outcome = RequeueOutcome(
            taskID: task.id,
            taskTitle: task.title,
            minutes: 20,
            newStart: nil,
            movedToAnotherDay: false,
            failureReason: nil
        )
        engine.completeFromBanner(outcome)

        #expect(world.settings.totalXP == 20)
        #expect(task.status == .completed)
    }
}

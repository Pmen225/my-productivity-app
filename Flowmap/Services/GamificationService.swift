import Foundation
import SwiftData

/// The result of awarding XP: the level before and after, so a caller that
/// renders UI can trigger the level-up roll only when a boundary was
/// actually crossed, rather than on every XP gain.
public struct GamificationAwardResult: Equatable, Sendable {
    public let xpAwarded: Int
    public let totalXP: Int
    public let levelBefore: Int
    public let levelAfter: Int
    public var didLevelUp: Bool { levelAfter > levelBefore }
}

/// Owns the one copy of the app's XP bookkeeping: the curve and award table
/// live in `GamificationCurve` (pure, tested without a simulator); this type
/// is the store-facing half that persists total XP and applies awards — the
/// same split `SchedulingEngine`/`SchedulingService` uses for planning.
///
/// A value type built fresh wherever it is needed, exactly like
/// `SchedulingService` — there is no per-instance state to keep alive.
@MainActor
public struct GamificationService {
    private let context: ModelContext
    private let settings: AppSettings
    /// Raises the XP toast and the rank stamp. Every award in the app comes
    /// through `award(_:)`, so wiring the feedback here rather than at each of
    /// the five call sites means none of them can forget it. Optional so tests
    /// and App Intents can build the service without any UI attached.
    private let moments: FlowMomentService?

    public init(context: ModelContext, settings: AppSettings, moments: FlowMomentService? = nil) {
        self.context = context
        self.settings = settings
        self.moments = moments
    }

    /// Level, XP-into-level and XP-for-level, computed fresh from the
    /// persisted total every read — never stored, so `MapNodeView` and
    /// `ProgressScreen` agree by construction rather than by coincidence.
    public var level: GamificationLevel {
        GamificationCurve.level(forTotalXP: settings.totalXP)
    }

    /// Adds an award's XP to the persisted total and reports whether a level
    /// boundary was crossed, so the caller can trigger the roll animation.
    @discardableResult
    public func award(_ award: GamificationAward) -> GamificationAwardResult {
        let before = level
        settings.totalXP = max(0, settings.totalXP + award.xp)
        settings.touch()
        try? context.save()
        let after = level
        let result = GamificationAwardResult(
            xpAwarded: award.xp,
            totalXP: settings.totalXP,
            levelBefore: before.level,
            levelAfter: after.level
        )
        moments?.show(result)
        return result
    }

    /// Toggles a subtask and awards `.subtaskCompleted` exactly when the
    /// toggle newly completes it — not when it is un-checked. The one place
    /// every subtask row calls, so the "did this just become done" check
    /// lives once rather than in each of the three rows that render one.
    public func toggleSubtask(_ subtask: Subtask) {
        let wasCompleted = subtask.isCompleted
        subtask.toggle()
        if !wasCompleted && subtask.isCompleted {
            award(.subtaskCompleted)
        } else {
            try? context.save()
        }
    }
}

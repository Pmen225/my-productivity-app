import Foundation

/// One event that earns XP, and how much it is worth — the design's full
/// award table, kept as data so no call site re-derives its own numbers.
/// See `state/specs/design-inventory.md` §"XP / levelling" for the source.
public enum GamificationAward: Equatable, Sendable {
    /// A task completed, worth its estimated length in minutes — the design's
    /// own wording is "per estimated minute", not time actually spent, so a
    /// task finished early or late earns the same XP either way.
    case taskCompleted(estimatedMinutes: Int)
    case subtaskCompleted
    /// The compulsory planning gate recorded a Definition of Done.
    case taskPlanned
    /// A project closed, worth 25 XP for every task it held.
    case projectClosed(taskCount: Int)
    /// Every one of today's segments reached a terminal state, with at least
    /// one of them completed.
    case dayCleared

    public var xp: Int {
        switch self {
        case .taskCompleted(let estimatedMinutes): max(0, estimatedMinutes)
        case .subtaskCompleted: 5
        case .taskPlanned: 10
        case .projectClosed(let taskCount): 25 * max(0, taskCount)
        case .dayCleared: 50
        }
    }
}

/// The level a total XP figure has reached, how far into it, and how much
/// that level demands — always computed fresh from the total, never itself
/// stored, exactly as `Project.progress` computes from its tasks every read.
public struct GamificationLevel: Equatable, Sendable {
    public let level: Int
    /// XP earned since the start of `level`.
    public let xpIntoLevel: Int
    /// XP `level` demands before the next one starts.
    public let xpForLevel: Int

    public var fraction: Double {
        xpForLevel > 0 ? Double(xpIntoLevel) / Double(xpForLevel) : 0
    }
}

/// The design's XP curve and award table, isolated from SwiftUI and SwiftData
/// so the maths can be proven without a simulator — the same split
/// `FocusVoiceSchedule` uses for the voice coach's timing.
public enum GamificationCurve {
    /// Cost of level `l`: `100 × l^1.5`, rounded to the nearest 10. This is
    /// the XP a player already AT level `l` must earn to reach `l + 1`.
    public static func cost(ofLevel level: Int) -> Int {
        guard level > 0 else { return 0 }
        let raw = 100 * pow(Double(level), 1.5)
        return Int((raw / 10).rounded()) * 10
    }

    /// The level `totalXP` has reached, the XP already earned into it, and
    /// what that level demands. A total of 0 is level 1 with nothing yet
    /// earned into it — nobody starts at level 0. "Meets or exceeds" a
    /// level's cost rolls over, matching the design's own `lvlInfo` rule.
    public static func level(forTotalXP totalXP: Int) -> GamificationLevel {
        var level = 1
        var remaining = max(0, totalXP)
        while remaining >= cost(ofLevel: level) {
            remaining -= cost(ofLevel: level)
            level += 1
        }
        return GamificationLevel(level: level, xpIntoLevel: remaining, xpForLevel: cost(ofLevel: level))
    }
}

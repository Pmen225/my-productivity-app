import Foundation

/// One "which comes first?" duel: two task identities, presented in no
/// particular precedence — picking either is what assigns first/second, not
/// the pair's own field order.
public struct DuelPair: Hashable, Sendable {
    public let first: UUID
    public let second: UUID
}

/// The prioritise duel's pairing, tallying and ranking — the design's "pairwise
/// 'Which comes first?' duels over the inbox (all combinations), tallies wins,
/// reveals a medal-ranked order" mini-game. See `state/specs/design-inventory.md`
/// §"Prioritise duel mini-game".
///
/// Kept free of SwiftUI and SwiftData, the same split `FocusVoiceSchedule` uses
/// for the voice coach's timing and `GamificationCurve` uses for the XP curve:
/// a caller hands over task identities and picks, gets pairs or a ranking back,
/// and the interesting cases — pair count, ties, stability — can be proven
/// without a simulator.
public enum PrioritiseDuel {
    /// The game needs at least two entrants; with one or zero there is no
    /// choice to make, so the entry point must not be offered at all.
    public static func isAvailable(for identities: [UUID]) -> Bool {
        identities.count >= 2
    }

    /// Every unordered pair of `identities`, exactly once each, with no task
    /// ever paired against itself — `N(N−1)/2` pairs for `N` identities.
    /// Fewer than two identities yields no pairs.
    public static func pairs(for identities: [UUID]) -> [DuelPair] {
        guard identities.count >= 2 else { return [] }
        var result: [DuelPair] = []
        result.reserveCapacity(identities.count * (identities.count - 1) / 2)
        for i in identities.indices {
            for j in identities.index(after: i)..<identities.endIndex {
                result.append(DuelPair(first: identities[i], second: identities[j]))
            }
        }
        return result
    }

    /// Ranks `identities` by how many `picks` each won — one winning identity
    /// per duel judged, in any order; a task with no recorded win counts as
    /// zero.
    ///
    /// Ties keep the entrant's original position in `identities` rather than
    /// whatever order the sort happens to visit them in. That is what makes
    /// this deterministic: the same `identities` and `picks` always yield the
    /// same ranking, so a reveal computed twice from the same picks never
    /// contradicts itself between renders.
    public static func rank(identities: [UUID], picks: [UUID]) -> [UUID] {
        var wins: [UUID: Int] = [:]
        for winner in picks { wins[winner, default: 0] += 1 }
        return identities.enumerated()
            .sorted { lhs, rhs in
                let lhsWins = wins[lhs.element] ?? 0
                let rhsWins = wins[rhs.element] ?? 0
                if lhsWins != rhsWins { return lhsWins > rhsWins }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

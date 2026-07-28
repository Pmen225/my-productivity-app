import Foundation
import Testing
@testable import Flowmap

@Suite("Prioritise duel pairing")
struct PrioritiseDuelPairingTests {
    @Test("Two tasks produce exactly one pair")
    func twoTasksOnePair() {
        let ids = [UUID(), UUID()]
        #expect(PrioritiseDuel.pairs(for: ids).count == 1)
    }

    @Test("Three tasks produce exactly three pairs")
    func threeTasksThreePairs() {
        let ids = (0..<3).map { _ in UUID() }
        #expect(PrioritiseDuel.pairs(for: ids).count == 3)
    }

    @Test("Pair count matches N(N-1)/2 for several sizes")
    func pairCountFormula() {
        for n in [2, 3, 4, 5, 8] {
            let ids = (0..<n).map { _ in UUID() }
            #expect(PrioritiseDuel.pairs(for: ids).count == n * (n - 1) / 2)
        }
    }

    @Test("Every unordered pair appears exactly once, with no self-pairing")
    func everyPairOnceNoSelfPairing() {
        let ids = (0..<5).map { _ in UUID() }
        let pairs = PrioritiseDuel.pairs(for: ids)

        for pair in pairs {
            #expect(pair.first != pair.second)
        }

        var seen: Set<Set<UUID>> = []
        for pair in pairs {
            let key: Set<UUID> = [pair.first, pair.second]
            #expect(!seen.contains(key))
            seen.insert(key)
        }
        #expect(seen.count == pairs.count)
    }

    @Test("Fewer than two tasks offers no game")
    func fewerThanTwoOffersNoGame() {
        #expect(PrioritiseDuel.pairs(for: []).isEmpty)
        #expect(PrioritiseDuel.pairs(for: [UUID()]).isEmpty)
        #expect(PrioritiseDuel.isAvailable(for: []) == false)
        #expect(PrioritiseDuel.isAvailable(for: [UUID()]) == false)
        #expect(PrioritiseDuel.isAvailable(for: [UUID(), UUID()]) == true)
    }
}

@Suite("Prioritise duel ranking")
struct PrioritiseDuelRankingTests {
    @Test("Ranks by win count, most wins first")
    func ranksByWinCount() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let ids = [a, b, c]
        // b wins twice, c wins once, a never wins.
        let picks = [b, b, c]
        #expect(PrioritiseDuel.rank(identities: ids, picks: picks) == [b, c, a])
    }

    @Test("Tied win counts keep the entrants' original relative order")
    func tiesKeepOriginalOrder() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let ids = [a, b, c]
        // No picks at all: every task ties at zero wins.
        #expect(PrioritiseDuel.rank(identities: ids, picks: []) == [a, b, c])
    }

    @Test("A tie further down the ranking also keeps original order, around a clear leader")
    func partialTieKeepsOrder() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let ids = [a, b, c]
        // a wins both its duels; b and c never win, so they tie at zero.
        let picks = [a, a]
        #expect(PrioritiseDuel.rank(identities: ids, picks: picks) == [a, b, c])
    }

    @Test("Ranking is stable across repeated reads of the same picks")
    func stableAcrossRepeatedReads() {
        let ids = (0..<6).map { _ in UUID() }
        let picks = [ids[2], ids[2], ids[4], ids[0]]

        let first = PrioritiseDuel.rank(identities: ids, picks: picks)
        let second = PrioritiseDuel.rank(identities: ids, picks: picks)
        let third = PrioritiseDuel.rank(identities: ids, picks: picks)

        #expect(first == second)
        #expect(second == third)
    }
}

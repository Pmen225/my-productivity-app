import Foundation
import Observation

/// A short, self-dismissing thing the app says about what just happened: XP
/// earned, a rank crossed, a task finished, a milestone reached, or a one-line
/// confirmation of something the user just did.
///
/// One vocabulary shared by every feature, so the chrome renders these in a
/// single place instead of each screen growing its own toast.
public enum FlowMoment: Equatable, Sendable {
    /// Short dark pill, top-centred — a confirmation or a refusal.
    case hud(String)
    /// Top glass banner with a title and a supporting line.
    case notif(title: String, subtitle: String)
    /// `+N XP`, shown for every award that did not also cross a level.
    case xp(Int)
    /// Supersedes the XP toast when a level boundary is crossed, so the two
    /// never fight over the same corner of the screen.
    case rankUp(level: Int, xp: Int)
    /// The `COMPLETE` band a finished task earns.
    case done(taskTitle: String)

    /// How long it stays up. A rank crossing earns longer on screen than a
    /// confirmation the user already expected.
    public var duration: TimeInterval {
        switch self {
        case .hud: 2
        case .notif: 4
        case .xp: 1.6
        case .rankUp: 2.6
        case .done: 2.6
        }
    }

    /// Which moment wins when two land together. Finishing a task fires both
    /// the `COMPLETE` band and an XP award in the same run loop, and crossing
    /// a level fires on top of that — without a ranking the last one written
    /// wins, which is the least interesting one about half the time.
    var priority: Int {
        switch self {
        case .rankUp: 4
        case .done: 3
        case .notif: 2
        case .xp: 1
        case .hud: 0
        }
    }
}

/// Holds the one moment currently on screen and takes it away again.
///
/// Deliberately a single slot rather than a queue: two of these stacked is
/// noise, and the newest is always the one worth reading.
@MainActor
@Observable
public final class FlowMomentService {
    public private(set) var current: FlowMoment?

    private var dismissal: Task<Void, Never>?

    public init() {}

    public func show(_ moment: FlowMoment) {
        // A moment already on screen only yields to one that outranks it, so
        // the `COMPLETE` band is not wiped out by the XP toast the same
        // completion raised a line later.
        if let current, current.priority > moment.priority { return }
        dismissal?.cancel()
        current = moment
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(moment.duration))
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    /// Turns an award into whichever of the two gamification moments it
    /// earned. Crossing a level replaces the plain XP toast rather than
    /// queueing behind it.
    public func show(_ result: GamificationAwardResult) {
        guard result.xpAwarded > 0 else { return }
        if result.didLevelUp {
            show(.rankUp(level: result.levelAfter, xp: result.xpAwarded))
        } else {
            show(.xp(result.xpAwarded))
        }
    }

    public func dismiss() {
        dismissal?.cancel()
        current = nil
    }
}

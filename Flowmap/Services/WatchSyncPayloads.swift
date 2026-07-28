import Foundation

/// The wire format between the phone and the watch.
///
/// Compiled into both targets, so it deliberately depends on nothing but
/// Foundation — no SwiftData, no SwiftUI. The watch never queries the store; it
/// renders the last snapshot it was handed and sends commands back, which keeps
/// one scheduling brain (`SchedulingService`) and one timing brain
/// (`FocusEngine`) on the phone where the data lives.
public struct WatchSnapshot: Codable, Sendable, Equatable {

    /// One scheduled block of the day.
    public struct Item: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var title: String
        /// `ColourToken.rawValue` — resolved to a colour on the watch.
        public var colourToken: String
        public var start: Date
        public var end: Date
        public var isDone: Bool
        public var isActive: Bool
        /// True for calendar events the app does not own.
        public var isExternal: Bool

        public init(
            id: UUID,
            title: String,
            colourToken: String,
            start: Date,
            end: Date,
            isDone: Bool,
            isActive: Bool,
            isExternal: Bool
        ) {
            self.id = id
            self.title = title
            self.colourToken = colourToken
            self.start = start
            self.end = end
            self.isDone = isDone
            self.isActive = isActive
            self.isExternal = isExternal
        }
    }

    public var generatedAt: Date
    public var activeTitle: String?
    public var activeColourToken: String?
    /// When the running session runs out. Absent while paused — the watch shows
    /// `pausedRemaining` instead, so a paused timer never drifts.
    public var activeEndsAt: Date?
    public var pausedRemaining: TimeInterval?
    public var activeTotalSeconds: TimeInterval?
    public var isPaused: Bool
    public var items: [Item]
    public var plannedMinutes: Int
    public var remainingMinutes: Int
    public var completedCount: Int
    public var totalCount: Int

    public init(
        generatedAt: Date = Date(),
        activeTitle: String? = nil,
        activeColourToken: String? = nil,
        activeEndsAt: Date? = nil,
        pausedRemaining: TimeInterval? = nil,
        activeTotalSeconds: TimeInterval? = nil,
        isPaused: Bool = false,
        items: [Item] = [],
        plannedMinutes: Int = 0,
        remainingMinutes: Int = 0,
        completedCount: Int = 0,
        totalCount: Int = 0
    ) {
        self.generatedAt = generatedAt
        self.activeTitle = activeTitle
        self.activeColourToken = activeColourToken
        self.activeEndsAt = activeEndsAt
        self.pausedRemaining = pausedRemaining
        self.activeTotalSeconds = activeTotalSeconds
        self.isPaused = isPaused
        self.items = items
        self.plannedMinutes = plannedMinutes
        self.remainingMinutes = remainingMinutes
        self.completedCount = completedCount
        self.totalCount = totalCount
    }

    public var hasActiveSession: Bool { activeTitle != nil }

    /// Seconds left at `date`, from whichever of the two clocks applies.
    public func remainingSeconds(at date: Date = Date()) -> TimeInterval {
        if isPaused { return max(pausedRemaining ?? 0, 0) }
        guard let activeEndsAt else { return 0 }
        return max(activeEndsAt.timeIntervalSince(date), 0)
    }

    public func progress(at date: Date = Date()) -> Double {
        guard let total = activeTotalSeconds, total > 0 else { return 0 }
        return min(max(1 - remainingSeconds(at: date) / total, 0), 1)
    }
}

/// What the watch can ask the phone to do. Every case maps onto a method that
/// already exists on `FocusEngine` or the capture path — the watch adds no
/// behaviour of its own.
public enum WatchCommand: Codable, Sendable, Equatable {
    case togglePause
    case complete
    case skip
    case startNext
    /// Dictated or scribbled text destined for the inbox.
    case capture(String)
    case requestSnapshot
}

/// Message dictionary keys, shared so a typo cannot desynchronise the two sides.
public enum WatchSyncKey {
    public static let snapshot = "flowmap.snapshot"
    public static let command = "flowmap.command"
}

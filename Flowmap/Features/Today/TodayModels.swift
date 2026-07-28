import Foundation
#if os(iOS)
import UIKit
#endif

// MARK: - Timeline block

/// One visual block on the Today timeline: either a Flowmap task segment or an
/// external calendar event. A UI-layer union only — segments and events keep
/// their own identity, nothing here is persisted or duplicated.
struct TimelineBlock: Identifiable {
    enum Kind {
        case segment(TaskSegment)
        case external(ExternalCalendarEvent)
    }

    let id: String
    let start: Date
    let end: Date
    let kind: Kind

    init(segment: TaskSegment) {
        self.id = "segment-\(segment.id.uuidString)"
        self.start = segment.startDate
        self.end = segment.endDate
        self.kind = .segment(segment)
    }

    init(event: ExternalCalendarEvent) {
        self.id = "event-\(event.id)"
        self.start = event.start
        self.end = event.end
        self.kind = .external(event)
    }

    var segment: TaskSegment? {
        if case .segment(let segment) = kind { return segment }
        return nil
    }

    var isExternal: Bool {
        if case .external = kind { return true }
        return false
    }

    var title: String {
        switch kind {
        case .segment(let segment): segment.task?.title ?? "Untitled"
        case .external(let event): event.title
        }
    }

    var iconName: String {
        switch kind {
        case .segment(let segment): segment.task?.iconName ?? "circle"
        case .external: "calendar"
        }
    }

    var colourToken: ColourToken? {
        switch kind {
        case .segment(let segment): segment.task?.colour
        case .external: nil
        }
    }

    /// Only ever set for a Flowmap segment — external events are fixed by
    /// nature and are never draggable, so a lock icon on them would mislead.
    var isLocked: Bool {
        switch kind {
        case .segment(let segment): segment.isLocked
        case .external: false
        }
    }

    var badgeText: String? {
        switch kind {
        case .segment(let segment): segment.badgeText
        case .external: nil
        }
    }

    var minutes: Int {
        max(0, Int(end.timeIntervalSince(start) / 60))
    }
}

// MARK: - Header scope

/// The header's Day/Week/Month scope menu. Presentational only for now: the
/// timeline underneath always shows today regardless of the selection, since
/// a real week/month agenda is a separate feature this slice does not build.
/// Kept here (rather than wired into `TodayView`) so it stays a self-contained,
/// zero-behaviour-change visual affordance matching the mock's popover.
enum TodayScope: String, CaseIterable, Identifiable {
    case day = "Day"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }
}

// MARK: - Primary action

/// The screen's single primary action: resume the plan, or make one.
enum TodayPrimaryAction {
    case startCurrentTask(segment: TaskSegment)
    case planDay

    var title: String {
        switch self {
        case .startCurrentTask: "Start current task"
        case .planDay: "Plan my day"
        }
    }

    var symbolName: String {
        switch self {
        case .startCurrentTask: "play.fill"
        case .planDay: "sparkles"
        }
    }
}

// MARK: - Haptics

/// Thin wrapper so drag feedback reads the same wherever it is called from.
/// A no-op on macOS, where `UIImpactFeedbackGenerator` does not exist.
enum TimelineHaptics {
    static func dragStarted() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func dropSucceeded() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func dropRefused() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

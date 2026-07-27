import Foundation

/// All enums are persisted as their `String` raw value.
///
/// CloudKit-backed SwiftData stores are happiest with primitive columns, and raw
/// strings stay queryable from `#Predicate` (computed properties are not).
/// Every model therefore stores a `...Raw: String` and exposes a computed enum.

// MARK: - Task

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case inbox
    case planned
    case active
    case paused
    case completed
    case cancelled

    /// Work that still wants a place in the schedule.
    public var isOpen: Bool {
        switch self {
        case .inbox, .planned, .active, .paused: true
        case .completed, .cancelled: false
        }
    }

    /// Counts toward project progress. Cancelled work must not distort the ratio.
    public var isActionable: Bool {
        switch self {
        case .inbox, .planned, .active, .paused, .completed: true
        case .cancelled: false
        }
    }

    public var displayName: String {
        switch self {
        case .inbox: "Inbox"
        case .planned: "Planned"
        case .active: "Active"
        case .paused: "Paused"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        }
    }
}

public enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case none
    case low
    case medium
    case high

    /// Higher sorts earlier in the scheduling engine.
    public var weight: Int {
        switch self {
        case .none: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    public var displayName: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    /// Status must never be conveyed by colour alone.
    public var symbolName: String {
        switch self {
        case .none: "minus"
        case .low: "chevron.down"
        case .medium: "equal"
        case .high: "chevron.up.2"
        }
    }
}

public enum DayPeriod: String, Codable, CaseIterable, Sendable {
    case anytime
    case morning
    case afternoon
    case evening

    public var displayName: String {
        switch self {
        case .anytime: "Anytime"
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        }
    }

    /// Local hour window the period allows. `anytime` imposes no constraint.
    public var hourRange: Range<Int>? {
        switch self {
        case .anytime: nil
        case .morning: 0..<12
        case .afternoon: 12..<17
        case .evening: 17..<24
        }
    }
}

// MARK: - Schedule segments

public enum SegmentState: String, Codable, CaseIterable, Sendable {
    case scheduled
    case elapsed
    case completed
    case missed
    case cancelled

    /// Still occupies time on the timeline, so the planner must not overlap it.
    public var occupiesTimeline: Bool {
        switch self {
        case .scheduled, .elapsed, .completed: true
        case .missed, .cancelled: false
        }
    }
}

public enum SegmentSource: String, Codable, CaseIterable, Sendable {
    case manual
    case autoPlanned
    case carryover
    case focusContinuation

    /// Copy shown on a task block. Never shaming.
    public var badgeText: String? {
        switch self {
        case .manual, .autoPlanned: nil
        case .carryover: "Carried from earlier"
        case .focusContinuation: "Continues from focus"
        }
    }
}

// MARK: - Projects and lists

public enum ProjectStatus: String, Codable, CaseIterable, Sendable {
    case active
    case paused
    case completed
    case archived

    public var displayName: String {
        switch self {
        case .active: "Active"
        case .paused: "Paused"
        case .completed: "Completed"
        case .archived: "Archived"
        }
    }
}

public enum GroupingMode: String, Codable, CaseIterable, Sendable {
    case manual
    case priority

    public var displayName: String {
        switch self {
        case .manual: "Manual"
        case .priority: "Priority"
        }
    }
}

// MARK: - Notes

public enum NoteBlockType: String, Codable, CaseIterable, Sendable {
    case paragraph
    case heading1
    case heading2
    case bullet
    case numbered
    case checklist
    case quote
    case callout
    case divider

    public var displayName: String {
        switch self {
        case .paragraph: "Text"
        case .heading1: "Heading 1"
        case .heading2: "Heading 2"
        case .bullet: "Bulleted list"
        case .numbered: "Numbered list"
        case .checklist: "To-do list"
        case .quote: "Quote"
        case .callout: "Callout"
        case .divider: "Divider"
        }
    }

    public var symbolName: String {
        switch self {
        case .paragraph: "text.alignleft"
        case .heading1: "textformat.size.larger"
        case .heading2: "textformat.size"
        case .bullet: "list.bullet"
        case .numbered: "list.number"
        case .checklist: "checklist"
        case .quote: "text.quote"
        case .callout: "lightbulb"
        case .divider: "minus"
        }
    }

    public var acceptsText: Bool { self != .divider }

    public var markdownPrefix: String {
        switch self {
        case .paragraph: ""
        case .heading1: "# "
        case .heading2: "## "
        case .bullet: "- "
        case .numbered: "1. "
        case .checklist: "- [ ] "
        case .quote: "> "
        case .callout: "> **Note** "
        case .divider: "---"
        }
    }
}

// MARK: - Focus

public enum FocusOutcome: String, Codable, CaseIterable, Sendable {
    case running
    case completed
    case elapsed
    case skipped
    case abandoned

    public var isFinished: Bool { self != .running }
}

// MARK: - Assistant

public enum AssistantRole: String, Codable, CaseIterable, Sendable {
    case user
    case assistant
    case tool
    case system
}

public enum AssistantProvider: String, Codable, CaseIterable, Sendable {
    case anthropic
    case openai

    public var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        }
    }

    public var defaultModel: String {
        switch self {
        case .anthropic: "claude-sonnet-5"
        case .openai: "gpt-5"
        }
    }

    public var availableModels: [String] {
        switch self {
        case .anthropic: ["claude-fable-5", "claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5-20251001"]
        case .openai: ["gpt-5", "gpt-5-mini"]
        }
    }

    /// Keychain account name. Values themselves never leave the Keychain.
    public var keychainAccount: String { "assistant.apiKey.\(rawValue)" }
}

// MARK: - Appearance

public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// How many wheel segments the Focus screen reveals at once.
public enum WheelVisibility: String, Codable, CaseIterable, Sendable {
    case one
    case two
    case three
    case all

    public var displayName: String {
        switch self {
        case .one: "1"
        case .two: "2"
        case .three: "3"
        case .all: "All"
        }
    }

    /// Number of upcoming tasks drawn beside the active one, or `nil` for every task.
    public var visibleCount: Int? {
        switch self {
        case .one: 1
        case .two: 2
        case .three: 3
        case .all: nil
        }
    }

    public var announcement: String {
        switch self {
        case .all: "All tasks visible"
        case .one: "1 task visible"
        default: "\(displayName) tasks visible"
        }
    }
}

// MARK: - Recurrence

public enum RecurrenceFrequency: String, Codable, CaseIterable, Sendable {
    case none
    case daily
    case weekdays
    case weekly
    case monthly

    public var displayName: String {
        switch self {
        case .none: "Never"
        case .daily: "Every day"
        case .weekdays: "Every weekday"
        case .weekly: "Every week"
        case .monthly: "Every month"
        }
    }
}

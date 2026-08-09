import Foundation

/// Pure-data model for the Settings hub list (task 55). Splits the 8 existing
/// settings sections into 3 founder-specified groups so `SettingsScreen` can
/// render a native drill-in hierarchy instead of one long scroll. No SwiftData,
/// no View — kept separate so the grouping itself is independently testable.
enum SettingsHubRow: String, CaseIterable, Identifiable {
    case general, focusWheel, sounds, notifications, calendar, assistant, data, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .focusWheel: "Focus Wheel"
        case .sounds: "Sounds"
        case .notifications: "Notifications"
        case .calendar: "Calendar"
        case .assistant: "Assistant"
        case .data: "Data"
        case .about: "About"
        }
    }

    /// SF Symbol, monochrome and outlined per space-notes rule 7 — every name
    /// here already renders elsewhere in this codebase or is a long-standing
    /// stock SF Symbol.
    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .focusWheel: "gauge"
        case .sounds: "speaker.wave.2"
        case .notifications: "bell"
        case .calendar: "calendar"
        case .assistant: "sparkles"
        case .data: "externaldrive"
        case .about: "info.circle"
        }
    }
}

struct SettingsHubGroup: Identifiable {
    let title: String
    let rows: [SettingsHubRow]
    var id: String { title }
}

enum SettingsHub {
    static let groups: [SettingsHubGroup] = [
        SettingsHubGroup(title: "Personalise", rows: [.general, .focusWheel]),
        SettingsHubGroup(title: "Alerts & connections", rows: [.sounds, .notifications, .calendar, .assistant]),
        SettingsHubGroup(title: "Data & about", rows: [.data, .about]),
    ]
}

import SwiftUI

/// Semantic colour vocabulary shared by every surface.
///
/// A task keeps the same token in the map, the task list, the calendar, the
/// focus wheel and the progress charts, so the token — not a raw `Color` — is
/// what gets persisted.
public enum ColourToken: String, CaseIterable, Codable, Sendable {
    case violet
    case green
    case peach
    case blue
    case yellow
    case pink
    case teal
    case lavender

    public var displayName: String {
        switch self {
        case .violet: "Violet"
        case .green: "Green"
        case .peach: "Peach"
        case .blue: "Blue"
        case .yellow: "Yellow"
        case .pink: "Pink"
        case .teal: "Teal"
        case .lavender: "Lavender"
        }
    }

    /// Saturated enough to carry text, muted enough to sit in a calm layout.
    public var base: Color {
        switch self {
        case .violet: Color(red: 0.42, green: 0.35, blue: 0.80)
        case .green: Color(red: 0.36, green: 0.66, blue: 0.48)
        case .peach: Color(red: 0.88, green: 0.55, blue: 0.38)
        case .blue: Color(red: 0.29, green: 0.56, blue: 0.82)
        case .yellow: Color(red: 0.82, green: 0.65, blue: 0.24)
        case .pink: Color(red: 0.83, green: 0.44, blue: 0.60)
        case .teal: Color(red: 0.24, green: 0.61, blue: 0.63)
        case .lavender: Color(red: 0.58, green: 0.50, blue: 0.78)
        }
    }

    /// Pastel fill for blocks and wheel segments.
    public var soft: Color { base.opacity(0.18) }

    /// Slightly stronger fill for the active or selected state.
    public var softStrong: Color { base.opacity(0.30) }

    /// Legible on top of `soft` in both colour schemes.
    public var onSoft: Color { base }

    public static func token(_ raw: String) -> ColourToken {
        ColourToken(rawValue: raw) ?? .violet
    }

    /// Stable colour for content that never had one chosen, derived from its id
    /// so the same object keeps the same colour across launches and devices.
    public static func deterministic(for uuid: UUID) -> ColourToken {
        let all = ColourToken.allCases
        let hash = abs(uuid.uuidString.hashValue % all.count)
        return all[hash]
    }
}

/// Surfaces, separators and accents. Warm off-white in light, deep charcoal in dark.
public enum FlowTheme {
    public static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.07, green: 0.07, blue: 0.08)
            : Color(red: 0.98, green: 0.976, blue: 0.969)
    }

    /// Cards and raised rows.
    public static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.11, green: 0.11, blue: 0.125)
            : Color.white
    }

    /// Sunken wells: timeline gutters, empty slots, secondary containers.
    public static func surfaceSunken(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.09, green: 0.09, blue: 0.10)
            : Color(red: 0.957, green: 0.949, blue: 0.937)
    }

    /// Floating popovers such as the list ellipsis menu, dark in both schemes.
    public static let popoverSurface = Color(red: 0.13, green: 0.13, blue: 0.15)

    public static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    public static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.96) : Color(white: 0.10)
    }

    public static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.62) : Color(white: 0.42)
    }

    /// Restrained violet, the single accent for primary actions.
    public static let accent = ColourToken.violet.base

    /// Externally-owned calendar events: present, but never competing for attention.
    public static func externalEvent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.30) : Color(white: 0.78)
    }

    public static func shadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.45) : Color.black.opacity(0.07)
    }
}

/// Corner radii, 12–22pt by hierarchy.
public enum FlowRadius {
    public static let small: CGFloat = 12
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 22
    public static let pill: CGFloat = 999
}

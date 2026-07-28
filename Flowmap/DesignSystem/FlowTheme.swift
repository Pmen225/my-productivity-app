import SwiftUI

// MARK: - Hex convenience

/// Design tokens are specified in hex by the design source, so they are written
/// here in hex — one conversion in one place beats eight hand-decimalised triples
/// that nobody can diff against the design.
extension Color {
    fileprivate init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Semantic colour vocabulary shared by every surface.
///
/// A task keeps the same token in the map, the task list, the calendar, the
/// focus wheel and the progress charts, and the token — not a raw `Color` —
/// gets persisted.
public enum ColourToken: String, CaseIterable, Codable, Sendable {
    case clay
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
        case .clay: "Clay"
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

    /// Warmed towards the clay-and-cream palette: each hue is the design's pastel
    /// deepened until text sitting on `soft` still passes contrast.
    public var base: Color {
        switch self {
        case .clay: Color(hex: 0xC4703E)
        case .violet: Color(hex: 0x6F5FA8)
        case .green: Color(hex: 0x6E9C63)
        case .peach: Color(hex: 0xD08A4F)
        case .blue: Color(hex: 0x5A82AE)
        case .yellow: Color(hex: 0xC79A3C)
        case .pink: Color(hex: 0xC1738A)
        case .teal: Color(hex: 0x4E9A90)
        case .lavender: Color(hex: 0x8A72C0)
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

    /// The eight task pastels — clay is the chrome accent, never a content
    /// colour, so pickers and deterministic assignment draw from this list.
    public static let taskTokens: [ColourToken] = [
        .violet, .green, .peach, .blue, .yellow, .pink, .teal, .lavender,
    ]

    /// Stable colour for content that never had one chosen, derived from its id
    /// so the same object keeps the same colour across launches and devices.
    public static func deterministic(for uuid: UUID) -> ColourToken {
        let all = ColourToken.taskTokens
        let hash = abs(uuid.uuidString.hashValue % all.count)
        return all[hash]
    }
}

/// Surfaces, separators and accents. Warm cream in light, warm near-black in dark —
/// the palette is built from browns rather than greys so nothing in the app reads
/// cold next to the clay accent.
public enum FlowTheme {
    public static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x1E1913) : Color(hex: 0xF6F3EE)
    }

    /// Cards and raised rows.
    public static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x2A241D) : .white
    }

    /// Sunken wells: timeline gutters, empty slots, secondary containers.
    public static func surfaceSunken(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x272119) : Color(hex: 0xF4F1EC)
    }

    /// One step deeper than `surfaceSunken`: fixed blocks, inactive segments.
    public static func surfaceWell(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x3A322A) : Color(hex: 0xEDEAE3)
    }

    /// Translucent layer for controls that float over content — the tab bar,
    /// the wheel's view chips, the map's control strip.
    public static func glass(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x2A241D).opacity(0.62) : Color.white.opacity(0.62)
    }

    /// The one-pixel highlight that makes a glass surface read as glass.
    public static func glassBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.70)
    }

    /// Floating popovers such as the list ellipsis menu, dark in both schemes.
    public static let popoverSurface = Color(hex: 0x2E2620)

    public static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x3A322A) : Color(hex: 0xECE8E1)
    }

    /// Load-bearing lines: control borders, dividers that must be seen.
    public static func separatorStrong(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x4E4438) : Color(hex: 0xD9D2C8)
    }

    public static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF3EEE6) : Color(hex: 0x42382C)
    }

    /// Deepened from the design's `#8A7A66`, which measures 4.15:1 on white and
    /// 3.75:1 on the cream background — under the 4.5:1 the HIG asks for. This
    /// value reads as the same warm grey-brown at 6.38:1 and 5.76:1.
    public static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xC6BAA9) : Color(hex: 0x6B5D4B)
    }

    /// Eyebrow labels and other text that must recede without disappearing.
    ///
    /// The design's `#B3A48F` measures 2.44:1 on white — invisible to anyone with
    /// reduced contrast sensitivity, and eyebrows carry real information here.
    /// Deepened to 5.38:1 on white, 4.86:1 on cream; dark side lifted from
    /// 4.13:1 to 4.85:1 on a card.
    public static func tertiaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x9C8F7C) : Color(hex: 0x786854)
    }

    /// Clay. The single accent for fills, live timers, progress and graphics.
    public static let accent = Color(hex: 0xC4703E)

    /// Clay behind white text. The accent itself carries white at only 3.66:1,
    /// so every filled button, chip and pill uses this instead — 4.61:1, and the
    /// two read as the same colour side by side.
    public static let accentFill = Color(hex: 0xB0602F)

    /// Clay AS text, which needs to work against a light or a dark surface:
    /// 5.19:1 on white, 4.95:1 on a dark card.
    public static func accentText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xD07E4C) : Color(hex: 0xA5591F)
    }

    /// The accent pressed into a smaller space — eyebrows over a tinted card,
    /// where the full-strength clay would vibrate.
    public static let accentDeep = Color(hex: 0xA5591F)

    /// Externally-owned calendar events: present, but never competing for attention.
    public static func externalEvent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x584D40) : Color(hex: 0xA79B89)
    }

    /// Warm-brown rather than neutral black, so shadows sit in the palette.
    public static func shadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.45) : Color(hex: 0x3C2D19).opacity(0.13)
    }

    /// The light edge a neumorphic control catches above it — paired with
    /// `shadow` cast below to read as a disc lifted off the page rather than
    /// a flat fill. Used by the Focus wheel's round controls.
    public static func raisedHighlight(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.85)
    }

    /// The clay-tinted glow under the floating create button — the one shadow
    /// in the chrome that carries the accent colour rather than the warm-brown
    /// neutral, same in both colour schemes.
    public static let accentShadow = accent.opacity(0.4)

    /// Fill for the map's root pill. The root is the one node that is always
    /// the inverse of the surrounding scheme — darker than paper in light
    /// mode, lighter than paper in dark — so the tree's anchor reads as a
    /// fixed point no pastel branch or leaf pill can be mistaken for.
    public static func mapRootFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF3EEE6) : Color(hex: 0x2E2620)
    }

    /// Text sitting on `mapRootFill` — always the opposite of body text,
    /// since the fill itself is always the opposite of the page.
    public static func mapRootText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x1E1913) : Color(hex: 0xF8F4EE)
    }
}

/// Corner radii, 12–40pt by hierarchy.
public enum FlowRadius {
    /// Small icon squircles (library row badges).
    public static let tile: CGFloat = 10
    public static let small: CGFloat = 12
    /// Text fields and the create sheet's CTA — the mock's 14pt shape.
    public static let field: CGFloat = 14
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 22
    /// Modal sheets that float over a dimmed screen.
    public static let sheet: CGFloat = 24
    /// The deep bottom corners of a sheet that reaches the edge of the screen —
    /// paired with `large` at the top, which is what gives the focus card its
    /// hand-held shape rather than a plain rectangle.
    public static let deep: CGFloat = 40
    public static let pill: CGFloat = 999
    /// The floating tab bar's outer radius — rounder than a card, short of a pill.
    public static let chrome: CGFloat = 32
}

/// Circular control diameters. Four sizes, each with a job: utility, secondary
/// action, creation, and the one control a screen is built around.
public enum FlowControlSize {
    /// Menus, toggles, small utilities.
    public static let utility: CGFloat = 38
    /// Skip and complete beside a primary control.
    public static let secondary: CGFloat = 42
    /// The floating create button.
    public static let create: CGFloat = 48
    /// The main timer control.
    public static let hero: CGFloat = 54
}

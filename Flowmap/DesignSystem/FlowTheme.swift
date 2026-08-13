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
        case .clay: Color(hex: 0xC25518)
        case .violet: Color(hex: 0x6242B8)
        case .green: Color(hex: 0x3F8A45)
        case .peach: Color(hex: 0xC96C10)
        case .blue: Color(hex: 0x2E6FB8)
        case .yellow: Color(hex: 0xA8790A)
        case .pink: Color(hex: 0xC03A6B)
        case .teal: Color(hex: 0x11857A)
        case .lavender: Color(hex: 0x7A50CC)
        }
    }

    /// Fill for blocks and wheel segments. These are solid rather than a single
    /// shared opacity over the background: one flat `base.opacity(0.20)` put every
    /// hue at roughly the same lightness, so six wedges read as one soft band
    /// instead of six distinct things. Each hue now carries its own value, spread
    /// deliberately across the range (violet darkest, yellow lightest) so the ring
    /// is told apart by lightness as well as by hue — which is also what a
    /// colour-blind reader needs.
    ///
    /// Branches on the theme's `nodeStyle`: `.vivid` keeps this saturated set,
    /// `.pastel` swaps in `pastelFill` so Minimal and the other light themes read
    /// as MindNode-style desaturated nodes instead of staying saturated regardless
    /// of theme.
    @MainActor public var soft: Color {
        FlowTheme.palette.nodeStyle == .pastel ? pastelFill : vividFill
    }

    /// Today's original saturated fills, kept verbatim as the `.vivid` set.
    private var vividFill: Color {
        switch self {
        case .clay: Color(hex: 0xB84E18)
        case .violet: Color(hex: 0x6B4BC4)
        case .green: Color(hex: 0x5FA463)
        case .peach: Color(hex: 0xE8823A)
        case .blue: Color(hex: 0x2F6AAF)
        case .yellow: Color(hex: 0xF0C24A)
        case .pink: Color(hex: 0xBE3A68)
        case .teal: Color(hex: 0x2E9E92)
        case .lavender: Color(hex: 0x9B7BE0)
        }
    }

    /// MindNode-style desaturated pastels, sampled from the founder's live
    /// MindNode app, for themes whose `nodeStyle` is `.pastel`.
    private var pastelFill: Color {
        switch self {
        case .clay: Color(hex: 0xDC956A)
        case .violet: Color(hex: 0xB5B3D3)
        case .green: Color(hex: 0xA8CBA0)
        case .peach: Color(hex: 0xE8C39A)
        case .blue: Color(hex: 0xA3C1DE)
        case .yellow: Color(hex: 0xEBD79A)
        case .pink: Color(hex: 0xE5B9D0)
        case .teal: Color(hex: 0x80BDC3)
        case .lavender: Color(hex: 0xC9C2E8)
        }
    }

    /// Slightly stronger fill for the active or selected state.
    @MainActor public var softStrong: Color { soft.opacity(0.82) }

    /// Legible on top of `soft`: ink on the light fills, white on the dark ones.
    /// Every pair measured at 4.5:1 or better — the previous `base` on
    /// `base.opacity(0.20)` cleared it on none of them (green 2.8:1, peach 2.5:1).
    ///
    /// Every pastel fill is light, so `.pastel` themes return `inkOnColour` for
    /// all nine tokens rather than switching per hue.
    @MainActor public var onSoft: Color {
        guard FlowTheme.palette.nodeStyle == .vivid else { return FlowTheme.inkOnColour }
        switch self {
        case .yellow, .peach, .green, .teal, .lavender: return FlowTheme.inkOnColour
        case .clay, .violet, .blue, .pink: return .white
        }
    }

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
        // Swift's `hashValue` is deliberately randomised for each process, so
        // it cannot back a persisted visual identity. This small FNV-1a pass
        // over the UUID bytes is stable across launches and devices.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in uuid.uuidString.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return all[Int(hash % UInt64(all.count))]
    }
}

/// Surfaces, separators and accents. Warm cream in light, warm near-black in dark —
/// the palette is built from browns rather than greys so nothing in the app reads
/// cold next to the clay accent.
public enum FlowTheme {
    /// The palette the user picked. Set once on change from `AppSettings.themeRaw`;
    /// the root view re-identifies on the raw value so the change repaints
    /// immediately.
    @MainActor public static var palette: FlowPalette = .default

    @MainActor public static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: palette.bgDark) : Color(hex: palette.bgLight)
    }

    /// Cards and raised rows.
    @MainActor public static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: palette.surfaceDark) : Color(hex: palette.surfaceLight)
    }

    /// Sunken wells: timeline gutters, empty slots, secondary containers.
    @MainActor public static func surfaceSunken(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: palette.sunkenDark) : Color(hex: palette.sunkenLight)
    }

    /// One step deeper than `surfaceSunken`: fixed blocks, inactive segments.
    @MainActor public static func surfaceWell(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: palette.wellDark) : Color(hex: palette.wellLight)
    }

    /// Translucent layer for controls that float over content — the tab bar,
    /// the wheel's view chips, the map's control strip.
    public static func glass(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x2E2721).opacity(0.62) : Color.white.opacity(0.62)
    }

    /// The one-pixel highlight that makes a glass surface read as glass.
    public static func glassBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.70)
    }

    /// Floating popovers such as the list ellipsis menu, dark in both schemes.
    public static let popoverSurface = Color(hex: 0x2E2620)

    /// Text and icons sitting on a saturated task colour. Fixed in both schemes,
    /// because the fill it sits on is the same colour in both — a scheme-aware
    /// ink would flip to white on a light fill and fail contrast.
    public static let inkOnColour = Color(hex: 0x2E2418)

    public static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x3A322A) : Color(hex: 0xECE8E1)
    }

    /// Load-bearing lines: control borders, dividers that must be seen.
    public static func separatorStrong(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x4E4438) : Color(hex: 0xD9D2C8)
    }

    public static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF3EEE6) : Color(hex: 0x2E2418)
    }

    /// Deepened from the design's `#8A7A66`, which measures 4.15:1 on white and
    /// 3.75:1 on the cream background — under the 4.5:1 the HIG asks for. This
    /// value reads as the same warm grey-brown at 6.38:1 and 5.76:1.
    public static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xC6BAA9) : Color(hex: 0x625340)
    }

    /// Eyebrow labels and other text that must recede without disappearing.
    ///
    /// The design's `#B3A48F` measures 2.44:1 on white — invisible to anyone with
    /// reduced contrast sensitivity, and eyebrows carry real information here.
    /// Deepened to 5.38:1 on white, 4.86:1 on cream; dark side lifted from
    /// 4.13:1 to 4.85:1 on a card.
    public static func tertiaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x9C8F7C) : Color(hex: 0x6A5B45)
    }

    /// Clay. The single accent for fills, live timers, progress and graphics.
    @MainActor public static var accent: Color { Color(hex: palette.accent) }

    /// Clay behind white text. The accent itself carries white at only 3.66:1,
    /// so every filled button, chip and pill uses this instead — 4.61:1, and the
    /// two read as the same colour side by side.
    @MainActor public static var accentFill: Color { Color(hex: palette.accentFill) }

    /// Clay AS text, which needs to work against a light or a dark surface:
    /// 5.19:1 on white, 4.95:1 on a dark card.
    @MainActor public static func accentText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: palette.accentTextDark) : Color(hex: palette.accentTextLight)
    }

    /// Delete. A deeper, redder clay so a destructive action reads as its own
    /// thing beside the accent rather than as more of the same.
    public static let destructive = Color(hex: 0xC03A22)

    /// The accent pressed into a smaller space — eyebrows over a tinted card,
    /// where the full-strength clay would vibrate.
    @MainActor public static var accentDeep: Color { Color(hex: palette.accentDeep) }

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
    @MainActor public static var accentShadow: Color { accent.opacity(0.4) }

    /// Medal colours for the prioritise duel reveal's top three. Fixed across
    /// both colour schemes, like `accent` — a medal has to read as
    /// gold/silver/bronze regardless of theme, not shift with it.
    public static let medalGold = Color(hex: 0xC9A227)
    public static let medalSilver = Color(hex: 0x9AA1A9)
    public static let medalBronze = Color(hex: 0xB08050)

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
        scheme == .dark ? Color(hex: 0x171310) : Color(hex: 0xF8F4EE)
    }

    /// The focus wheel ruler's major ticks — bronze/tan, fixed across both
    /// schemes so the scale reads the same regardless of which task's wedge
    /// it sits on (Task 56: the ruler no longer floods with the task colour).
    /// Verified legible on dark in `verification/11-focus-dark.png`.
    public static func rulerTickMajor(_ scheme: ColorScheme) -> Color {
        Color(hex: 0xB98A5C)
    }

    /// The ruler's minor and medium ticks — a paler tan than `rulerTickMajor`,
    /// fixed across both schemes for the same reason.
    public static func rulerTickMinor(_ scheme: ColorScheme) -> Color {
        Color(hex: 0xD6C4AC)
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
    /// The detached capture control, matched to the floating tab bar height.
    public static let create: CGFloat = 56
    /// The main timer control.
    public static let hero: CGFloat = 54
}

/// Artwork sizes shared by navigation and library chrome. Keeping the glyph
/// separate from its hit frame lets the rows remain comfortably tappable while
/// the symbol itself is large enough to scan at a glance.
public enum FlowIconSize {
    public static let navigation: CGFloat = 18
}

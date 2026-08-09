import SwiftUI

/// Which typeface the whole app renders in. Persisted by `AppSettings`
/// (`appFontRaw`); defined here rather than in `SupportingEnums.swift` because
/// the watch targets compile this file standalone, and the watch stays on the
/// system face regardless.
public enum AppFontChoice: String, Codable, CaseIterable, Sendable {
    case system
    case quattro

    public var displayName: String {
        switch self {
        case .system: "System"
        case .quattro: "iA Writer"
        }
    }
}

/// SF Pro by default; iA Writer Quattro when the Settings option is flipped.
/// Dynamic Type is preserved by building on the semantic text styles (system)
/// or by anchoring the same default point size with `relativeTo:` (custom).
public enum FlowFont {
    /// Set from `AppSettings` at launch and by the Settings picker. A plain
    /// static rather than environment state so the tokens below stay callable
    /// from anywhere; the app root rebuilds the shell when it changes.
    /// Only ever written on the main thread — at launch by `AppEnvironment`
    /// and from the Settings picker — so the unsafe opt-out is sound.
    nonisolated(unsafe) public static var choice: AppFontChoice = .system

    /// Quattro ships Regular and Bold static faces only, so every weight
    /// above regular maps onto Bold.
    private static func face(_ weight: Font.Weight) -> String {
        weight == .regular ? "iAWriterQuattroS-Regular" : "iAWriterQuattroS-Bold"
    }

    /// A Dynamic-Type-scaling token. The point size is the style's default,
    /// so the two faces sit at identical sizes and only the face changes.
    private static func scaled(_ style: Font.TextStyle, _ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        switch choice {
        case .system: .system(style, design: .rounded, weight: weight)
        case .quattro: .custom(face(weight), size: size, relativeTo: style)
        }
    }

    /// A fixed-size token — sizes geometry is measured from (map pills, wheel
    /// segments) or chrome that stays constant.
    private static func fixed(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        switch choice {
        case .system: .system(size: size, weight: weight, design: .rounded)
        case .quattro: .custom(face(weight), fixedSize: size)
        }
    }

    public static var screenTitle: Font { scaled(.largeTitle, 34, .bold) }

    /// The quiet centred title the phone screens wear when the content, not the
    /// heading, is meant to hold the eye.
    public static var screenTitleCompact: Font { scaled(.subheadline, 15, .bold) }

    /// Tab bar and other chrome labels.
    public static var chromeLabel: Font { fixed(10, .semibold) }
    public static var sectionTitle: Font { scaled(.headline, 17, .semibold) }
    public static var cardTitle: Font { scaled(.body, 17, .semibold) }
    public static var body: Font { scaled(.body, 17) }
    public static var secondary: Font { scaled(.subheadline, 15) }
    public static var caption: Font { scaled(.caption, 12) }

    /// Compact duration chips such as `30M`. Monospaced digits stop the label
    /// jittering as the number changes.
    public static var durationChip: Font { scaled(.caption2, 11, .bold).monospacedDigit() }

    /// The large focus countdown.
    public static var countdown: Font { fixed(44, .semibold).monospacedDigit() }

    /// The countdown when it sits inside the wheel rather than above a card.
    public static var countdownCompact: Font { fixed(30, .bold).monospacedDigit() }

    /// Small uppercase label above a section or a live value — `NOW`, `TODAY'S
    /// QUEUE`. Always paired with `FlowTheme.tertiaryText` and 1.5pt tracking.
    public static var eyebrow: Font { fixed(11, .heavy) }

    /// The single figure on a statistic tile.
    public static var statNumber: Font { fixed(20, .bold).monospacedDigit() }

    /// Title written inside a wheel segment.
    public static var wheelSegment: Font { fixed(11, .semibold) }

    /// The same title on a wedge too narrow to hold it. Held at 9.5pt: the
    /// design steps a third time down to 8.4, smaller than anything else in
    /// this app and hard to read on a dial that moves — a wedge tighter than
    /// this truncates instead, the way `mapNodeTitleCompact` holds its floor.
    public static var wheelSegmentCompact: Font { fixed(9.5, .semibold) }

    /// The title inside a centred modal dialog — `FlowDialog`'s task/gate title.
    public static var dialogTitle: Font { fixed(21, .heavy) }

    /// A map branch/leaf pill's own title. Fixed rather than Dynamic-Type
    /// scaling, on a par with `eyebrow`/`wheelSegment` — the pill's width is
    /// measured from this exact size, so text and pill can never drift apart.
    public static var mapNodeTitle: Font { fixed(13, .semibold) }

    /// The same pill title when the canvas is in compact mode. Kept at the
    /// 11pt HIG floor rather than following the mock's dynamic-per-zoom scale
    /// all the way down to 9pt.
    public static var mapNodeTitleCompact: Font { fixed(11, .semibold) }

    /// The root pill's title — bold rather than semibold, the one place on
    /// the map where weight signals hierarchy instead of colour.
    public static var mapRootTitle: Font { fixed(13, .bold) }

    /// The "+N" collapsed-children badge beneath a pill. Held at the same
    /// 11pt floor for the same reason as `mapNodeTitleCompact`.
    public static var mapBadge: Font { fixed(11, .bold) }
}

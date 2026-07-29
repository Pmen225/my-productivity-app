import SwiftUI

/// SF Pro throughout. Dynamic Type is preserved by building on the semantic
/// text styles rather than fixed point sizes.
public enum FlowFont {
    public static let screenTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)

    /// The quiet centred title the phone screens wear when the content, not the
    /// heading, is meant to hold the eye.
    public static let screenTitleCompact = Font.system(.subheadline, design: .rounded, weight: .bold)

    /// Tab bar and other chrome labels.
    public static let chromeLabel = Font.system(size: 10, weight: .semibold, design: .rounded)
    public static let sectionTitle = Font.system(.headline, design: .rounded, weight: .semibold)
    public static let cardTitle = Font.system(.body, design: .rounded, weight: .semibold)
    public static let body = Font.system(.body, design: .rounded)
    public static let secondary = Font.system(.subheadline, design: .rounded)
    public static let caption = Font.system(.caption, design: .rounded)

    /// Compact duration chips such as `30M`. Monospaced digits stop the label
    /// jittering as the number changes.
    public static let durationChip = Font.system(.caption2, design: .rounded, weight: .bold)
        .monospacedDigit()

    /// The large focus countdown.
    public static let countdown = Font.system(size: 44, weight: .semibold, design: .rounded)
        .monospacedDigit()

    /// The countdown when it sits inside the wheel rather than above a card.
    public static let countdownCompact = Font.system(size: 30, weight: .bold, design: .rounded)
        .monospacedDigit()

    /// Small uppercase label above a section or a live value — `NOW`, `TODAY'S
    /// QUEUE`. Always paired with `FlowTheme.tertiaryText` and 1.5pt tracking.
    public static let eyebrow = Font.system(size: 11, weight: .heavy, design: .rounded)

    /// The single figure on a statistic tile.
    public static let statNumber = Font.system(size: 20, weight: .bold, design: .rounded)
        .monospacedDigit()

    /// Title written inside a wheel segment.
    public static let wheelSegment = Font.system(size: 11, weight: .semibold, design: .rounded)

    /// The same title on a wedge too narrow to hold it. Held at 9.5pt: the
    /// design steps a third time down to 8.4, smaller than anything else in
    /// this app and hard to read on a dial that moves — a wedge tighter than
    /// this truncates instead, the way `mapNodeTitleCompact` holds its floor.
    public static let wheelSegmentCompact = Font.system(size: 9.5, weight: .semibold, design: .rounded)

    /// The title inside a centred modal dialog — `FlowDialog`'s task/gate title.
    public static let dialogTitle = Font.system(size: 21, weight: .heavy, design: .rounded)

    /// A map branch/leaf pill's own title. Fixed rather than Dynamic-Type
    /// scaling, on a par with `eyebrow`/`wheelSegment` — the pill's width is
    /// measured from this exact size, so text and pill can never drift apart.
    public static let mapNodeTitle = Font.system(size: 13, weight: .semibold, design: .rounded)

    /// The same pill title when the canvas is in compact mode. Kept at the
    /// 11pt HIG floor rather than following the mock's dynamic-per-zoom scale
    /// all the way down to 9pt.
    public static let mapNodeTitleCompact = Font.system(size: 11, weight: .semibold, design: .rounded)

    /// The root pill's title — bold rather than semibold, the one place on
    /// the map where weight signals hierarchy instead of colour.
    public static let mapRootTitle = Font.system(size: 13, weight: .bold, design: .rounded)

    /// The "+N" collapsed-children badge beneath a pill. Held at the same
    /// 11pt floor for the same reason as `mapNodeTitleCompact`.
    public static let mapBadge = Font.system(size: 11, weight: .bold, design: .rounded)
}

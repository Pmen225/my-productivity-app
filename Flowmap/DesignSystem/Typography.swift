import SwiftUI

/// SF Pro throughout. Dynamic Type is preserved by building on the semantic
/// text styles rather than fixed point sizes.
public enum FlowFont {
    public static let screenTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
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

    /// Title written inside a wheel segment.
    public static let wheelSegment = Font.system(size: 11, weight: .semibold, design: .rounded)
}

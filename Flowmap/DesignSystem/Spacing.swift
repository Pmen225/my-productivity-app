import SwiftUI

/// A single spacing scale. Generous by default — breathing room is a product
/// requirement here, not a preference.
public enum FlowSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48

    /// Aligns the detached capture control's centre with the iOS 26 floating
    /// tab pill; the overlay's bottom padding is applied before this offset.
    public static let bottomControlBaselineOffset: CGFloat = 20

    /// Standard screen inset.
    public static let screen: CGFloat = 20

    /// Space the single capture control reserves at the bottom of scrollable
    /// screens, so the last row can move fully above it instead of putting its
    /// trailing value under the orb. Floating tab bars provide a detached
    /// trailing lane; legacy full-width bars need a complete lane above them.
    ///
    /// Shared rather than private to the phone shell: a scroll view nested
    /// inside a paging `TabView` never sees the shell's `.contentMargins`, so it
    /// has to reserve the same room itself.
    public static var floatingControlsInset: CGFloat {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            return FlowControlSize.create + FlowSpacing.l
        }
        return FlowControlSize.create + FlowSpacing.xxxl + FlowSpacing.l
        #else
        return FlowControlSize.create + FlowSpacing.l
        #endif
    }

    /// Minimum gap the focus card must keep from the wheel at rest.
    public static let wheelCardGap: CGFloat = 24
}

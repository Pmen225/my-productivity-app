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

    /// Standard screen inset.
    public static let screen: CGFloat = 20

    /// Space the FAB and the Assistant orb reserve at the bottom of the screens
    /// they float over, so the last row of a list is reachable instead of
    /// sitting under them. The mock leans on an idle-fade for this; a native tab
    /// bar does not fade, so the room is reserved outright — the stack's own
    /// height, plus the gap it is padded off the bottom by, plus a breath so the
    /// last row does not touch the orb.
    ///
    /// Shared rather than private to the phone shell: a scroll view nested
    /// inside a paging `TabView` never sees the shell's `.contentMargins`, so it
    /// has to reserve the same room itself.
    public static let floatingControlsInset =
        FlowControlSize.create + FlowSpacing.m + FlowControlSize.secondary
            + FlowSpacing.xxxl + FlowSpacing.l

    /// Minimum gap the focus card must keep from the wheel at rest.
    public static let wheelCardGap: CGFloat = 24
}

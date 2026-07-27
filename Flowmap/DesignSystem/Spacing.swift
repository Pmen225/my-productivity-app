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

    /// Minimum gap the focus card must keep from the wheel at rest.
    public static let wheelCardGap: CGFloat = 24
}

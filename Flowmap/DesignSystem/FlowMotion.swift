import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The app's whole motion vocabulary. Four curves, nothing else — the
/// founder's cognitive profile calls for gentle, predictable transitions, so
/// no screen should invent its own timing. Values are the ones already used
/// most often across the app (audited in board task 135); callers still
/// decide their own Reduce Motion fallback, usually `reduceMotion ? nil :
/// FlowMotion.x` or `reduceMotion ? FlowMotion.fade : FlowMotion.travel`.
public enum FlowMotion {
    /// Taps, toggles, chip selection — the fastest thing a user should
    /// notice. Matches the `.snappy` used at every plain toggle site.
    public static let tap: Animation = .snappy

    /// Cards expanding, sheets settling, accordions.
    public static let expand: Animation = .spring(response: 0.32, dampingFraction: 0.86)

    /// Anything that moves across the screen (wheel, canvas, page changes).
    public static let travel: Animation = .spring(response: 0.4, dampingFraction: 0.86)

    /// The focus wheel returning from a time-travel peek. This is deliberately
    /// separate from `travel`: a wheel released with momentum must continue
    /// from the finger's velocity, then come home once without the generic
    /// spring's visible wobble.
    public static func wheelSettle(initialVelocity: Double) -> Animation {
        .interpolatingSpring(
            mass: 1,
            stiffness: 190,
            damping: 28,
            initialVelocity: initialVelocity
        )
    }

    /// Content appearing or disappearing.
    public static let fade: Animation = .easeOut(duration: 0.2)
}

/// The app's whole haptic vocabulary. Three feelings, nothing else. `play()`
/// fires unconditionally — callers keep gating on
/// `AppSettings.focusHapticsEnabled` themselves before calling it, exactly as
/// the existing call sites already do; this type does not read settings.
public enum FlowHaptic {
    case light
    case success
    case warning

    public func play() {
        #if os(iOS)
        switch self {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        #endif
    }
}

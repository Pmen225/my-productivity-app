import Foundation

/// The three user-facing reminder styles. The selected style is persisted as a
/// primitive raw value, while the actual device voice is resolved at runtime.
public enum FocusVoiceStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case calm
    case bright
    case deep

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .calm: "Calm"
        case .bright: "Bright"
        case .deep: "Deep"
        }
    }

    /// Speech rate and pitch are deliberately small adjustments: the style
    /// should colour a reminder, not turn it into a character voice.
    public var speechRate: Float {
        switch self {
        case .calm: 0.43
        case .bright: 0.52
        case .deep: 0.39
        }
    }

    public var pitchMultiplier: Float {
        switch self {
        case .calm: 0.96
        case .bright: 1.08
        case .deep: 0.86
        }
    }
}

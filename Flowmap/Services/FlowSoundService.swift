import AudioToolbox
import Foundation

/// The four noises the focus loop makes.
///
/// These play through `AudioServicesPlaySystemSound`, so the app ships no
/// audio of its own: the tones come from the system's own alert set, which
/// means no bundled files, no licensing question, and nothing to keep in sync
/// with the asset catalogue. The trade is that the exact timbre is Apple's
/// choice rather than the mock's — swapping any of these is a one-line change
/// to `systemSoundID` if a variant sounds wrong.
public enum FlowSound: Sendable {
    /// Once a second while a task's clock runs.
    case tick
    /// The task's time ran out.
    case bell
    /// A level boundary was crossed.
    case fanfare
    /// A task was completed.
    case chime

    var systemSoundID: SystemSoundID {
        switch self {
        case .tick: 1104   // Tock — the keyboard's, short enough to repeat
        case .bell: 1005   // Alarm
        case .fanfare: 1025
        case .chime: 1031
        }
    }
}

/// Plays the focus loop's sounds, or stays quiet when the user has asked it to.
///
/// Every caller goes through `play(_:settings:)` rather than reading
/// `focusTickEnabled`/`focusSoundEnabled` itself, so the Settings toggles
/// cannot be honoured on some call sites and forgotten on others.
@MainActor
public struct FlowSoundService {
    public init() {}

    public func play(_ sound: FlowSound, settings: AppSettings) {
        switch sound {
        case .tick:
            guard settings.focusTickEnabled else { return }
        case .bell, .fanfare, .chime:
            guard settings.focusSoundEnabled else { return }
        }
        AudioServicesPlaySystemSound(sound.systemSoundID)
    }
}

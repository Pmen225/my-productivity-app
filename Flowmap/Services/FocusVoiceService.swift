import AVFoundation
import Foundation
import Observation

/// Speaks the focus coach's task-start, time-left and wind-down announcements.
///
/// Owns the `AVSpeechSynthesizer` and every word said; `FocusVoiceSchedule`
/// only decides *when* something is due, so the schedule stays testable
/// without a simulator and `FocusEngine` stays free of speech concerns.
/// `AVSpeechSynthesizer` is not `Sendable`, so this stays confined to the
/// main actor rather than reaching for `@unchecked Sendable`.
@MainActor
@Observable
public final class FocusVoiceService {
    private let synthesizer = AVSpeechSynthesizer()
    /// Set once the shared audio session has been configured for `.ambient`
    /// playback, so `speak(_:settings:)` only pays that cost once.
    private var audioSessionConfigured = false
    /// What has already been said for each running session, so a pause/resume
    /// or a relaunch mid-session never repeats an announcement.
    private var announcedBySession: [UUID: Set<FocusVoiceMilestone>] = [:]
    /// Shows the same milestone on screen as a banner. The two modalities
    /// share this service because they share the schedule — a second timer
    /// deciding when to show a banner would drift out of step with the voice.
    private let moments: FlowMomentService?
    /// When the unresolved-gate reminder last went out. Exposed for the test
    /// that pins the interval — the speech itself leaves nothing to assert on.
    private(set) var lastGateNagAt: Date?

    public init(moments: FlowMomentService? = nil) {
        self.moments = moments
    }

    /// Every voice this device can speak with, used to resolve the curated
    /// reminder styles. Read live from the system rather than a hard-coded
    /// list, since availability differs by device, language and downloaded
    /// voice packs.
    public static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
    }

    /// Maps a curated style to a currently installed voice in the current
    /// language. Device voice packs differ, so the mapping is deterministic
    /// within the available list and gracefully collapses to the same voice
    /// when only one option is installed.
    public static func voice(for style: FocusVoiceStyle) -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let all = availableVoices()
        let matching = all.filter { $0.language == language }
        let voices = (matching.isEmpty ? all : matching).sorted { $0.name < $1.name }
        guard !voices.isEmpty else { return nil }
        let index: Int
        switch style {
        case .calm: index = 0
        case .bright: index = voices.count / 2
        case .deep: index = voices.count - 1
        }
        return voices[min(index, voices.count - 1)]
    }

    /// Speaks the task-start announcement. Called once, exactly when a fresh
    /// session begins — not on resume, where the caller simply does not call
    /// this again.
    public func announceTaskStart(title: String, settings: AppSettings) {
        guard settings.focusVoiceEnabled else { return }
        speak("Drop what you're doing — \(title) starts now.", settings: settings)
    }

    /// Checks whether the active session has newly crossed a time-left,
    /// countdown or wind-down threshold, and speaks it if so.
    ///
    /// Driven by `FocusEngine`'s existing tick — this never starts a second
    /// timer of its own.
    public func tick(
        sessionID: UUID,
        taskTitle: String,
        duration: TimeInterval,
        elapsed: TimeInterval,
        settings: AppSettings
    ) {
        let due = FocusVoiceSchedule.dueMilestones(duration: duration, elapsed: elapsed)
        guard !due.isEmpty else { return }

        let announced = announcedBySession[sessionID] ?? []
        guard let toSpeak = FocusVoiceSchedule.nextAnnouncement(
            duration: duration, elapsed: elapsed, alreadyAnnounced: announced
        ) else { return }

        // Mark every milestone due right now as announced, not just the one
        // spoken — otherwise an older one skipped this tick (because it was
        // superseded by a fresher one) would resurface stale on the next tick.
        announcedBySession[sessionID] = announced.union(due)
        // The banner is not gated on the voice setting: someone who turned
        // speech off still wants to see the milestone go by.
        moments?.show(banner(for: toSpeak, taskTitle: taskTitle))
        guard settings.focusVoiceEnabled else { return }
        speak(text(for: toSpeak), settings: settings)
    }

    /// Clears this session's history and stops any speech in flight —
    /// called whenever a session ends, so nothing keeps talking afterwards.
    public func sessionEnded(sessionID: UUID) {
        announcedBySession[sessionID] = nil
        synthesizer.stopSpeaking(at: .word)
    }

    /// A settings preview uses the same speech path as a real reminder, so
    /// volume, style, device voice and the silent-switch-aware audio session
    /// cannot drift apart.
    public func preview(settings: AppSettings) {
        speak("You have 30 minutes left.", settings: settings)
    }

    // MARK: - Wording

    private func text(for milestone: FocusVoiceMilestone) -> String {
        switch milestone {
        case .timeLeft(let minutes):
            "\(minutes) minutes left."
        case .countdown(let minutesLeft):
            minutesLeft == 1 ? "1 minute left." : "\(minutesLeft) minutes left."
        case .windDown:
            // The mockup's reflection prompt names the two things to do rather
            // than repeating a countdown the banner already shows.
            "Wind down. Note what you learned, and set up the next step."
        }
    }

    // MARK: - Gate nag

    /// How long a gate is left sitting before the reminder repeats.
    static let gateNagInterval: TimeInterval = 18

    /// Reminds someone stuck on a clock-in or plan gate that the work is not
    /// lost if they move on.
    ///
    /// The first call only starts the clock — arriving at a dialog and being
    /// talked at immediately would read as nagging rather than reassurance.
    public func nagUnresolvedGate(now: Date, settings: AppSettings) {
        guard let last = lastGateNagAt else {
            lastGateNagAt = now
            return
        }
        guard now.timeIntervalSince(last) >= Self.gateNagInterval else { return }
        lastGateNagAt = now
        moments?.show(
            .notif(
                title: "Still here?",
                subtitle: "You will have another chance to complete the task."
            )
        )
        guard settings.focusVoiceEnabled else { return }
        speak(
            "You will have another chance to complete the task. Move on to the next task.",
            settings: settings
        )
    }

    /// Called when no gate is pending, so the next one starts its own clock.
    public func gateResolved() {
        lastGateNagAt = nil
    }

    /// The same milestone as a banner: how long is left and what the task is,
    /// with wind-down carrying the mockup's reflection prompt as its subtitle.
    private func banner(for milestone: FocusVoiceMilestone, taskTitle: String) -> FlowMoment {
        switch milestone {
        case .timeLeft(let minutes):
            .notif(title: "\(minutes) minutes left — \(taskTitle)", subtitle: "Keep going.")
        case .countdown(let minutesLeft):
            .notif(
                title: minutesLeft == 1
                    ? "1 minute left — \(taskTitle)"
                    : "\(minutesLeft) minutes left — \(taskTitle)",
                subtitle: "Bring it to a close."
            )
        case .windDown(let minutes):
            .notif(
                title: minutes == 1
                    ? "Wind down, 1 minute — \(taskTitle)"
                    : "Wind down, \(minutes) minutes — \(taskTitle)",
                subtitle: "Note what you learned, prep the next step."
            )
        }
    }

    // MARK: - Speaking

    private func speak(_ text: String, settings: AppSettings) {
        configureAudioSessionIfNeeded()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: settings)
        utterance.volume = Float(settings.focusVoiceVolume)
        utterance.rate = settings.focusVoiceStyle.speechRate
        utterance.pitchMultiplier = settings.focusVoiceStyle.pitchMultiplier
        synthesizer.speak(utterance)
    }

    /// `.ambient` respects the silent switch and mixes with other apps' audio
    /// rather than interrupting them — never `.playback`, which would do
    /// neither. A failure here should never crash the focus session, so this
    /// is best-effort.
    private func configureAudioSessionIfNeeded() {
        guard !audioSessionConfigured else { return }
        audioSessionConfigured = true
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        #endif
    }

    /// The user's chosen voice if it is still installed, else the system's
    /// default for the current language — never a hard failure.
    private func voice(for settings: AppSettings) -> AVSpeechSynthesisVoice? {
        if let identifier = settings.focusVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        if let voice = Self.voice(for: settings.focusVoiceStyle) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }
}

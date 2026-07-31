import AVFoundation
import SwiftUI

/// Every audio control in one place. Founder feedback: the ticking could only
/// be turned off by guessing that a toggle labelled plain "Sound" (buried in
/// Focus Wheel) covered it — each control here names the sound it governs.
struct SoundSettingsSection: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context

    var body: some View {
        FlowCard {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                FlowEyebrow("Sounds")

                if let flow {
                    Toggle("Ticking while focusing", isOn: binding(flow, \.focusTickEnabled))

                    VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                        Toggle("Session chimes", isOn: binding(flow, \.focusSoundEnabled))
                        Text("Time-up bell, level-up fanfare and the task-complete chime.")
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    }

                    VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                        Toggle("Voice coach", isOn: binding(flow, \.focusVoiceEnabled))
                        Text("Spoken reminders during focus sessions.")
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    }

                    if flow.settings.focusVoiceEnabled {
                        voicePicker(flow)
                        voiceVolumeRow(flow)
                    }
                }
            }
            .font(FlowFont.body)
            .foregroundStyle(FlowTheme.primaryText(scheme))
            .tint(FlowTheme.accent)
        }
    }

    private func voicePicker(_ flow: AppEnvironment) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Text("Voice").font(FlowFont.secondary).foregroundStyle(FlowTheme.secondaryText(scheme))
            Picker("Voice", selection: Binding(
                get: { flow.settings.focusVoiceIdentifier },
                set: { newValue in
                    flow.settings.focusVoiceIdentifier = newValue
                    save()
                }
            )) {
                Text("System default").tag(String?.none)
                ForEach(voices, id: \.identifier) { voice in
                    Text(voice.name).tag(Optional(voice.identifier))
                }
            }
            .labelsHidden()
        }
    }

    private func voiceVolumeRow(_ flow: AppEnvironment) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Text("Voice volume").font(FlowFont.secondary).foregroundStyle(FlowTheme.secondaryText(scheme))
            Slider(
                value: Binding(
                    get: { flow.settings.focusVoiceVolume },
                    set: { newValue in
                        flow.settings.focusVoiceVolume = newValue
                        save()
                    }
                ),
                in: 0.2...1.0
            )
            .accessibilityValue("\(Int(flow.settings.focusVoiceVolume * 100)) per cent")
        }
    }

    /// Voices in the device's current language first, since a picker full of
    /// every installed language would bury the ones worth choosing between.
    private var voices: [AVSpeechSynthesisVoice] {
        let currentLanguage = AVSpeechSynthesisVoice.currentLanguageCode()
        let all = FocusVoiceService.availableVoices()
        let matching = all.filter { $0.language == currentLanguage }
        return matching.isEmpty ? all : matching
    }

    private func binding(_ flow: AppEnvironment, _ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { flow.settings[keyPath: keyPath] },
            set: { newValue in
                flow.settings[keyPath: keyPath] = newValue
                save()
            }
        )
    }

    private func save() {
        try? context.save()
    }
}

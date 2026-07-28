import AVFoundation
import SwiftUI

/// Focus voice coach settings — task-start, time-left and wind-down
/// announcements. The picker lists whatever voices `AVSpeechSynthesisVoice`
/// actually reports on this device rather than a hard-coded list, since
/// availability differs by device, language and downloaded voice packs.
struct FocusAudioSettingsSection: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context

    var body: some View {
        FlowCard {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                FlowEyebrow("Focus Voice")

                if let flow {
                    Toggle("Voice coach", isOn: binding(flow, \.focusVoiceEnabled))
                    if flow.settings.focusVoiceEnabled {
                        voicePicker(flow)
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

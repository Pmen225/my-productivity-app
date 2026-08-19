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
                    Text("Flowmap stays quiet by default. Turn on only the feedback that helps you focus.")
                        .font(FlowFont.secondary)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))

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
                        voiceStylePicker(flow)
                        voiceVolumeRow(flow)
                    }

                    Text("The bell rings at the wind-down mark (last 5 min of a long task, scaled down for short ones). Reminders scale with the task — a 1H task hears 45, 30 and 15 minutes left, then 5 · 4 · 3 · 2 · 1.")
                        .font(FlowFont.caption)
                        .foregroundStyle(FlowTheme.tertiaryText(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(FlowFont.body)
            .foregroundStyle(FlowTheme.primaryText(scheme))
            .tint(FlowTheme.accent)
        }
    }

    private func voiceStylePicker(_ flow: AppEnvironment) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Text("Reminder voice").font(FlowFont.secondary).foregroundStyle(FlowTheme.secondaryText(scheme))
            Picker("Reminder voice", selection: Binding(
                get: { flow.settings.focusVoiceStyle },
                set: { newValue in
                    flow.settings.focusVoiceStyle = newValue
                    flow.settings.focusVoiceIdentifier = FocusVoiceService.voice(for: newValue)?.identifier
                    save()
                    flow.voiceService.preview(settings: flow.settings)
                }
            )) {
                ForEach(FocusVoiceStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityValue(flow.settings.focusVoiceStyle.displayName)
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

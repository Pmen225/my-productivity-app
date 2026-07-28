import SwiftUI

/// Focus Wheel behaviour. Automatic requeue itself is not a toggle here — it
/// is core, so unfinished work can never silently vanish. The only choice
/// offered is where requeued work goes first.
struct FocusWheelSettingsSection: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FlowCard {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                FlowEyebrow("Focus Wheel")

                if let flow {
                    visibleTasksRow(flow)
                    Toggle("Sound", isOn: binding(flow, \.focusSoundEnabled))
                    Toggle("Haptics", isOn: binding(flow, \.focusHapticsEnabled))
                    Toggle("Automatically start next task", isOn: binding(flow, \.autoStartNextTask))
                    requeueRow(flow)
                    reducedMotionRow
                }
            }
            .font(FlowFont.body)
            .foregroundStyle(FlowTheme.primaryText(scheme))
            .tint(FlowTheme.accent)
        }
    }

    private func visibleTasksRow(_ flow: AppEnvironment) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Text("Visible tasks").font(FlowFont.secondary).foregroundStyle(FlowTheme.secondaryText(scheme))
            Picker("Visible tasks", selection: Binding(
                get: { flow.settings.wheelVisibility },
                set: { newValue in
                    flow.settings.wheelVisibility = newValue
                    save()
                }
            )) {
                ForEach(WheelVisibility.allCases, id: \.self) { visibility in
                    Text(visibility.displayName).tag(visibility)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityValue(flow.settings.wheelVisibility.announcement)
        }
    }

    private func requeueRow(_ flow: AppEnvironment) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
            Toggle("Prefer later today over tomorrow", isOn: binding(flow, \.requeuePrefersLaterToday))
            Text("Unfinished work always gets requeued automatically — this only chooses where it goes first.")
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
        }
    }

    private var reducedMotionRow: some View {
        HStack(spacing: FlowSpacing.s) {
            Text("Reduced motion")
            Spacer(minLength: FlowSpacing.s)
            Text(reduceMotion ? "On" : "Off")
                .foregroundStyle(FlowTheme.secondaryText(scheme))
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Follows the system Reduce Motion setting.")
        .overlay(alignment: .bottom) {
            Text("Follows your system setting — change it in Accessibility settings.")
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .offset(y: FlowSpacing.l)
        }
        .padding(.bottom, FlowSpacing.l)
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

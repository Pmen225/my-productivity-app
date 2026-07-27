import SwiftUI

/// Which local notifications fire, and the permission state behind them.
struct NotificationSettingsSection: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context

    var body: some View {
        FlowCard {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                CompactSectionHeader(title: "Notifications")

                if let flow {
                    permissionRow(flow)
                    Toggle("Five-minute warning", isOn: binding(flow, \.notifyFiveMinuteWarning))
                    Toggle("Task start", isOn: binding(flow, \.notifyTaskStart))
                    Toggle("Task end", isOn: binding(flow, \.notifyTaskEnd))
                    Toggle("Carryover summary", isOn: binding(flow, \.notifyCarryoverSummary))
                }
            }
            .font(FlowFont.body)
            .foregroundStyle(FlowTheme.primaryText(scheme))
        }
    }

    private func permissionRow(_ flow: AppEnvironment) -> some View {
        HStack(spacing: FlowSpacing.s) {
            StatusIndicator(
                token: flow.notificationService.authorisation == .authorised ? .green : .peach,
                symbolName: flow.notificationService.authorisation == .authorised ? "bell.fill" : "bell.slash",
                label: flow.notificationService.authorisation.explanation
            )
            Text(flow.notificationService.authorisation.explanation)
                .font(FlowFont.secondary)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: FlowSpacing.s)
            if flow.notificationService.authorisation == .notDetermined {
                SecondaryActionButton("Enable") {
                    Task { await flow.notificationService.requestAuthorisation() }
                }
            }
        }
        .padding(.bottom, FlowSpacing.xs)
    }

    private func binding(_ flow: AppEnvironment, _ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { flow.settings[keyPath: keyPath] },
            set: { newValue in
                flow.settings[keyPath: keyPath] = newValue
                try? context.save()
            }
        )
    }
}

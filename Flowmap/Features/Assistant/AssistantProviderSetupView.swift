import SwiftData
import SwiftUI

/// Provider, model and API key rows, plus the Connections list — shared by
/// Settings (`AssistantSettingsSection`) and the in-conversation setup sheet
/// opened from the Assistant screen's `⋯` menu (decision 27). Extracted from
/// `AssistantSettingsSection` so both surfaces stay identical instead of
/// drifting into two copies.
///
/// Key values are never read back into this view — only
/// `KeychainService.maskedDescription` is shown, and the entry field is a
/// `SecureField` that always starts empty.
struct AssistantProviderSetupView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context

    /// The mockup's setup pane shows a discrete Connect/Disconnect action;
    /// Settings is a persistent screen with no "connected" moment to
    /// announce or dismiss out of, so it leaves this off.
    var showsConnectAction: Bool = false
    /// Fires once a saved key is confirmed and the provider/model are
    /// current — the setup sheet uses this to dismiss and post the welcome
    /// message onto the active thread.
    var onConnected: ((String) -> Void)? = nil

    @State private var apiKeyInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.l) {
            if let flow {
                providerRow(flow)
                modelRow(flow)
                apiKeyRow(flow)
                if showsConnectAction {
                    connectRow(flow)
                }
                connectionsSection(flow)
            }
        }
    }

    // MARK: - Provider / model / API key (identical to Batch 1's Settings rows)

    private func providerRow(_ flow: AppEnvironment) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            FlowEyebrow("Provider")
            VStack(spacing: FlowSpacing.s) {
                ForEach(AssistantProvider.allCases, id: \.self) { provider in
                    providerOptionRow(provider, flow: flow)
                }
            }
        }
    }

    private func providerOptionRow(_ provider: AssistantProvider, flow: AppEnvironment) -> some View {
        let isSelected = flow.settings.assistantProvider == provider
        return Button {
            flow.settings.assistantProvider = provider
            apiKeyInput = ""
            try? context.save()
        } label: {
            HStack(spacing: FlowSpacing.s) {
                VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                    Text(provider.displayName)
                        .font(FlowFont.cardTitle)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                    if let firstModel = provider.availableModels.first {
                        Text(firstModel)
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                    }
                }
                Spacer(minLength: FlowSpacing.s)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FlowTheme.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, FlowSpacing.m)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                    .fill(isSelected ? FlowTheme.surfaceSunken(scheme) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                    .strokeBorder(isSelected ? FlowTheme.accent : FlowTheme.separator(scheme), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func modelRow(_ flow: AppEnvironment) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Text("Model").font(FlowFont.secondary).foregroundStyle(FlowTheme.secondaryText(scheme))
            Picker("Model", selection: Binding(
                get: { flow.settings.assistantModel },
                set: { newValue in
                    flow.settings.assistantModel = newValue
                    try? context.save()
                }
            )) {
                ForEach(flow.settings.assistantProvider.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .labelsHidden()
        }
    }

    private func apiKeyRow(_ flow: AppEnvironment) -> some View {
        let account = flow.settings.assistantProvider.keychainAccount
        let placeholder = flow.settings.assistantProvider == .anthropic ? "sk-ant-…" : "sk-…"
        return VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Text("API key").font(FlowFont.secondary).foregroundStyle(FlowTheme.secondaryText(scheme))
            Text(KeychainService.maskedDescription(account: account))
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
            HStack(spacing: FlowSpacing.s) {
                SecureField(placeholder, text: $apiKeyInput)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, FlowSpacing.m)
                    .padding(.vertical, FlowSpacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                            .fill(FlowTheme.surfaceSunken(scheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: FlowRadius.small, style: .continuous)
                            .strokeBorder(FlowTheme.separatorStrong(scheme), lineWidth: 1)
                    )
                SecondaryActionButton("Save") {
                    KeychainService.set(apiKeyInput, account: account)
                    apiKeyInput = ""
                }
                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if KeychainService.hasKey(account: account) {
                    SecondaryActionButton("Remove") {
                        KeychainService.delete(account: account)
                        apiKeyInput = ""
                    }
                }
            }
            Text("Stored in the iOS Keychain — never in iCloud, never in logs. Only messages you send reach the provider.")
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
        }
    }

    /// The mockup's discrete "Connect" CTA: disabled until a key is on file
    /// for the selected provider — no toggle that does nothing. Tapping it
    /// hands the current model to the caller, which dismisses and posts the
    /// welcome message. "Disconnect" only appears once a key exists, and
    /// maps to the same removal the API key row's "Remove" already does.
    private func connectRow(_ flow: AppEnvironment) -> some View {
        let account = flow.settings.assistantProvider.keychainAccount
        let isConnected = KeychainService.hasKey(account: account)
        return VStack(spacing: FlowSpacing.s) {
            PrimaryActionButton("Connect") {
                onConnected?(flow.settings.assistantModel)
            }
            .disabled(!isConnected)
            if isConnected {
                SecondaryActionButton("Disconnect") {
                    KeychainService.delete(account: account)
                }
            }
        }
    }

    // MARK: - Connections (decision 25: Calendar live, the rest coming soon)

    private func connectionsSection(_ flow: AppEnvironment) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow("Connections")
            VStack(spacing: FlowSpacing.s) {
                calendarConnectionRow(flow)
                comingSoonRow(title: "Web search")
                comingSoonRow(title: "Notion")
                comingSoonRow(title: "Files & Drive")
            }
            Text("Connections let the assistant search the web, read and write Notion pages, and see your calendar — Calendar is live today; the rest are coming soon.")
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
        }
    }

    /// Reuses `CalendarHub`'s existing connect/disconnect path (the same one
    /// `CalendarSettingsSection` drives) — no new permission plumbing.
    private func calendarConnectionRow(_ flow: AppEnvironment) -> some View {
        let isConnected = flow.calendarHub.connection(for: .apple)?.isConnected ?? false
        return HStack(spacing: FlowSpacing.s) {
            VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                Text("Calendar")
                    .font(FlowFont.cardTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                Text(isConnected ? "Connected" : "Not connected")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }
            Spacer(minLength: FlowSpacing.s)
            Toggle("Calendar connection", isOn: Binding(
                get: { isConnected },
                set: { toggleCalendar($0, flow: flow) }
            ))
            .labelsHidden()
        }
        .padding(.horizontal, FlowSpacing.m)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .fill(FlowTheme.surfaceSunken(scheme))
        )
    }

    private func toggleCalendar(_ enabled: Bool, flow: AppEnvironment) {
        if enabled {
            Task {
                let success = await flow.calendarHub.connect(.apple)
                guard success else { return }
                try? context.save()
                flow.refreshCalendarWindow(around: flow.now)
            }
        } else {
            flow.calendarHub.disconnect(.apple)
            try? context.save()
        }
    }

    /// HIG: unavailable items stay visible but dimmed, and never rely on
    /// colour alone — the "Coming soon" caption carries the state in text,
    /// not just a faded toggle.
    private func comingSoonRow(title: String) -> some View {
        HStack(spacing: FlowSpacing.s) {
            Text(title)
                .font(FlowFont.cardTitle)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
            Spacer(minLength: FlowSpacing.s)
            Text("Coming soon")
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
            Toggle("", isOn: .constant(false))
                .labelsHidden()
                .disabled(true)
        }
        .padding(.horizontal, FlowSpacing.m)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .fill(FlowTheme.surfaceSunken(scheme).opacity(0.5))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), coming soon")
    }
}

/// The in-conversation setup sheet (decision 27), opened from the Assistant
/// screen's `⋯` menu and from the disconnected status pill. Roots in a
/// `ScrollView` — the Connections section makes this pane's height data-
/// dependent, and a fixed-height sheet with a growing list is the exact
/// trap `FlowCreateSheet` already hit once.
struct AssistantProviderSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let onConnected: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                AssistantProviderSetupView(showsConnectAction: true, onConnected: { model in
                    dismiss()
                    onConnected(model)
                })
                .padding(FlowSpacing.screen)
            }
            .background(FlowTheme.background(scheme))
            .navigationTitle("Provider & API Key")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

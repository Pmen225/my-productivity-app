import SwiftData
import SwiftUI

/// Provider, model, API key management and clearing assistant history.
///
/// Key values are never read back into this view — only
/// `KeychainService.maskedDescription` is shown, and the entry field is a
/// `SecureField` that always starts empty.
struct AssistantSettingsSection: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context

    @Query private var threads: [AssistantThread]

    @State private var apiKeyInput: String = ""
    @State private var showingClearHistoryConfirm = false

    var body: some View {
        FlowCard {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                FlowEyebrow("Assistant")

                if let flow {
                    providerRow(flow)
                    modelRow(flow)
                    apiKeyRow(flow)
                    clearHistoryRow
                }
            }
        }
        .confirmationDialog(
            "Clear assistant history?",
            isPresented: $showingClearHistoryConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive, action: clearHistory)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every conversation. It cannot be undone.")
        }
    }

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

    private var clearHistoryRow: some View {
        HStack {
            Text("\(threads.count) conversation\(threads.count == 1 ? "" : "s") stored")
                .font(FlowFont.secondary)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
            Spacer(minLength: FlowSpacing.s)
            SecondaryActionButton("Clear History", systemImage: "trash") {
                showingClearHistoryConfirm = true
            }
        }
        .disabled(threads.isEmpty)
    }

    private func clearHistory() {
        for thread in threads { context.delete(thread) }
        try? context.save()
    }
}

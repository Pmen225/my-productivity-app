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

    @State private var showingClearHistoryConfirm = false

    var body: some View {
        FlowCard {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                FlowEyebrow("Assistant")

                if flow != nil {
                    AssistantProviderSetupView()
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

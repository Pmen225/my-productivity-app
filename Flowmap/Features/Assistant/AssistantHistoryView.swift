import SwiftData
import SwiftUI

/// Conversation history: switch threads, start a new one, or rename/archive/
/// delete an old one.
struct AssistantHistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let threads: [AssistantThread]
    let activeThreadID: UUID?
    let onSelect: (AssistantThread) -> Void
    let onNew: () -> Void

    @State private var renamingThread: AssistantThread?
    @State private var renameText = ""

    private var activeThreads: [AssistantThread] { threads.filter { !$0.isArchived } }
    private var archivedThreads: [AssistantThread] { threads.filter { $0.isArchived } }

    var body: some View {
        NavigationStack {
            List {
                if activeThreads.isEmpty && archivedThreads.isEmpty {
                    FlowEmptyState(symbol: "bubble.left.and.bubble.right", title: "No conversations yet", message: "Start one below.")
                }
                if !activeThreads.isEmpty {
                    Section {
                        ForEach(activeThreads) { row(for: $0) }
                    } header: {
                        FlowEyebrow("Conversations")
                    }
                }
                if !archivedThreads.isEmpty {
                    Section {
                        ForEach(archivedThreads) { row(for: $0) }
                    } header: {
                        FlowEyebrow("Archived")
                    }
                }
            }
            .navigationTitle("History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New", action: onNew)
                }
            }
            .alert("Rename conversation", isPresented: renameBinding) {
                TextField("Title", text: $renameText)
                Button("Save", action: commitRename)
                Button("Cancel", role: .cancel) { renamingThread = nil }
            }
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renamingThread != nil }, set: { if !$0 { renamingThread = nil } })
    }

    @ViewBuilder
    private func row(for thread: AssistantThread) -> some View {
        Button {
            onSelect(thread)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                    Text(thread.title)
                        .font(FlowFont.cardTitle)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                    if !thread.lastMessagePreview.isEmpty {
                        Text(thread.lastMessagePreview)
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                            .lineLimit(1)
                    }
                }
                Spacer()
                if thread.id == activeThreadID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(FlowTheme.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(thread) } label: { Label("Delete", systemImage: "trash") }
            Button { archive(thread) } label: { Label(thread.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") }
                .tint(.orange)
            Button { beginRename(thread) } label: { Label("Rename", systemImage: "pencil") }
                .tint(.blue)
        }
    }

    private func beginRename(_ thread: AssistantThread) {
        renameText = thread.title
        renamingThread = thread
    }

    private func commitRename() {
        guard let thread = renamingThread else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { thread.title = trimmed }
        thread.touch()
        try? context.save()
        renamingThread = nil
    }

    private func archive(_ thread: AssistantThread) {
        thread.isArchived.toggle()
        thread.touch()
        try? context.save()
    }

    private func delete(_ thread: AssistantThread) {
        context.delete(thread)
        try? context.save()
    }
}

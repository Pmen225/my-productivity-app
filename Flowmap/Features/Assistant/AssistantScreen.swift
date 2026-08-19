import SwiftData
import SwiftUI

/// Entry point for the Assistant tab: the active conversation, plus history,
/// new-conversation and rename/archive/delete affordances.
public struct AssistantScreen: View {
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AssistantThread.updatedAt, order: .reverse) private var threads: [AssistantThread]

    @State private var activeThread: AssistantThread?
    @State private var showHistory = false
    @State private var showingSetup = false
    private let initialThreadID: UUID?

    public init(initialThreadID: UUID? = nil) {
        self.initialThreadID = initialThreadID
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let flow, let activeThread {
                    AssistantConversationView(
                        thread: activeThread,
                        flow: flow,
                        onConnectTapped: { showingSetup = true }
                    )
                    .id(activeThread.id)
                    .accessibilityIdentifier("assistant-thread-\(activeThread.id.uuidString)")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Assistant")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingSetup = true
                        } label: {
                            Label("Provider & API Key…", systemImage: "gearshape")
                        }
                        Button {
                            showHistory = true
                        } label: {
                            Label("Chat History", systemImage: "clock.arrow.circlepath")
                        }
                        Button {
                            activeThread = makeThread()
                        } label: {
                            Label("New Chat", systemImage: "square.and.pencil")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More options")
                }
            }
        }
        .sheet(isPresented: $showHistory) {
            AssistantHistoryView(
                threads: threads,
                activeThreadID: activeThread?.id,
                onSelect: { thread in
                    activeThread = thread
                    showHistory = false
                },
                onNew: {
                    activeThread = makeThread()
                    showHistory = false
                }
            )
        }
        .sheet(isPresented: $showingSetup) {
            AssistantProviderSetupSheet(onConnected: postConnectedMessage)
        }
        .onAppear {
            guard activeThread == nil else { return }
            activeThread = initialThreadID
                .flatMap { id in threads.first(where: { $0.id == id && !$0.isArchived }) }
                ?? threads.first(where: { !$0.isArchived })
                ?? makeThread()
        }
    }

    /// Posts the mockup's welcome message onto the active thread once
    /// `AssistantProviderSetupSheet` confirms a key is saved and the setup
    /// sheet has dismissed itself.
    private func postConnectedMessage(model: String) {
        guard let activeThread else { return }
        let message = AssistantMessage(
            role: .assistant,
            text: "Connected to \(model). Full conversation enabled — ask me anything about your plan.",
            thread: activeThread
        )
        context.insert(message)
        activeThread.touch()
        try? context.save()
    }

    @discardableResult
    private func makeThread() -> AssistantThread {
        let thread = AssistantThread()
        context.insert(thread)
        try? context.save()
        return thread
    }
}

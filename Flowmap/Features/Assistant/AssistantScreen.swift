import SwiftData
import SwiftUI

/// Entry point for the Assistant tab: the active conversation, plus history,
/// new-conversation and rename/archive/delete affordances.
public struct AssistantScreen: View {
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Query(sort: \AssistantThread.updatedAt, order: .reverse) private var threads: [AssistantThread]

    @State private var activeThread: AssistantThread?
    @State private var showHistory = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if let flow, let activeThread {
                    AssistantConversationView(thread: activeThread, flow: flow)
                        .id(activeThread.id)
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
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Conversation history")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        activeThread = makeThread()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New conversation")
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
        .onAppear {
            guard activeThread == nil else { return }
            activeThread = threads.first(where: { !$0.isArchived }) ?? makeThread()
        }
    }

    @discardableResult
    private func makeThread() -> AssistantThread {
        let thread = AssistantThread()
        context.insert(thread)
        try? context.save()
        return thread
    }
}

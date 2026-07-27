import SwiftData
import SwiftUI

/// Reached from the ellipsis menu's `Edit lists` row. Rename, recolour,
/// reorder or delete any user-created list. System smart views (Inbox,
/// Today, Upcoming…) are queries, not rows here — there is nothing to edit.
public struct EditListsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @State private var pendingDelete: TaskList?

    public init() {}

    private var userLists: [TaskList] {
        lists.filter { !$0.isSystemList }
    }

    public var body: some View {
        NavigationStack {
            List {
                if userLists.isEmpty {
                    FlowEmptyState(
                        symbol: "list.bullet",
                        title: "No lists yet",
                        message: "Create a list from the ellipsis menu on any to-do screen."
                    )
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(userLists) { list in
                        EditListRow(list: list)
                    }
                    .onMove(perform: move)
                    .onDelete { offsets in
                        for index in offsets { pendingDelete = userLists[index] }
                    }
                }
            }
            .navigationTitle("Edit Lists")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { EditButton() } }
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete this list?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete List", role: .destructive) {
                    if let list = pendingDelete {
                        context.delete(list)
                        try? context.save()
                    }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Tasks inside stay in Flowmap and move to Inbox.")
            }
        }
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        var reordered = userLists
        reordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, list) in reordered.enumerated() { list.sortOrder = index }
        try? context.save()
    }
}

/// One editable row: inline rename plus a colour swatch.
private struct EditListRow: View {
    @Bindable var list: TaskList

    var body: some View {
        HStack(spacing: FlowSpacing.m) {
            Circle()
                .fill(list.colour.base)
                .frame(width: 10, height: 10)
            Image(systemName: list.iconName)
                .foregroundStyle(list.colour.onSoft)
                .frame(width: 20)
            TextField("List name", text: $list.name)
                .onSubmit { list.touch() }
        }
    }
}

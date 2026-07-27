import SwiftData
import SwiftUI

/// The block editor for one note.
///
/// Typing writes straight into SwiftData objects (instant, in-memory), but the
/// disk/CloudKit `save()` is debounced so fast typing doesn't hammer the store.
struct NoteEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Bindable var note: Note

    @FocusState private var focusedBlockID: UUID?
    @State private var slashMenuBlockID: UUID?
    @State private var saveTask: Task<Void, Never>?
    @State private var isShowingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleField
            Divider().overlay(FlowTheme.separator(scheme))
            blockList
        }
        .background(FlowTheme.background(scheme))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: note.markdown(), preview: SharePreview(note.title.isEmpty ? "Note" : note.title)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export as Markdown")
            }
            #if os(iOS)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingDetails = true
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .accessibilityLabel("Note details")
            }
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $isShowingDetails) {
            NavigationStack {
                NoteDetailsPanel(note: note)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { isShowingDetails = false }
                        }
                    }
            }
        }
        #endif
        .onDisappear { saveTask?.cancel() }
    }

    // MARK: - Title

    private var titleField: some View {
        TextField("Untitled", text: titleBinding)
            .font(FlowFont.screenTitle)
            .textFieldStyle(.plain)
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.top, FlowSpacing.m)
            .padding(.bottom, FlowSpacing.s)
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { note.title },
            set: { newValue in
                note.title = newValue
                scheduleSave()
            }
        )
    }

    // MARK: - Blocks

    private var blockList: some View {
        List {
            ForEach(Array(note.orderedBlocks.enumerated()), id: \.element.id) { index, block in
                VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                    NoteBlockRow(
                        block: block,
                        numberInList: numberInList(at: index),
                        focusedBlockID: $focusedBlockID,
                        onTextChanged: scheduleSave,
                        onReturn: { insertBlock(after: block) },
                        onBackspaceOnEmpty: { deleteBlock(block) },
                        onSlashTrigger: { slashMenuBlockID = block.id }
                    )
                    if slashMenuBlockID == block.id {
                        NoteSlashMenu { type in
                            block.type = type
                            slashMenuBlockID = nil
                        }
                    }
                }
                .listRowSeparator(.hidden)
            }
            .onMove(perform: moveBlocks)
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
    }

    /// `1.` for the first of a run of consecutive `.numbered` blocks, `2.` for
    /// the next, and so on — the run resets whenever a different type breaks it.
    private func numberInList(at index: Int) -> Int? {
        let blocks = note.orderedBlocks
        guard blocks[index].type == .numbered else { return nil }
        var count = 1
        var cursor = index - 1
        while cursor >= 0, blocks[cursor].type == .numbered {
            count += 1
            cursor -= 1
        }
        return count
    }

    private func insertBlock(after block: NoteBlock) {
        let blocks = note.orderedBlocks
        let newBlock = NoteBlock(type: .paragraph, sortOrder: block.sortOrder, note: note)
        context.insert(newBlock)
        for existing in blocks where existing.sortOrder > block.sortOrder {
            existing.sortOrder += 1
        }
        newBlock.sortOrder = block.sortOrder + 1
        try? context.save()
        focusedBlockID = newBlock.id
    }

    private func deleteBlock(_ block: NoteBlock) {
        let blocks = note.orderedBlocks
        guard blocks.count > 1, let index = blocks.firstIndex(where: { $0.id == block.id }) else { return }
        let previousID = blocks[safe: index - 1]?.id
        context.delete(block)
        try? context.save()
        focusedBlockID = previousID ?? blocks[safe: index + 1]?.id
    }

    private func moveBlocks(from offsets: IndexSet, to destination: Int) {
        var blocks = note.orderedBlocks
        blocks.move(fromOffsets: offsets, toOffset: destination)
        for (index, block) in blocks.enumerated() { block.sortOrder = index }
        try? context.save()
    }

    private func scheduleSave() {
        note.touch()
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            try? context.save()
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

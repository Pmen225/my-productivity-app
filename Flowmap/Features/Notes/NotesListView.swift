import SwiftData
import SwiftUI

/// Which slice of the notes library is showing.
enum NotesScope: String, CaseIterable, Identifiable {
    case all
    case recent
    case favourites
    case archived
    case trashed

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: "Notes"
        case .recent: "Recent"
        case .favourites: "Favourites"
        case .archived: "Archived"
        case .trashed: "Trash"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: "Create a note to capture a thought, a plan, or anything worth keeping."
        case .recent: "Notes you've touched recently will show up here."
        case .favourites: "Star a note to pin it here."
        case .archived: "Notes you archive appear here, out of the way but never lost."
        case .trashed: "Deleted notes stay here until you empty the trash."
        }
    }
}

/// The notes library: create, rename, favourite, archive, trash and restore,
/// plus the Recent and Favourites slices. The header is always the compact
/// `NOTES (0)` style with a small `+` — never a permanent full-width add row.
struct NotesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]

    @Binding var scope: NotesScope
    let onSelect: (Note) -> Void

    @State private var searchText = ""
    @State private var renamingNote: Note?
    @State private var renameText = ""

    var body: some View {
        List {
            headerSection
            notesSection
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search notes")
        .toolbar { scopeToolbarItem }
        .navigationTitle(scope.displayName)
        .flowScreenTitle(scope.displayName)
        .alert("Rename note", isPresented: renameAlertBinding) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { commitRename() }
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        let canAddNote = scope != .trashed
        let addLabel: String? = canAddNote ? "New note" : nil
        let onAdd: (() -> Void)? = canAddNote ? { createNote() } : nil
        Section {
            CompactSectionHeader(
                title: scope.displayName,
                count: filteredNotes.count,
                addLabel: addLabel,
                onAdd: onAdd
            )
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        if filteredNotes.isEmpty {
            FlowEmptyState(
                symbol: "doc.text",
                title: "No notes",
                message: scope.emptyMessage
            )
            .listRowSeparator(.hidden)
        } else {
            ForEach(filteredNotes) { note in
                noteRow(for: note)
            }
        }
    }

    private func noteRow(for note: Note) -> some View {
        Button { onSelect(note) } label: { NoteRow(note: note) }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .leading) {
                Button {
                    note.isFavourite.toggle()
                    note.touch()
                    try? context.save()
                } label: {
                    Label(
                        note.isFavourite ? "Unfavourite" : "Favourite",
                        systemImage: note.isFavourite ? "star.slash" : "star"
                    )
                }
                .tint(.yellow)
            }
            .swipeActions(edge: .trailing) {
                trailingActions(for: note)
            }
            .contextMenu {
                contextActions(for: note)
            }
    }

    @ToolbarContentBuilder
    private var scopeToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Scope", selection: $scope) {
                    ForEach(NotesScope.allCases) { candidate in
                        Text(candidate.displayName).tag(candidate)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filter notes")
        }
    }

    // MARK: - Row actions

    @ViewBuilder
    private func trailingActions(for note: Note) -> some View {
        if note.isTrashed {
            Button {
                note.isTrashed = false
                note.touch()
                try? context.save()
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.blue)
            Button(role: .destructive) {
                context.delete(note)
                try? context.save()
            } label: {
                Label("Delete Forever", systemImage: "trash")
            }
        } else {
            Button(role: .destructive) {
                note.isTrashed = true
                note.touch()
                try? context.save()
            } label: {
                Label("Trash", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func contextActions(for note: Note) -> some View {
        Button {
            renameText = note.title
            renamingNote = note
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            note.isFavourite.toggle()
            note.touch()
            try? context.save()
        } label: {
            Label(note.isFavourite ? "Unfavourite" : "Favourite", systemImage: note.isFavourite ? "star.slash" : "star")
        }
        if note.isTrashed {
            Button {
                note.isTrashed = false
                note.touch()
                try? context.save()
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
        } else {
            Button {
                note.isArchived.toggle()
                note.touch()
                try? context.save()
            } label: {
                Label(note.isArchived ? "Unarchive" : "Archive", systemImage: note.isArchived ? "tray.and.arrow.up" : "archivebox")
            }
            Button(role: .destructive) {
                note.isTrashed = true
                note.touch()
                try? context.save()
            } label: {
                Label("Trash", systemImage: "trash")
            }
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(get: { renamingNote != nil }, set: { if !$0 { renamingNote = nil } })
    }

    private func commitRename() {
        guard let note = renamingNote else { return }
        note.title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        note.touch()
        try? context.save()
        renamingNote = nil
    }

    // MARK: - Create

    private func createNote() {
        let note = Note(title: "")
        context.insert(note)
        try? context.save()
        onSelect(note)
    }

    // MARK: - Filtering

    private var filteredNotes: [Note] {
        var base: [Note]
        switch scope {
        case .all:
            base = allNotes.filter { !$0.isArchived && !$0.isTrashed }
        case .recent:
            base = Array(allNotes.filter { !$0.isArchived && !$0.isTrashed }.prefix(20))
        case .favourites:
            base = allNotes.filter { $0.isFavourite && !$0.isTrashed }
        case .archived:
            base = allNotes.filter { $0.isArchived && !$0.isTrashed }
        case .trashed:
            base = allNotes.filter { $0.isTrashed }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter { $0.searchableText.localizedCaseInsensitiveContains(query) }
    }
}

/// One row: icon, title, a one-line preview and the favourite star.
private struct NoteRow: View {
    @Environment(\.colorScheme) private var scheme
    let note: Note

    var body: some View {
        HStack(spacing: FlowSpacing.s) {
            Image(systemName: note.iconName)
                .foregroundStyle(note.colour.onSoft)
                .frame(width: 20, height: 20)
                .background(Circle().fill(note.colour.soft))
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(FlowFont.cardTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                    .lineLimit(1)
                if !note.preview.isEmpty {
                    Text(note.preview)
                        .font(FlowFont.caption)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if note.isFavourite {
                Image(systemName: "star.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.yellow)
            }
        }
        .padding(FlowSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .fill(FlowTheme.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .strokeBorder(FlowTheme.separator(scheme), lineWidth: 1)
        )
    }
}

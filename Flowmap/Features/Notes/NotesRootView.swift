import SwiftUI

/// The Notes feature's entry point.
///
/// macOS: a three-column layout (navigation, editor, details + backlinks).
/// iPhone: a full-width list pushing to a full-width editor; details live in
/// a sheet reached from the editor's toolbar.
struct NotesRootView: View {
    @State private var scope: NotesScope = .all
    @State private var selectedNote: Note?

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            NotesListView(scope: $scope) { selectedNote = $0 }
        } content: {
            if let selectedNote {
                NoteEditorView(note: selectedNote)
            } else {
                FlowEmptyState(
                    symbol: "doc.text",
                    title: "No note selected",
                    message: "Choose a note on the left, or create a new one."
                )
            }
        } detail: {
            if let selectedNote {
                NoteDetailsPanel(note: selectedNote)
            } else {
                Color.clear
            }
        }
        #else
        NavigationStack {
            NotesListView(scope: $scope) { selectedNote = $0 }
                .navigationDestination(item: $selectedNote) { note in
                    NoteEditorView(note: note)
                }
        }
        #endif
    }
}

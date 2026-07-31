import SwiftUI

/// Adds the note-specific attachment commands without building a second
/// labelled control row. The notes detail sheet remains the visible Task
/// picker route; this contextual route keeps the Plan accordion scannable.
enum NoteAttachCandidates {
    /// Includes a closed task that is already attached so the picker always
    /// offers a way to detach it.
    static func display(_ candidates: [FlowTask], attached: FlowTask?) -> [FlowTask] {
        guard let attached, !candidates.contains(where: { $0.id == attached.id }) else {
            return candidates
        }
        return [attached] + candidates
    }
}

struct NoteAttachRow<Content: View>: View {
    let note: Note
    let candidates: [FlowTask]
    let onToggle: (FlowTask?) -> Void
    let content: Content
    let onShowPicker: () -> Void

    init(
        note: Note,
        candidates: [FlowTask],
        onToggle: @escaping (FlowTask?) -> Void,
        @ViewBuilder content: () -> Content,
        onShowPicker: @escaping () -> Void
    ) {
        self.note = note
        self.candidates = candidates
        self.onToggle = onToggle
        self.content = content()
        self.onShowPicker = onShowPicker
    }

    /// `candidates` plus the currently attached task if a status change
    /// (e.g. completing it) has since dropped it out of the open-task
    /// filter. Without this, the picker could not offer a closed attached
    /// task for detachment — a dead-affordance bug this repo has shipped
    /// before (see CLAUDE.md's
    /// "dead UI branches are silent"). Exposed so a test can assert the
    /// merge without touching view state.
    private var canChangeAttachment: Bool {
        !candidates.isEmpty
    }

    private var hasAttachmentActions: Bool {
        note.task != nil || canChangeAttachment
    }

    @ViewBuilder
    var body: some View {
        if hasAttachmentActions {
            content
                .contextMenu {
                    if canChangeAttachment {
                        Button(note.task == nil ? "Attach to task…" : "Change task…", systemImage: "link.badge.plus") {
                            onShowPicker()
                        }
                    }
                    if let attached = note.task {
                        Button("Detach from task", systemImage: "link.badge.minus") {
                            onToggle(attached)
                        }
                    }
                }
        } else {
            content
        }
    }
}

/// A plain `.searchable` list in a sheet — `GlobalSearchView` searches the
/// whole app with no candidate-filtering entry point, so it does not fit a
/// picker scoped to one note's open tasks (ruling 6 names this fallback).
struct NoteAttachPickerView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    let candidates: [FlowTask]
    let current: FlowTask?
    let onSelect: (FlowTask?) -> Void

    @State private var query = ""

    private var filtered: [FlowTask] {
        guard !query.isEmpty else { return candidates }
        return candidates.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { task in
                Button {
                    // The caller (`LibraryView.toggleAttach`) applies the
                    // same single-select toggle rule via
                    // `attachToggleResult`; this view only reports the tap.
                    onSelect(task)
                    dismiss()
                } label: {
                    HStack(spacing: FlowSpacing.s) {
                        Circle().fill(task.colour.base).frame(width: 8, height: 8)
                        Text(task.title)
                        Spacer()
                        if task.id == current?.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(FlowTheme.accentText(scheme))
                        }
                    }
                }
                .foregroundStyle(FlowTheme.primaryText(scheme))
            }
            .searchable(text: $query, prompt: "Search tasks")
            .navigationTitle("Attach to task")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

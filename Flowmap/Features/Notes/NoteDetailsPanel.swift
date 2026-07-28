import SwiftData
import SwiftUI

/// The trailing details column on macOS (a sheet on iPhone): where a note
/// lives, what it's linked to, and what links back to it.
struct NoteDetailsPanel: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Bindable var note: Note

    @Query(sort: \Project.sortOrder) private var allProjects: [Project]
    @Query(sort: \FlowTask.sortOrder) private var allTasks: [FlowTask]
    @Query(sort: \MapNode.sortOrder) private var allMapNodes: [MapNode]
    @Query private var allNotes: [Note]

    var body: some View {
        Form {
            Section {
                Picker("Project", selection: projectBinding) {
                    Text("None").tag(Optional<Project>.none)
                    ForEach(allProjects) { project in
                        Text(project.title).tag(Optional(project))
                    }
                }
                Picker("Task", selection: taskBinding) {
                    Text("None").tag(Optional<FlowTask>.none)
                    ForEach(allTasks) { task in
                        Text(task.title).tag(Optional(task))
                    }
                }
                Picker("Idea (Map)", selection: mapNodeBinding) {
                    Text("None").tag(Optional<MapNode>.none)
                    ForEach(allMapNodes) { node in
                        Text(node.title).tag(Optional(node))
                    }
                }
            } header: {
                FlowEyebrow("Links")
            }

            if !backlinkedNotes.isEmpty {
                Section {
                    ForEach(backlinkedNotes) { linked in
                        NavigationLink(value: linked) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(linked.title.isEmpty ? "Untitled" : linked.title)
                                    .font(FlowFont.secondary)
                                Text(backlinkReason(for: linked))
                                    .font(FlowFont.caption)
                                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                            }
                        }
                    }
                } header: {
                    FlowEyebrow("Backlinks")
                }
            }
        }
        .navigationTitle("Details")
        .presentationCornerRadius(FlowRadius.large)
    }

    // MARK: - Bindings

    private var projectBinding: Binding<Project?> {
        Binding(get: { note.project }, set: { note.project = $0; note.touch(); try? context.save() })
    }

    private var taskBinding: Binding<FlowTask?> {
        Binding(get: { note.task }, set: { note.task = $0; note.touch(); try? context.save() })
    }

    private var mapNodeBinding: Binding<MapNode?> {
        Binding(get: { note.mapNode }, set: { note.mapNode = $0; note.touch(); try? context.save() })
    }

    // MARK: - Backlinks

    /// The model has no direct note-to-note link, so "backlinks" surfaces the
    /// other notes sharing this note's linked task, project or map idea —
    /// the closest honest reading of "what connects to this note".
    private var backlinkedNotes: [Note] {
        guard note.task != nil || note.project != nil || note.mapNode != nil else { return [] }
        return allNotes.filter { candidate in
            guard candidate.id != note.id, !candidate.isTrashed else { return false }
            if let task = note.task, candidate.task?.id == task.id { return true }
            if let project = note.project, candidate.project?.id == project.id { return true }
            if let mapNode = note.mapNode, candidate.mapNode?.id == mapNode.id { return true }
            return false
        }
    }

    private func backlinkReason(for other: Note) -> String {
        if let task = note.task, other.task?.id == task.id { return "Shares task \"\(task.title)\"" }
        if let project = note.project, other.project?.id == project.id { return "Shares project \"\(project.title)\"" }
        if let mapNode = note.mapNode, other.mapNode?.id == mapNode.id { return "Shares idea \"\(mapNode.title)\"" }
        return ""
    }
}

import SwiftData
import SwiftUI

/// The Projects library screen. Default state is a compact `PROJECTS (0)`
/// header and a compact `+` — never a permanent full-width "Add a project" row.
public struct ProjectsScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    @State private var isAddingProject = false
    @State private var searchText = ""
    @State private var statusFilter: ProjectStatus?
    @State private var pendingProjectDelete: Project?

    public init() {}

    public var body: some View {
        List {
            Section {
                CompactSectionHeader(
                    title: "Projects",
                    count: filteredProjects.count,
                    addLabel: "Add project",
                    onAdd: { withAnimation(.snappy) { isAddingProject.toggle() } }
                )
                .listRowSeparator(.hidden)

                if isAddingProject {
                    NewProjectView(onFinished: { withAnimation(.snappy) { isAddingProject = false } })
                        .listRowSeparator(.hidden)
                }
            }

            if filteredProjects.isEmpty {
                FlowEmptyState(
                    symbol: "folder",
                    title: "No projects yet",
                    message: "Group related tasks, a map and notes into a project when you need one."
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredProjects) { project in
                    NavigationLink(value: project) {
                        ProjectRow(project: project)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    #if os(iOS)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // Keep the confirmation card alive after the swipe
                        // closes; a destructive role rebuilds this row and
                        // loses the pending state before the card can present.
                        Button {
                            pendingProjectDelete = project
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(FlowTheme.destructive)
                    }
                    #endif
                }
            }
        }
        .navigationTitle("Projects")
        .flowScreenTitle("Projects")
        .searchable(text: $searchText, placement: .automatic, prompt: "Search projects")
        .navigationDestination(for: Project.self) { project in
            ProjectDetailView(project: project)
        }
        .flowDeleteConfirmation(
            isPresented: projectDeleteBinding,
            itemTitle: pendingProjectDelete?.title ?? "",
            hasChildren: !(pendingProjectDelete?.tasks ?? []).isEmpty,
            onDelete: deletePendingProject
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("All statuses") { statusFilter = nil }
                    ForEach(ProjectStatus.allCases, id: \.self) { status in
                        Button(status.displayName) { statusFilter = status }
                    }
                } label: {
                    Image(systemName: statusFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Filter by status")
            }
        }
    }

    private var filteredProjects: [Project] {
        var result = projects
        if let statusFilter {
            result = result.filter { $0.status == statusFilter }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.summary.localizedCaseInsensitiveContains(query)
            }
        }
        return result
    }

    private var projectDeleteBinding: Binding<Bool> {
        Binding(
            get: { pendingProjectDelete != nil },
            set: { if !$0 { pendingProjectDelete = nil } }
        )
    }

    private func deletePendingProject() {
        guard let project = pendingProjectDelete else { return }
        context.delete(project)
        try? context.save()
        pendingProjectDelete = nil
    }
}

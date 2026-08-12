import SwiftData
import SwiftUI

/// The Projects library screen. Default state is a compact `PROJECTS (0)`
/// header and a compact `+` — never a permanent full-width "Add a project" row.
public struct ProjectsScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \Initiative.sortOrder) private var initiatives: [Initiative]

    @State private var isAddingProject = false
    @State private var searchText = ""
    @State private var statusFilter: ProjectStatus?
    @State private var pendingProjectDelete: Project?
    @State private var renamingProject: Project?
    @State private var renameProjectText = ""
    @State private var editingInitiative: Initiative?
    @State private var renamingInitiative: Initiative?
    @State private var renameInitiativeText = ""

    public init() {}

    public var body: some View {
        List {
            initiativesSection

            Section {
                CompactSectionHeader(
                    title: "Projects",
                    count: filteredProjects.count,
                    addLabel: "Add project",
                    onAdd: { withAnimation(FlowMotion.tap) { isAddingProject.toggle() } }
                )
                .listRowSeparator(.hidden)

                if isAddingProject {
                    NewProjectView(onFinished: { withAnimation(FlowMotion.tap) { isAddingProject = false } })
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
                    .contextMenu {
                        Button {
                            renameProjectText = project.title
                            renamingProject = project
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                    }
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
        .alert("Rename project", isPresented: projectRenameBinding) {
            TextField("Title", text: $renameProjectText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { commitProjectRename() }
        }
        .alert("Rename initiative", isPresented: initiativeRenameBinding) {
            TextField("Title", text: $renameInitiativeText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { commitInitiativeRename() }
        }
        .sheet(item: $editingInitiative) { initiative in
            InitiativeEditSheet(initiative: initiative)
        }
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

    // MARK: - Initiatives

    /// Initiatives have no detail screen of their own yet, so this section is
    /// their only home: rename via context menu, full edit via `InitiativeEditSheet`.
    @ViewBuilder
    private var initiativesSection: some View {
        Section {
            CompactSectionHeader(title: "Initiatives", count: initiatives.count)
                .listRowSeparator(.hidden)

            if initiatives.isEmpty {
                FlowEmptyState(
                    symbol: "scope",
                    title: "No initiatives yet",
                    message: "File a project under an initiative to see it here."
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(initiatives) { initiative in
                    Button { editingInitiative = initiative } label: {
                        initiativeRow(initiative)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .contextMenu {
                        Button {
                            renameInitiativeText = initiative.title
                            renamingInitiative = initiative
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button { editingInitiative = initiative } label: {
                            Label("Edit", systemImage: "square.and.pencil")
                        }
                    }
                }
            }
        }
    }

    private func initiativeRow(_ initiative: Initiative) -> some View {
        HStack(spacing: FlowSpacing.m) {
            Image(systemName: initiative.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(initiative.colour.onSoft)
                .frame(width: 36, height: 36)
                .background(Circle().fill(initiative.colour.soft))

            VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                Text(initiative.title)
                    .font(FlowFont.cardTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                Text("\(initiative.orderedProjects.count) project\(initiative.orderedProjects.count == 1 ? "" : "s")")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }

            Spacer(minLength: FlowSpacing.s)
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
        .accessibilityElement(children: .combine)
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

    // MARK: - Rename

    private var projectRenameBinding: Binding<Bool> {
        Binding(get: { renamingProject != nil }, set: { if !$0 { renamingProject = nil } })
    }

    private func commitProjectRename() {
        guard let project = renamingProject else { return }
        let trimmed = renameProjectText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { renamingProject = nil; return }
        project.title = trimmed
        project.touch()
        try? context.save()
        renamingProject = nil
    }

    private var initiativeRenameBinding: Binding<Bool> {
        Binding(get: { renamingInitiative != nil }, set: { if !$0 { renamingInitiative = nil } })
    }

    private func commitInitiativeRename() {
        guard let initiative = renamingInitiative else { return }
        let trimmed = renameInitiativeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { renamingInitiative = nil; return }
        initiative.title = trimmed
        initiative.touch()
        try? context.save()
        renamingInitiative = nil
    }
}

/// Initiatives have no detail screen of their own yet, so this is their only
/// editor: name, summary and colour — the fields the model actually has.
/// Mirrors `ProjectOverviewTab`'s card styling and its live-binding, save-on-
/// dismiss pattern (no separate Save button, like a task's own detail sheet).
struct InitiativeEditSheet: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var initiative: Initiative
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FlowSpacing.l) {
                    FlowCard {
                        VStack(alignment: .leading, spacing: FlowSpacing.m) {
                            FlowEyebrow("Title")
                            TextField("Initiative title", text: $initiative.title)
                                .font(FlowFont.cardTitle)
                                .focused($titleFocused)
                        }
                    }

                    FlowCard {
                        VStack(alignment: .leading, spacing: FlowSpacing.m) {
                            FlowEyebrow("Summary")
                            TextEditor(text: $initiative.summary)
                                .frame(minHeight: 80)
                        }
                    }

                    FlowCard {
                        HStack {
                            FlowEyebrow("Colour")
                            Spacer()
                            FlowColourPicker(selection: Binding(
                                get: { initiative.colour },
                                set: { initiative.colourToken = $0.rawValue }
                            ))
                        }
                    }
                }
                .padding(FlowSpacing.screen)
            }
            .navigationTitle("Edit initiative")
            .flowScreenTitle("Edit initiative")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { titleFocused = true }
        .onDisappear {
            let trimmed = initiative.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { initiative.title = trimmed }
            initiative.touch()
            try? context.save()
        }
    }
}

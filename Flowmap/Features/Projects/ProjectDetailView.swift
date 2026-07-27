import SwiftData
import SwiftUI

/// A project's own screen: overview, its task list, map, notes, timeline and
/// progress. macOS gets a segmented switcher inline; iPhone gets the same
/// switcher at the top of one clean detail screen — the content beneath is
/// what actually differs per platform's List/ScrollView conventions.
public struct ProjectDetailView: View {
    @Bindable private var project: Project
    @State private var selectedTab: ProjectDetailTab = .overview

    public init(project: Project) {
        self._project = Bindable(project)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedTab) {
                ForEach(ProjectDetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.vertical, FlowSpacing.s)

            Divider()

            tabContent
        }
        .navigationTitle(project.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            ScrollView { ProjectOverviewTab(project: project) }
        case .tasks:
            ProjectTasksTab(project: project)
        case .map:
            ScrollView { ProjectMapTab(project: project) }
        case .notes:
            ScrollView { ProjectNotesTab(project: project) }
        }
    }
}

/// The four facets of a project, switched by one segmented control.
public enum ProjectDetailTab: String, CaseIterable, Identifiable {
    case overview
    case tasks
    case map
    case notes

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: return "Overview"
        case .tasks: return "Tasks"
        case .map: return "Map"
        case .notes: return "Notes"
        }
    }
}

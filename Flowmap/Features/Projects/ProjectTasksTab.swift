import SwiftData
import SwiftUI

/// The project's own task list: the same `TaskRowView` and quick-add pattern
/// used everywhere else, scoped to this project instead of a smart view.
public struct ProjectTasksTab: View {
    @Environment(\.modelContext) private var context
    let project: Project

    @State private var isAddingTask = false
    @State private var selectedTask: FlowTask?

    public init(project: Project) {
        self.project = project
    }

    private var tasks: [FlowTask] {
        (project.tasks ?? [])
            .filter { $0.status != .cancelled }
            .sorted { lhs, rhs in
                if lhs.status.isOpen != rhs.status.isOpen { return lhs.status.isOpen }
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
    }

    public var body: some View {
        List {
            Section {
                CompactSectionHeader(
                    title: "Tasks",
                    count: tasks.count,
                    addLabel: "Add task",
                    onAdd: { isAddingTask = true }
                )
                .listRowSeparator(.hidden)
            }

            if tasks.isEmpty {
                FlowEmptyState(
                    symbol: "checklist",
                    title: "No tasks yet",
                    message: "Add the first task for this project."
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(tasks) { task in
                    TaskRowView(task: task)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedTask = task }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
        }
        #if os(iOS)
        .sheet(item: $selectedTask) { task in
            NavigationStack { TaskDetailInspector(task: task) }
        }
        #else
        .inspector(isPresented: Binding(get: { selectedTask != nil }, set: { if !$0 { selectedTask = nil } })) {
            if let selectedTask {
                TaskDetailInspector(task: selectedTask)
            }
        }
        #endif
        .sheet(isPresented: $isAddingTask) {
            QuickCaptureView(initialProjectID: project.id)
        }
    }
}

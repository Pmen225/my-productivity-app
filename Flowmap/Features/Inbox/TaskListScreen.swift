import SwiftData
import SwiftUI

/// Where a `TaskListScreen` gets its tasks from: a query-backed `SmartView`
/// (Inbox, Today, Upcoming…) or a user-created `TaskList`. Both are queries
/// over the one `FlowTask` store — neither duplicates it.
public enum TaskListSource: Hashable {
    case smartView(SmartView)
    case userList(TaskList)

    public var title: String {
        switch self {
        case .smartView(let view): return view.displayName
        case .userList(let list): return list.name
        }
    }

    public var symbolName: String {
        switch self {
        case .smartView(let view): return view.symbolName
        case .userList(let list): return list.iconName
        }
    }

    public var emptyMessage: String {
        switch self {
        case .smartView(let view): return view.emptyMessage
        case .userList: return "Nothing here yet."
        }
    }

    /// Only the Completed view can't sensibly receive new tasks straight in.
    public var allowsQuickAdd: Bool {
        if case .smartView(.completed) = self { return false }
        return true
    }
}

/// Renders any smart view or user list. This is the one task-list screen in
/// the app — Today, Upcoming, Anytime and so on are the same view with a
/// different query, never a separately built container.
public struct TaskListScreen: View {
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: [SortDescriptor(\FlowTask.sortOrder), SortDescriptor(\FlowTask.createdAt)])
    private var allTasks: [FlowTask]

    public let source: TaskListSource

    @State private var isAddingTask = false
    @State private var searchText = ""
    @State private var filterPriority: TaskPriority?
    @State private var showCreateList = false
    @State private var showEditLists = false
    @State private var showDuel = false
    @State private var selectedTask: FlowTask?

    @SmartViewGrouping private var smartGrouping: GroupingMode

    #if os(macOS)
    @State private var macSelection: Set<UUID> = []
    #endif

    public init(source: TaskListSource) {
        self.source = source
        switch source {
        case .smartView(let view):
            _smartGrouping = SmartViewGrouping(view)
        case .userList:
            _smartGrouping = SmartViewGrouping(.inbox)
        }
    }

    public var body: some View {
        content
            .navigationTitle(source.title)
            .flowScreenTitle(source.title)
            .searchable(text: $searchText, placement: .automatic, prompt: "Search tasks")
            .toolbar { toolbarContent }
            .sheet(isPresented: $isAddingTask) {
                QuickCaptureView(
                    initialListID: userListIfAny?.id,
                    flagForTodayIfUndated: smartViewIfAny == .today
                )
            }
            .sheet(isPresented: $showCreateList) { CreateListSheet() }
            .sheet(isPresented: $showEditLists) { EditListsView() }
            #if os(iOS)
            .fullScreenCover(isPresented: $showDuel) { PrioritiseDuelView(tasks: filteredTasks) }
            #else
            .sheet(isPresented: $showDuel) { PrioritiseDuelView(tasks: filteredTasks) }
            #endif
            #if os(iOS)
            .sheet(item: $selectedTask) { task in
                NavigationStack { TaskDetailInspector(task: task) }
            }
            #else
            .inspector(isPresented: singleSelectionInspectorBinding) {
                if let task = singleSelectedTask {
                    TaskDetailInspector(task: task)
                }
            }
            #endif
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        List(selection: $macSelection) {
            headerSection
            taskSections
        }
        .scrollContentBackground(.hidden)
        .background(FlowTheme.background(scheme).ignoresSafeArea())
        #else
        List {
            headerSection
            taskSections
        }
        .scrollContentBackground(.hidden)
        .background(FlowTheme.background(scheme).ignoresSafeArea())
        #endif
    }

    private var headerSection: some View {
        Section {
            if source.allowsQuickAdd {
                CompactSectionHeader(
                    title: source.title,
                    count: filteredTasks.count,
                    addLabel: "Add task",
                    onAdd: { isAddingTask = true }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                // Hosted here rather than on a dedicated "Plan" screen, which
                // this app does not have — the Today listing is where the
                // duel's own set (today's open tasks) already lives. See
                // `PrioritiseDuelView`'s header comment.
                if isDuelAvailable {
                    SecondaryActionButton("Play the prioritise game", systemImage: "trophy") {
                        showDuel = true
                    }
                    .accessibilityLabel("Play the prioritise game")
                    .accessibilityHint("Pick which of two of today's tasks comes first, repeated for every pair, then reorder today by the result")
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            } else {
                CompactSectionHeader(title: source.title, count: filteredTasks.count)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder
    private var taskSections: some View {
        if filteredTasks.isEmpty {
            FlowEmptyState(symbol: source.symbolName, title: source.title, message: source.emptyMessage)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        } else {
            ForEach(groupedSections, id: \.title) { section in
                Section {
                    ForEach(section.tasks) { task in
                        row(for: task)
                    }
                    .onMove(
                        perform: currentGrouping == .manual
                            ? { offsets, destination in move(section.tasks, from: offsets, to: destination) }
                            : nil
                    )
                } header: {
                    if !section.title.isEmpty {
                        FlowEyebrow(section.title)
                    }
                }
            }
        }
    }

    private func row(for task: FlowTask) -> some View {
        TaskRowView(task: task, onEdit: { edit(task) })
            #if os(macOS)
            .tag(task.id)
            #endif
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private func edit(_ task: FlowTask) {
        #if os(macOS)
        macSelection = [task.id]
        #else
        selectedTask = task
        #endif
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
        if !macSelection.isEmpty {
            ToolbarItem { Button("Complete", action: completeSelected) }
            ToolbarItem { Button("Delete", role: .destructive, action: deleteSelected) }
        }
        #endif
        ToolbarItem(placement: .primaryAction) {
            ListEllipsisMenu(
                currentGrouping: currentGrouping,
                onSelectGrouping: setGrouping,
                onCreateList: { showCreateList = true },
                onEditLists: { showEditLists = true },
                filterPriority: filterPriority,
                onSelectFilter: { filterPriority = $0 }
            )
        }
    }

    // MARK: - Filtering

    private var filteredTasks: [FlowTask] {
        var base: [FlowTask]
        switch source {
        case .smartView(let view):
            base = view.matches(allTasks, now: flow?.now ?? Date())
        case .userList(let list):
            base = allTasks.filter { $0.list?.id == list.id && $0.status != .cancelled }
        }
        if let filterPriority {
            base = base.filter { $0.priority == filterPriority }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            base = base.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.details.localizedCaseInsensitiveContains(query)
            }
        }
        return base
    }

    /// `SmartView.sections(_:grouping:)` doesn't depend on which case `self`
    /// is — only on `grouping` — so any instance groups correctly. Using it
    /// here avoids a second copy of that sorting logic.
    private var groupedSections: [(title: String, tasks: [FlowTask])] {
        SmartView.allTasks.sections(filteredTasks, grouping: currentGrouping)
    }

    // MARK: - Grouping persistence

    private var currentGrouping: GroupingMode {
        switch source {
        case .smartView: return smartGrouping
        case .userList(let list): return list.groupingMode
        }
    }

    private func setGrouping(_ mode: GroupingMode) {
        switch source {
        case .smartView: smartGrouping = mode
        case .userList(let list):
            list.groupingMode = mode
            try? context.save()
        }
    }

    // MARK: - Quick add context

    private var smartViewIfAny: SmartView? {
        if case .smartView(let view) = source { return view }
        return nil
    }

    private var userListIfAny: TaskList? {
        if case .userList(let list) = source { return list }
        return nil
    }

    /// The prioritise duel operates on today's set, not the inbox — planning
    /// must not require the game (state/specs/cognitive-profile.md, "product
    /// thesis"); it only orders what's already lined up for today. Upcoming,
    /// Anytime and user lists already have an order the duel would fight, and
    /// it only has something to say once there are at least two tasks.
    private var isDuelAvailable: Bool {
        guard case .smartView(.today) = source else { return false }
        return PrioritiseDuel.isAvailable(for: filteredTasks.map(\.id))
    }

    // MARK: - Manual reorder

    private func move(_ tasks: [FlowTask], from offsets: IndexSet, to destination: Int) {
        var reordered = tasks
        reordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, task) in reordered.enumerated() { task.sortOrder = index }
        try? context.save()
    }

    // MARK: - Mac multi-select

    #if os(macOS)
    private var singleSelectedTask: FlowTask? {
        guard macSelection.count == 1, let id = macSelection.first else { return nil }
        return allTasks.first { $0.id == id }
    }

    private var singleSelectionInspectorBinding: Binding<Bool> {
        Binding(get: { singleSelectedTask != nil }, set: { if !$0 { macSelection = [] } })
    }

    private func completeSelected() {
        withAnimation(FlowMotion.tap) {
            for task in allTasks where macSelection.contains(task.id) {
                task.markCompleted()
            }
            try? context.save()
            macSelection = []
        }
    }

    private func deleteSelected() {
        withAnimation(FlowMotion.tap) {
            for task in allTasks where macSelection.contains(task.id) {
                context.delete(task)
            }
            try? context.save()
            macSelection = []
        }
    }
    #endif
}

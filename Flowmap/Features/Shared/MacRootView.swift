#if os(macOS)
import SwiftData
import SwiftUI

/// Everything the Mac sidebar can select.
enum MacDestination: Hashable, Identifiable {
    case today
    case inbox
    case calendar
    case focus
    case maps
    case projects
    case notes
    case progress
    case assistant
    case settings
    case smartView(SmartView)
    case userList(TaskList)

    var id: String {
        switch self {
        case .smartView(let view): "smart.\(view.rawValue)"
        case .userList(let list): "list.\(list.id.uuidString)"
        default: String(describing: self)
        }
    }

    var title: String {
        switch self {
        case .today: "Today"
        case .inbox: "Inbox"
        case .calendar: "Calendar"
        case .focus: "Focus"
        case .maps: "Maps"
        case .projects: "Projects"
        case .notes: "Notes"
        case .progress: "Progress"
        case .assistant: "Assistant"
        case .settings: "Settings"
        case .smartView(let view): view.displayName
        case .userList(let list): list.name
        }
    }

    var symbolName: String {
        switch self {
        case .today: "sun.max"
        case .inbox: "tray"
        case .calendar: "calendar"
        case .focus: "timer"
        case .maps: "point.topleft.down.to.point.bottomright.curvepath"
        case .projects: "folder"
        case .notes: "doc.text"
        case .progress: "chart.bar"
        case .assistant: "sparkles"
        case .settings: "gearshape"
        case .smartView(let view): view.symbolName
        case .userList(let list): list.iconName
        }
    }
}

/// The Mac shell: a native split view grouped by what the user is doing —
/// planning, building, reviewing, or asking.
struct MacRootView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]

    @State private var selection: MacDestination? = .today
    @State private var showingSearch = false
    @State private var showingCapture = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            NavigationStack {
                detail
            }
        }
        .sheet(isPresented: $showingSearch) {
            GlobalSearchView { result in navigate(to: result) }
        }
        .sheet(isPresented: $showingCapture) {
            QuickCaptureView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .flowmapOpenDeepLink)) { notification in
            guard let request = notification.object as? DeepLinkRequest else { return }
            selection = destination(for: request.destination)
        }
        .onReceive(NotificationCenter.default.publisher(for: .flowmapShowSearch)) { _ in
            showingSearch = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .flowmapQuickCapture)) { _ in
            showingCapture = true
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Plan") {
                row(.today)
                row(.inbox)
                row(.calendar)
                row(.focus)
            }

            Section("Build") {
                row(.maps)
                row(.projects)
                row(.notes)
            }

            Section("Review") {
                row(.progress)
            }

            Section("AI") {
                row(.assistant)
            }

            if !lists.isEmpty {
                Section("Lists") {
                    ForEach(lists) { list in
                        row(.userList(list))
                    }
                }
            }

            Section {
                row(.settings)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 300)
        .toolbar {
            ToolbarItem {
                Button { showingCapture = true } label: { Image(systemName: "plus") }
                    .help("Quick capture (⌘N)")
                    .accessibilityLabel("Quick capture")
            }
        }
    }

    private func row(_ destination: MacDestination) -> some View {
        Label(destination.title, systemImage: destination.symbolName)
            .tag(destination)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .today, .none: TodayView()
        case .inbox: TaskListScreen(source: .smartView(.inbox))
        case .calendar: CalendarRootView()
        case .focus: FocusScreen()
        case .maps: MapListView()
        case .projects: ProjectsScreen()
        case .notes: NotesRootView()
        case .progress: ProgressScreen()
        case .assistant: AssistantScreen()
        case .settings: SettingsScreen()
        case .smartView(let view): TaskListScreen(source: .smartView(view))
        case .userList(let list): TaskListScreen(source: .userList(list))
        }
    }

    // MARK: - Routing

    private func destination(for link: DeepLink) -> MacDestination {
        switch link {
        case .today: .today
        case .focus: .focus
        case .map: .maps
        case .calendar: .calendar
        case .library, .inbox: .inbox
        case .assistant: .assistant
        }
    }

    private func navigate(to result: SearchResult) {
        switch result.kind {
        case .task: selection = .smartView(.allTasks)
        case .project: selection = .projects
        case .mapNode: selection = .maps
        case .note: selection = .notes
        case .assistantThread: selection = .assistant
        }
    }
}
#endif

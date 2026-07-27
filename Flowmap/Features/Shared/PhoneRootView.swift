#if !os(macOS)
import SwiftData
import SwiftUI

/// The iPhone shell: five calm destinations, with the Assistant reachable in one
/// tap from a floating orb rather than eating a sixth tab.
struct PhoneRootView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme

    @State private var tab: DeepLink = .today
    @State private var showingAssistant = false
    @State private var showingSearch = false
    @State private var showingCapture = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $tab) {
                NavigationStack {
                    TodayView()
                }
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(DeepLink.today)

                NavigationStack {
                    MapListView()
                }
                .tabItem {
                    Label("Map", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .tag(DeepLink.map)

                NavigationStack {
                    CalendarRootView()
                }
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(DeepLink.calendar)

                NavigationStack {
                    FocusScreen()
                }
                .tabItem { Label("Focus", systemImage: "timer") }
                .tag(DeepLink.focus)

                NavigationStack {
                    LibraryView(showingAssistant: $showingAssistant)
                }
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(DeepLink.library)
            }

            assistantOrb
        }
        .sheet(isPresented: $showingAssistant) {
            NavigationStack { AssistantScreen() }
        }
        .sheet(isPresented: $showingSearch) {
            GlobalSearchView { result in navigate(to: result) }
        }
        .sheet(isPresented: $showingCapture) {
            QuickCaptureView().presentationDetents([.height(300)])
        }
        .onReceive(NotificationCenter.default.publisher(for: .flowmapOpenDeepLink)) { notification in
            guard let request = notification.object as? DeepLinkRequest else { return }
            switch request.destination {
            case .assistant: showingAssistant = true
            case .inbox: tab = .library
            default: tab = request.destination
            }
        }
    }

    /// Floats above the tab bar. The bottom padding clears both the tab bar and
    /// the home indicator, so it never sits on top of content.
    private var assistantOrb: some View {
        Button {
            showingAssistant = true
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(FlowTheme.accent))
                .shadow(color: FlowTheme.shadow(scheme), radius: 10, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.trailing, FlowSpacing.screen)
        .padding(.bottom, 72)
        .accessibilityLabel("Assistant")
    }

    private func navigate(to result: SearchResult) {
        switch result.kind {
        case .task, .project, .note: tab = .library
        case .mapNode: tab = .map
        case .assistantThread: showingAssistant = true
        }
    }
}

/// Everything that does not earn its own tab.
struct LibraryView: View {
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]

    @Binding var showingAssistant: Bool
    @State private var showingSearch = false
    @State private var showingCapture = false

    var body: some View {
        List {
            Section("Tasks") {
                ForEach(SmartView.allCases) { view in
                    NavigationLink {
                        TaskListScreen(source: .smartView(view))
                    } label: {
                        Label(view.displayName, systemImage: view.symbolName)
                    }
                }
            }

            if !lists.isEmpty {
                Section("Lists") {
                    ForEach(lists) { list in
                        NavigationLink {
                            TaskListScreen(source: .userList(list))
                        } label: {
                            Label(list.name, systemImage: list.iconName)
                        }
                    }
                }
            }

            Section {
                NavigationLink { ProjectsScreen() } label: {
                    Label("Projects", systemImage: "folder")
                }
                NavigationLink { NotesRootView() } label: {
                    Label("Notes", systemImage: "doc.text")
                }
                NavigationLink { ProgressScreen() } label: {
                    Label("Progress", systemImage: "chart.bar")
                }
                Button {
                    showingAssistant = true
                } label: {
                    Label("Assistant", systemImage: "sparkles")
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                }
                NavigationLink { SettingsScreen() } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingSearch = true } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCapture = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Quick capture")
            }
        }
        .sheet(isPresented: $showingSearch) {
            GlobalSearchView { _ in }
        }
        .sheet(isPresented: $showingCapture) {
            QuickCaptureView().presentationDetents([.height(300)])
        }
    }
}
#endif

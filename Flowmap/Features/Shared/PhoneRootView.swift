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

    /// Tab order and icon for the floating tab bar. Labels come from
    /// `DeepLink.title` so the chrome and the deep-link vocabulary never drift.
    private static let tabOrder: [(DeepLink, systemImage: String)] = [
        (.today, "sun.max"),
        (.map, "point.topleft.down.to.point.bottomright.curvepath"),
        (.calendar, "calendar"),
        (.focus, "timer"),
        (.library, "square.stack"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                NavigationStack {
                    TodayView()
                }
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(DeepLink.today)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack {
                    MapListView()
                }
                .tabItem {
                    Label("Map", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .tag(DeepLink.map)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack {
                    CalendarRootView()
                }
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(DeepLink.calendar)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack {
                    FocusScreen()
                }
                .tabItem { Label("Focus", systemImage: "timer") }
                .tag(DeepLink.focus)
                .toolbar(.hidden, for: .tabBar)

                NavigationStack {
                    LibraryView(showingAssistant: $showingAssistant, onSearchResult: navigate(to:))
                }
                .tabItem { Label("Library", systemImage: "square.stack") }
                .tag(DeepLink.library)
                .toolbar(.hidden, for: .tabBar)
            }

            FlowTabBar(
                selection: $tab,
                items: Self.tabOrder.map {
                    FlowTabBarItem(id: $0.0, title: $0.0.title, systemImage: $0.systemImage)
                }
            )
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.bottom, FlowSpacing.xs)
        }
        // Focus fills the space above the tab bar with its own card, so the
        // floating controls would sit on top of it. The Assistant and quick
        // capture stay one tap away from every other destination.
        .overlay(alignment: .bottomTrailing) {
            if tab != .focus {
                VStack(spacing: FlowSpacing.m) {
                    createButton
                    assistantOrb
                }
                .padding(.trailing, FlowSpacing.screen)
                .padding(.bottom, FlowSpacing.xxxl)
            }
        }
        .sheet(isPresented: $showingAssistant) {
            NavigationStack { AssistantScreen() }
        }
        .sheet(isPresented: $showingSearch) {
            GlobalSearchView { result in navigate(to: result) }
        }
        .sheet(isPresented: $showingCapture) {
            QuickCaptureView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(FlowRadius.large)
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

    /// The floating create button — new task, project or initiative — sitting
    /// above the assistant orb, clear of the tab bar.
    private var createButton: some View {
        FlowFloatingButton(
            systemImage: "plus",
            diameter: FlowControlSize.create,
            background: FlowTheme.accent,
            foreground: .white,
            shadowColor: FlowTheme.accentShadow,
            accessibilityLabel: "New task, project or initiative"
        ) {
            showingCapture = true
        }
    }

    /// Floats above the tab bar, below the create button.
    private var assistantOrb: some View {
        FlowFloatingButton(
            systemImage: "sparkles",
            diameter: FlowControlSize.secondary,
            background: FlowTheme.popoverSurface,
            foreground: .white,
            shadowColor: FlowTheme.shadow(scheme),
            accessibilityLabel: "Assistant"
        ) {
            showingAssistant = true
        }
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
    /// Routes a chosen search result, so a Library search behaves like the
    /// shell's own — selecting a result must actually go somewhere.
    let onSearchResult: (SearchResult) -> Void

    @State private var showingSearch = false
    @State private var showingCapture = false

    var body: some View {
        List {
            Section(header: sectionHeader("TASKS")) {
                ForEach(Array(SmartView.allCases.enumerated()), id: \.element) { index, view in
                    NavigationLink {
                        TaskListScreen(source: .smartView(view))
                    } label: {
                        libraryLabel(view.displayName, symbol: view.symbolName, token: Self.rowTokens[index % Self.rowTokens.count])
                    }
                }
            }
            .listRowBackground(FlowTheme.surface(scheme))

            if !lists.isEmpty {
                Section(header: sectionHeader("LISTS")) {
                    ForEach(lists) { list in
                        NavigationLink {
                            TaskListScreen(source: .userList(list))
                        } label: {
                            libraryLabel(list.name, symbol: list.iconName, token: list.colour)
                        }
                    }
                }
                .listRowBackground(FlowTheme.surface(scheme))
            }

            Section(header: sectionHeader("BUILD & REVIEW")) {
                NavigationLink { ProjectsScreen() } label: {
                    libraryLabel("Projects", symbol: "folder", token: .lavender)
                }
                NavigationLink { NotesRootView() } label: {
                    libraryLabel("Notes", symbol: "doc.text", token: .yellow)
                }
                NavigationLink { ProgressScreen() } label: {
                    libraryLabel("Progress", symbol: "chart.bar", token: .pink)
                }
                Button {
                    showingAssistant = true
                } label: {
                    libraryLabel("Assistant", symbol: "sparkles", token: .teal)
                }
                NavigationLink { SettingsScreen() } label: {
                    libraryLabel("Settings", symbol: "gearshape", token: .blue)
                }
            }
            .listRowBackground(FlowTheme.surface(scheme))
        }
        .scrollContentBackground(.hidden)
        .background(FlowTheme.background(scheme).ignoresSafeArea())
        .flowScreenTitle("Library")
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
            GlobalSearchView { result in onSearchResult(result) }
        }
        .sheet(isPresented: $showingCapture) {
            QuickCaptureView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(FlowRadius.large)
        }
    }

    /// The design's pastel token order for smart-view rows, cycled in order.
    private static let rowTokens: [ColourToken] = [
        .teal, .blue, .peach, .yellow, .lavender, .green, .pink,
    ]

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .kerning(1.5)
            .foregroundStyle(FlowTheme.tertiaryText(scheme))
    }

    /// The mock's row: soft token squircle with a solid dot, then the title.
    private func libraryLabel(_ title: String, symbol: String, token: ColourToken) -> some View {
        HStack(spacing: FlowSpacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: FlowRadius.tile, style: .continuous)
                    .fill(token.soft)
                    .frame(width: 32, height: 32)
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(token.onSoft)
            }
            Text(title)
                .font(FlowFont.body.weight(.semibold))
                .foregroundStyle(FlowTheme.primaryText(scheme))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
#endif

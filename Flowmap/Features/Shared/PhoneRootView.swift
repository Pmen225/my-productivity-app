#if !os(macOS)
import SwiftData
import SwiftUI

/// The iPhone shell: a real, native tab bar with exactly five destinations —
/// Plan, Focus, Map + Today, Calendar, Settings — restyled with `FlowTheme`.
///
/// Decision 1b (2026-07-29) reverses the `≡` glass menu subtask 37 built.
/// That menu still switched tabs through a hidden 7-tag `TabView`, and iOS
/// collapses any `TabView` past 5 tags into a stock system "More" list
/// regardless of `.toolbar(.hidden, for: .tabBar)` — confirmed the hard way
/// on Stats/Settings. Capping this `TabView` at exactly 5 tags and letting it
/// draw its own chrome (instead of hiding it behind a custom overlay) avoids
/// the bug and gives a genuinely native tab bar, not a web-style hamburger.
struct PhoneRootView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var allTasks: [FlowTask]

    // The mockup's launch screen is Focus (`00-initial.png`).
    @State private var tab: DeepLink = .focus
    @State private var showingAssistant = false
    @State private var showingSearch = false
    @State private var showingCapture = false
    // Today is no longer a tab (decision 1b) — it stays reachable by deep
    // link and notification, presented as a sheet, until T3 folds it into
    // the Map page as a pane.
    @State private var showingToday = false
    // Stats also isn't a tab — it's a chart-icon push on Plan's own
    // NavigationStack. Owned here so the deep-link handler can drive it from
    // outside Plan/LibraryView.
    @State private var pushStats = false

    private var inboxCount: Int {
        SmartView.inbox.matches(allTasks).count
    }

    /// Space the FAB and the Assistant orb reserve at the bottom of the three
    /// screens they float over, so the last row of a list is reachable instead
    /// of sitting under them. The mock leans on an idle-fade for this; a native
    /// tab bar does not fade, so the room is reserved outright — the stack's
    /// own height, plus the gap it is padded off the bottom by, plus a breath
    /// so the last row does not touch the orb.
    private static let floatingControlsInset =
        FlowControlSize.create + FlowSpacing.m + FlowControlSize.secondary
            + FlowSpacing.xxxl + FlowSpacing.l

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                NavigationStack {
                    LibraryView(showingAssistant: $showingAssistant, pushStats: $pushStats, onSearchResult: navigate(to:))
                }
                .contentMargins(.bottom, Self.floatingControlsInset, for: .scrollContent)
                .tabItem { Label("Plan", systemImage: "square.stack") }
                .tag(DeepLink.library)
                .badge(inboxCount > 0 ? "\(inboxCount)" : nil)

                NavigationStack {
                    FocusScreen()
                }
                .tabItem { Label("Focus", systemImage: "timer") }
                .tag(DeepLink.focus)

                NavigationStack {
                    MapTodayScreen()
                }
                .contentMargins(.bottom, Self.floatingControlsInset, for: .scrollContent)
                .tabItem {
                    Label("Map + Today", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .tag(DeepLink.map)

                NavigationStack {
                    CalendarRootView()
                }
                .contentMargins(.bottom, Self.floatingControlsInset, for: .scrollContent)
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(DeepLink.calendar)

                NavigationStack {
                    SettingsScreen()
                }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(DeepLink.settings)
            }
            // The system bar now actually renders — restyled, not hidden.
            // The `.ultraThinMaterial` matches the base layer `.flowGlass()`
            // uses everywhere else in the chrome (see `GlassBackground` in
            // `FlowSurfaces.swift`); the accent tint matches `FlowTabBar`'s
            // restored-but-unused styling in `FlowChrome.swift`.
            .tint(FlowTheme.accent)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
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
                // Clears the now-visible native tab bar rather than a
                // floating one, so the FAB stack sits above its safe area.
                .padding(.bottom, FlowSpacing.xxxl)
            }
        }
        .overlay { FlowMomentOverlay() }
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
        // Today: sheet, not full-screen cover — matches the ambient idiom
        // this shell already uses for Assistant/Search/Quick capture, and it
        // is an interim, deep-link-only destination until T3 folds it into
        // Map + Today.
        .sheet(isPresented: $showingToday) {
            NavigationStack { TodayView() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .flowmapOpenDeepLink)) { notification in
            guard let request = notification.object as? DeepLinkRequest else { return }
            switch request.destination {
            case .assistant: showingAssistant = true
            case .inbox: tab = .library
            case .today: showingToday = true
            case .stats:
                tab = .library
                pushStats = true
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
    /// Stats dropped off the tab bar (decision 1b) and is reached instead by
    /// a chart-icon push on this screen's own `NavigationStack`. Owned by
    /// `PhoneRootView` so its deep-link handler can drive the push from
    /// outside Plan too.
    @Binding var pushStats: Bool
    /// Routes a chosen search result, so a Library search behaves like the
    /// shell's own — selecting a result must actually go somewhere.
    let onSearchResult: (SearchResult) -> Void

    @State private var showingSearch = false
    @State private var showingCapture = false

    var body: some View {
        List {
            // Triage first: what has no slot yet, above the places to go
            // looking for everything that has one.
            PlanInboxSection()
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
        // Named for the tab that reaches it (decision 1b), not for the type —
        // a screen titled "Library" under a tab labelled "Plan" reads as two
        // different places.
        .flowScreenTitle("Plan")
        .toolbar {
            // Left at trailing, where subtask 37's `≡` build put it — that
            // rationale (the floating `≡` owning the top-left corner) no
            // longer applies now the tab bar is back, but there is no design
            // authority for a specific placement here, so it stays rather
            // than guess. Open question, see closing handover.
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSearch = true } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("Search")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCapture = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Quick capture")
            }
            // Stats: decision 1b drops it off the tab bar; reached instead
            // by this chart-icon push, normal `NavigationLink` behaviour, not
            // a tab and not a sheet.
            ToolbarItem(placement: .topBarTrailing) {
                Button { pushStats = true } label: { Image(systemName: "chart.bar") }
                    .accessibilityLabel("Stats")
            }
        }
        .navigationDestination(isPresented: $pushStats) {
            ProgressScreen()
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

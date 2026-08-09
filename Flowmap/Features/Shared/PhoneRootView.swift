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
    @State private var showingAssistantDock = false
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


    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                NavigationStack {
                    LibraryView(pushStats: $pushStats, onSearchResult: navigate(to:))
                }
                .contentMargins(.bottom, FlowSpacing.floatingControlsInset, for: .scrollContent)
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
                .contentMargins(.bottom, FlowSpacing.floatingControlsInset, for: .scrollContent)
                .tabItem {
                    Label("Map", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .tag(DeepLink.map)

                NavigationStack {
                    CalendarRootView()
                }
                // No inset here: Calendar's only scroll views sit inside a
                // paging `TabView`, which this modifier does not reach. They
                // reserve the same room themselves.
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(DeepLink.calendar)

                NavigationStack {
                    SettingsScreen()
                }
                // Settings has its own long scroll. Reserve space for the
                // native tab bar and the shell's floating capture/assistant
                // orb so the last controls remain readable and tappable.
                .contentMargins(.bottom, FlowSpacing.floatingControlsInset, for: .scrollContent)
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
                captureAssistantOrb
                .padding(.trailing, FlowSpacing.screen)
                // Clears the now-visible native tab bar rather than a
                // floating one, so the orb sits above its safe area.
                .padding(.bottom, FlowSpacing.xxxl)
            }
        }
        .overlay { FlowMomentOverlay() }
        .sheet(isPresented: $showingAssistant) {
            NavigationStack { AssistantScreen() }
        }
        // The mini dock (decision 26, HIG ruling 1): a nonmodal, resizable
        // supplementary surface. The orb opens this first; `⤢` hands off to
        // the full `showingAssistant` sheet above. Hosted here, on the
        // shell's own body, per the `.sheet`-on-`Section` trap.
        .sheet(isPresented: $showingAssistantDock) {
            AssistantMiniDockView(
                onExpand: expandAssistantDock,
                onClose: { showingAssistantDock = false }
            )
            .presentationDetents([.height(360), .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled)
            .presentationCornerRadius(FlowRadius.large)
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
        .sheet(item: rolloverReviewBinding) { _ in
            RolloverReviewView()
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

    /// The shell's single primary orb. Tapping captures work; Assistant remains
    /// one long press or VoiceOver custom action away without competing for a
    /// second bottom-corner control.
    private var captureAssistantOrb: some View {
        FlowFloatingButton(
            systemImage: "plus",
            diameter: FlowControlSize.create,
            background: FlowTheme.accentFill,
            foreground: .white,
            shadowColor: FlowTheme.accentShadow,
            accessibilityLabel: "New task, project or initiative",
            badgeSystemImage: "sparkles",
            assistantAction: { showingAssistantDock = true },
            hapticsEnabled: flow?.settings.focusHapticsEnabled ?? false
        ) {
            showingCapture = true
        }
    }

    /// Closes the dock before presenting the full screen (HIG: close one
    /// sheet before showing another, rather than stacking sheet-on-sheet).
    /// Reduce Motion skips the hand-off delay instead of imposing one.
    private func expandAssistantDock() {
        showingAssistantDock = false
        let delay = reduceMotion ? 0 : 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            showingAssistant = true
        }
    }

    private func navigate(to result: SearchResult) {
        switch result.kind {
        case .task, .project, .note: tab = .library
        case .assistantThread: showingAssistant = true
        }
    }

    private var rolloverReviewBinding: Binding<RolloverReview?> {
        Binding(
            get: { flow?.pendingRolloverReview },
            set: { value in
                if value == nil { flow?.pendingRolloverReview = nil }
            }
        )
    }
}

/// Everything that does not earn its own tab.
struct LibraryView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @Query private var allTasks: [FlowTask]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    // Same sort `NotesListView` uses, so "note preview row order" cannot
    // drift between the two places notes are listed.
    @Query(sort: \Note.updatedAt, order: .reverse) private var allNotes: [Note]

    /// Stats dropped off the tab bar (decision 1b) and is reached instead by
    /// a chart-icon push on this screen's own `NavigationStack`. Owned by
    /// `PhoneRootView` so its deep-link handler can drive the push from
    /// outside Plan too.
    @Binding var pushStats: Bool
    /// Routes a chosen search result, so a Library search behaves like the
    /// shell's own — selecting a result must actually go somewhere.
    let onSearchResult: (SearchResult) -> Void

    @State private var showingSearch = false
    /// The task tapped inside an unfolded TASKS row. A sheet, not a push into
    /// Focus — decision 10 already answered this exact question for the
    /// Today pane, and one screen cannot mean two things by the same tap.
    /// Mirrors `TaskListScreen.swift`'s own `selectedTask` wiring.
    @State private var inspectedTask: FlowTask?
    /// The note tapped inside the unfolded Notes row — opens the same
    /// `NoteEditorView` a push from `NotesListView` would (ruling 7, T6
    /// stage 2), as a sheet to match `inspectedTask`'s presentation above.
    @State private var inspectedNote: Note?
    /// Hosted on this screen's top-level List, not inside the Notes accordion:
    /// a presentation modifier below a nested Section can silently fail to
    /// present. The contextual menu only selects the note to attach.
    @State private var attachmentPickerNote: Note?
    /// Which BUILD and REVIEW accordions are open, keyed by a stable id per row.
    @State private var expandedRows: Set<String> = []
    @State private var taskPage: TaskPage = Self.initialTaskPage
    /// Inbox remains the capture-first Plan surface. User lists are opened as
    /// a separate paged surface so smart views never become swipe pages.
    @State private var showingListCarousel = false
    @State private var selectedListID: UUID?
    /// The prioritise duel and plan-preview sheets `PlanInboxSection`'s
    /// buttons trigger, hosted HERE rather than inside `PlanInboxSection`
    /// itself: `PlanInboxSection` is only one `Section` among several inside
    /// this screen's own `List`, and a `.sheet` attached that deep never
    /// presented — see the comment on `PlanInboxSection`'s bindings of the
    /// same names. Owning them at this List's own top level is the pattern
    /// `inspectedTask`/`inspectedNote`/`showingSearch` above already use
    /// successfully.
    @State private var showingDuel = false
    @State private var showingPlanPreview = false
    @State private var planProposal: PlanProposal?
    /// "New list" and swipe-to-delete for the LISTS section, hosted here for
    /// the same reason as `showingDuel`/`showingPlanPreview` above: a
    /// `.sheet`/`.confirmationDialog` attached to a `Section` nested in this
    /// screen's own `List` never presents.
    @State private var showCreateList = false
    @State private var pendingListDelete: TaskList?
    @State private var pendingProjectDelete: Project?

    /// Ordered peers in the Plan tab's task surface. Inbox is deliberately
    /// page zero because it is the capture-to-triage entry point; completed is
    /// last because it is history, not the next action.
    enum TaskPage: String, CaseIterable, Identifiable {
        case inbox, today, upcoming, anytime, allTasks, completed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .inbox: "Inbox"
            case .today: "Today"
            case .upcoming: "Upcoming"
            case .anytime: "Anytime"
            case .allTasks: "All tasks"
            case .completed: "Completed"
            }
        }

        var smartView: SmartView? {
            switch self {
            case .inbox: nil
            case .today: .today
            case .upcoming: .upcoming
            case .anytime: .anytime
            case .allTasks: .allTasks
            case .completed: .completed
            }
        }
    }

    static let taskPages = TaskPage.allCases
    /// The five smart destinations intentionally share one menu. Inbox is
    /// the separate default capture button and is not a peer in this menu.
    static let smartTaskPages: [TaskPage] = [.today, .upcoming, .anytime, .allTasks, .completed]
    static let initialTaskPage: TaskPage = .inbox

    /// Kept pure so the selected-page rule is covered without needing a
    /// simulator to drive a swipe. Choosing the current page is intentionally
    /// idempotent; it should not restart a transition or collapse Inbox edits.
    static func taskPageSelection(from current: TaskPage, choosing candidate: TaskPage) -> TaskPage {
        current == candidate ? current : candidate
    }

    /// The exact tasks a non-Inbox page shows, sorted for display. Both the
    /// page and this helper read the same SmartView filter, so they cannot
    /// drift into different counts or contents.
    static func taskPageContent(for view: SmartView, in tasks: [FlowTask], now: Date) -> [FlowTask] {
        view.sorted(view.matches(tasks, now: now), grouping: .manual)
    }

    var body: some View {
        planSurface
            .background(FlowTheme.background(scheme).ignoresSafeArea())
            // Named for the tab that reaches it (decision 1b), not for the type —
            // a screen titled "Library" under a tab labelled "Plan" reads as two
            // different places.
            .flowScreenTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSearch = true } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("Search")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { pushStats = true } label: { Image(systemName: "chart.bar") }
                        .accessibilityLabel("Stats")
                }
            }
            .navigationDestination(isPresented: $pushStats) {
                ProgressScreen()
            }
            .navigationDestination(for: Project.self) { project in
                ProjectDetailView(project: project)
            }
            .sheet(isPresented: $showingSearch) {
                GlobalSearchView { result in onSearchResult(result) }
            }
            .sheet(item: $inspectedTask) { task in
                NavigationStack { TaskDetailInspector(task: task) }
            }
            .sheet(item: $inspectedNote) { note in
                NavigationStack { NoteEditorView(note: note) }
            }
            .sheet(item: $attachmentPickerNote) { note in
                NoteAttachPickerView(
                    candidates: NoteAttachCandidates.display(noteCandidates, attached: note.task),
                    current: note.task
                ) { task in
                    toggleAttach(note: note, task: task)
                }
            }
            // Hosted here, not on `PlanInboxSection`'s `Section`. A `.sheet`
            // attached to a `Section` nested inside this `List` never presents.
            .sheet(isPresented: $showingDuel) {
                PrioritiseDuelView(tasks: SmartView.today.matches(allTasks, now: flow?.now ?? Date()))
            }
            .sheet(isPresented: $showingPlanPreview) {
                PlanPreviewView(
                    proposal: planProposal ?? PlanProposal(),
                    tasksByID: Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) }),
                    onApply: applyPlan,
                    onReplanWholeDay: replanWholeDay
                )
            }
            .sheet(isPresented: $showCreateList) {
                CreateListSheet()
            }
            .confirmationDialog(
                "Delete this list?",
                isPresented: Binding(get: { pendingListDelete != nil }, set: { if !$0 { pendingListDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete List", role: .destructive) {
                    if let list = pendingListDelete {
                        context.delete(list)
                        try? context.save()
                    }
                    pendingListDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingListDelete = nil }
            } message: {
                Text("Tasks inside stay in Flowmap and move to Inbox.")
            }
            .flowDeleteConfirmation(
                isPresented: projectDeleteBinding,
                itemTitle: pendingProjectDelete?.title ?? "",
                hasChildren: !(pendingProjectDelete?.tasks ?? []).isEmpty,
                onDelete: deletePendingProject
            )
    }

    @ViewBuilder
    private var planSurface: some View {
        if showingListCarousel {
            listCarousel
        } else {
            smartViewSurface
        }
    }

    @ViewBuilder
    private var smartViewSurface: some View {
        #if os(macOS)
        planList(for: taskPage)
        #else
        planList(for: taskPage)
        #endif
    }

    /// The only horizontal paging in Plan. Each page owns the vertical list
    /// supplied by `TaskListScreen`; smart views are selected from the Menu
    /// above instead of competing for the swipe gesture.
    @ViewBuilder
    private var listCarousel: some View {
        if lists.isEmpty {
            List {
                Section {
                    listTitleStrip
                    emptyRow("No lists yet. Create one to start a focused list.")
                    Button { showCreateList = true } label: {
                        Label("New list", systemImage: "plus")
                    }
                    .tint(FlowTheme.accent)
                }
                .listRowBackground(FlowTheme.surface(scheme))
            }
            .scrollContentBackground(.hidden)
        } else {
            VStack(spacing: 0) {
                listTitleStrip
                #if os(macOS)
                if let list = selectedList {
                    TaskListScreen(source: .userList(list))
                }
                #else
                TabView(selection: selectedListBinding) {
                    ForEach(lists) { list in
                        TaskListScreen(source: .userList(list))
                            .tag(list.id)
                            .accessibilityIdentifier("user-list-page-\(list.id.uuidString)")
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
            }
        }
    }

    private var selectedList: TaskList? {
        guard let selectedListID else { return lists.first }
        return lists.first(where: { $0.id == selectedListID }) ?? lists.first
    }

    private var selectedListBinding: Binding<UUID> {
        Binding(
            get: { selectedList?.id ?? UUID() },
            set: { id in
                if reduceMotion {
                    selectedListID = id
                } else {
                    withAnimation(.snappy(duration: 0.24)) { selectedListID = id }
                }
            }
        )
    }

    private func planList(for page: TaskPage) -> some View {
        List {
            Section {
                taskPageTitleStrip
            }
            .listRowBackground(Color.clear)

            directListRoute

            taskPageSection(page)

            Section(header: sectionHeader("BUILD")) {
                projectsAccordion
                notesAccordion
            }
            .listRowBackground(FlowTheme.surface(scheme))

        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Inbox plan preview

    /// Moved here from `PlanInboxSection` along with the sheet it drives —
    /// see the comment on that view's `showingPlanPreview` binding.
    private func applyPlan() {
        guard let flow, let planProposal else { return }
        flow.applyPlan(planProposal, replanExisting: false)
        showingPlanPreview = false
    }

    private func replanWholeDay() {
        guard let flow else { return }
        planProposal = flow.planToday(replanExisting: true)
    }

    // MARK: - TASKS pages

    /// Smart views are one native Menu. Inbox is deliberately a separate
    /// 44pt capture button; it remains the default surface without becoming a
    /// sixth menu item. Lists has its own title strip and page-style pager.
    private var taskPageTitleStrip: some View {
        HStack(spacing: FlowSpacing.m) {
            Button {
                showingListCarousel = false
                selectTaskPage(.inbox)
            } label: {
                Text("Inbox")
                    .font(taskPage == .inbox ? FlowFont.cardTitle : FlowFont.body)
                    .foregroundStyle(taskPage == .inbox ? FlowTheme.primaryText(scheme) : FlowTheme.tertiaryText(scheme))
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Task page: Inbox")
            .accessibilityHint("Opens the capture and triage page")

            smartTaskMenu

            Spacer(minLength: FlowSpacing.s)

            Button {
                showingListCarousel = true
                if selectedListID == nil { selectedListID = lists.first?.id }
            } label: {
                Label("Lists", systemImage: "list.bullet")
                    .labelStyle(.titleAndIcon)
                    .font(FlowFont.body.weight(.semibold))
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Lists")
            .accessibilityHint("Opens your lists and lets you swipe between them")

        }
    }

    /// Keep one direct list route for existing workflows while the complete
    /// user-list set remains owned by the carousel. Hosting this as a native
    /// List row (rather than a clipped title-strip link) preserves its 44pt
    /// hit target and existing navigation/options flow.
    @ViewBuilder
    private var directListRoute: some View {
        if let firstList = lists.first {
            Section {
                NavigationLink {
                    TaskListScreen(source: .userList(firstList))
                } label: {
                    libraryLabel(firstList.name, symbol: firstList.iconName, token: firstList.colour)
                }
                .accessibilityLabel(firstList.name)
                .accessibilityHint("Opens this list")
            }
            .listRowBackground(FlowTheme.surface(scheme))
        }
    }

    /// Quiet adjacent-name strip for the user-list pager. The Menu is the
    /// direct-selection and VoiceOver path; the title buttons are a discoverable
    /// visual hint that the content below is horizontally paged.
    private var listTitleStrip: some View {
        HStack(spacing: FlowSpacing.s) {
            Button {
                showingListCarousel = false
                selectTaskPage(.inbox)
            } label: {
                Text("Inbox")
                    .font(FlowFont.body)
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Task page: Inbox")
            smartTaskMenu

            Menu {
                ForEach(lists) { list in
                    Button {
                        selectList(list)
                    } label: {
                        Label(list.name, systemImage: list.id == selectedList?.id ? "checkmark" : list.iconName)
                    }
                    .accessibilityIdentifier("user-list-choice-\(list.id.uuidString)")
                }
                Divider()
                Button { showCreateList = true } label: {
                    Label("New list", systemImage: "plus")
                }
                if let list = selectedList {
                    Button(role: .destructive) {
                        pendingListDelete = list
                    } label: {
                        Label("Delete \(list.name)", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Choose list")
            .accessibilityHint("Shows every user-created list")

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FlowSpacing.m) {
                        ForEach(lists) { list in
                            Button {
                                selectList(list)
                            } label: {
                                Text(list.name)
                                    .font(list.id == selectedList?.id ? FlowFont.screenTitleCompact : FlowFont.cardTitle)
                                    .foregroundStyle(list.id == selectedList?.id ? FlowTheme.primaryText(scheme) : FlowTheme.tertiaryText(scheme))
                                    .lineLimit(1)
                                    .frame(minHeight: 52)
                            }
                            .id(list.id)
                            .accessibilityLabel("List: \(list.name)")
                            .accessibilityValue(list.id == selectedList?.id ? "Selected" : "")
                        }
                    }
                    .padding(.horizontal, FlowSpacing.xs)
                }
                .onChange(of: selectedList?.id) { _, id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .padding(.horizontal, FlowSpacing.m)
        .background(FlowTheme.background(scheme))
    }

    /// Shared smart-view menu, intentionally present in both Inbox/smart mode
    /// and Lists mode so direct selection never depends on the current pager.
    private var smartTaskMenu: some View {
        Menu {
            ForEach(Self.smartTaskPages) { candidate in
                Button {
                    showingListCarousel = false
                    selectTaskPage(candidate)
                } label: {
                    if candidate == taskPage {
                        Label(candidate.title, systemImage: "checkmark")
                    } else {
                        Text(candidate.title)
                    }
                }
                .accessibilityIdentifier("smart-task-page-\(candidate.rawValue)")
            }
        } label: {
            HStack(spacing: FlowSpacing.xs) {
                Text(taskPage == .inbox ? "Views" : taskPage.title)
                    .font(FlowFont.cardTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                Image(systemName: "chevron.down")
                    .font(FlowFont.caption.weight(.semibold))
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Smart task views")
        .accessibilityHint("Shows Today, Upcoming, Anytime, All tasks and Completed")
    }

    private func selectList(_ list: TaskList) {
        if reduceMotion {
            selectedListID = list.id
        } else {
            withAnimation(.snappy(duration: 0.24)) { selectedListID = list.id }
        }
    }

    @ViewBuilder
    private func taskPageSection(_ page: TaskPage) -> some View {
        if page == .inbox {
            PlanInboxSection(
                showingDuel: $showingDuel,
                showingPlanPreview: $showingPlanPreview,
                planProposal: $planProposal,
                showsHeader: false
            )
        } else if let view = page.smartView {
            let tasks = Self.taskPageContent(for: view, in: allTasks, now: flow?.now ?? Date())
            Section {
                if tasks.isEmpty {
                    emptyRow(view.emptyMessage)
                } else {
                    ForEach(tasks) { task in
                        TaskRowView(task: task)
                            .contentShape(Rectangle())
                            .onTapGesture { inspectedTask = task }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listRowBackground(FlowTheme.surface(scheme))
        }
    }

    private func selectTaskPage(_ page: TaskPage) {
        let next = Self.taskPageSelection(from: taskPage, choosing: page)
        guard next != taskPage else { return }
        if reduceMotion {
            taskPage = next
        } else {
            withAnimation(.snappy(duration: 0.24)) {
                taskPage = next
            }
        }
    }

    // MARK: - BUILD accordion

    private var projectsAccordion: some View {
        LibraryAccordionRow(
            title: "Projects",
            symbol: "folder",
            token: .lavender,
            count: projects.count,
            isExpanded: expansionBinding(for: "projects")
        ) {
            if projects.isEmpty {
                // Drops the mock's "in the full app" — that clause was the
                // demo apologising for being a demo. This is the full app.
                emptyRow("No projects yet. Branches of your map can become projects.")
            } else {
                ForEach(projects) { project in
                    NavigationLink(value: project) {
                        ProjectRow(project: project)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    #if os(iOS)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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

    // MARK: - Notes accordion

    /// Notes shown in the accordion — active notes only, most recently
    /// updated first. Both the header's count and the unfolded rows read
    /// this one array, so they cannot disagree, the same principle
    /// `taskAccordionContent` already follows. `allNotes` is already sorted
    /// by `updatedAt` descending, so filtering preserves that order.
    static func noteAccordionContent(in notes: [Note]) -> [Note] {
        notes.filter { !$0.isArchived && !$0.isTrashed }
    }

    /// Tasks a note can attach to — a completed or cancelled task is not a
    /// sensible attach target. Exposed so a test can assert the filter
    /// without touching view state.
    static func noteAttachCandidates(in tasks: [FlowTask]) -> [FlowTask] {
        tasks
            .filter { $0.status.isOpen }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private var noteCandidates: [FlowTask] {
        Self.noteAttachCandidates(in: allTasks)
    }

    private var notesAccordion: some View {
        let notes = Self.noteAccordionContent(in: allNotes)
        return LibraryAccordionRow(
            title: "Notes",
            symbol: "doc.text",
            token: .yellow,
            count: notes.count,
            isExpanded: expansionBinding(for: "notes")
        ) {
            if notes.isEmpty {
                emptyRow("No notes yet.")
            } else {
                ForEach(notes) { note in
                    NoteAttachRow(note: note, candidates: noteCandidates) { task in
                        toggleAttach(note: note, task: task)
                    } content: {
                        notePreviewRow(note)
                    } onShowPicker: {
                        attachmentPickerNote = note
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
    }

    /// One note's row: the accordion's own `.yellow` dot (not the mockup's
    /// leaked task colour — ruling 3, T6 stage 2), its title, and — only
    /// when attached to something — a trailing `On <task>` tag. Tapping
    /// opens the note itself (ruling 7).
    private func notePreviewRow(_ note: Note) -> some View {
        HStack(spacing: FlowSpacing.s) {
            Circle().fill(ColourToken.yellow.base).frame(width: 9, height: 9)
            Text(note.title)
                .font(FlowFont.body)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .lineLimit(1)
            Spacer(minLength: FlowSpacing.s)
            if let task = note.task {
                Text("On \(task.title)")
                    // `durationChip` rather than a literal 10pt: it is the
                    // existing token for exactly this small bold tag, and it
                    // is built on `.caption2`, so it scales with Dynamic Type.
                    // A fixed size would not, which is an accessibility bug as
                    // well as a hard-coded size.
                    .font(FlowFont.durationChip)
                    .lineLimit(1)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                    .padding(.horizontal, FlowSpacing.s)
                    .padding(.vertical, FlowSpacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: FlowRadius.tile, style: .continuous)
                            .fill(FlowTheme.surfaceWell(scheme))
                    )
            }
        }
        .contentShape(Rectangle())
        // Keep the compact row scannable without letting the note title touch
        // the accordion header or the next row at Dynamic Type sizes.
        .padding(.vertical, FlowSpacing.xs)
        .onTapGesture { inspectedNote = note }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens note")
    }

    /// Attach is single-select (ruling 4): tapping the already-attached
    /// task's chip detaches it (`task` and `current` share an id), choosing a
    /// different one re-assigns rather than adding. Exposed so a test can
    /// assert the toggle rule without touching view state or SwiftData.
    static func attachToggleResult(current: FlowTask?, tapped: FlowTask?) -> FlowTask? {
        current?.id == tapped?.id ? nil : tapped
    }

    private func toggleAttach(note: Note, task: FlowTask?) {
        note.task = Self.attachToggleResult(current: note.task, tapped: task)
        note.touch()
        try? context.save()
    }

    // MARK: - Expansion state

    private func expansionBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { expandedRows.contains(key) },
            set: { isExpanded in
                if isExpanded { expandedRows.insert(key) } else { expandedRows.remove(key) }
            }
        )
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
    /// Still used by the LISTS section's plain `NavigationLink` rows.
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

    /// Plain empty-state row inside an unfolded accordion — no `FlowEmptyState`
    /// symbol/title component, which is full-screen-empty-state weight and
    /// far too heavy for one unfolded row (HIG *Boxes*: no nested boxes).
    private func emptyRow(_ message: String) -> some View {
        Text(message)
            .font(FlowFont.caption)
            .foregroundStyle(FlowTheme.tertiaryText(scheme))
    }
}
#endif

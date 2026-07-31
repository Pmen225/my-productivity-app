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
            assistantAction: { showingAssistant = true },
            hapticsEnabled: flow?.settings.focusHapticsEnabled ?? false
        ) {
            showingCapture = true
        }
    }

    private func navigate(to result: SearchResult) {
        switch result.kind {
        case .task, .project, .note: tab = .library
        case .mapNode: tab = .map
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
        taskPager
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
    private var taskPager: some View {
        #if os(macOS)
        planList(for: taskPage)
        #else
        TabView(selection: $taskPage) {
            ForEach(Self.taskPages) { page in
                planList(for: page)
                    .tag(page)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
    }

    private func planList(for page: TaskPage) -> some View {
        List {
            Section {
                taskPageTitleStrip
            }
            .listRowBackground(Color.clear)

            taskPageSection(page)

            Section(header: sectionHeader("LISTS")) {
                ForEach(lists) { list in
                    NavigationLink {
                        TaskListScreen(source: .userList(list))
                    } label: {
                        libraryLabel(list.name, symbol: list.iconName, token: list.colour)
                    }
                    #if os(iOS)
                    .swipeActions(edge: .trailing) {
                        // No `role: .destructive`: that role rebuilds the row as
                        // the swipe closes, which resets state and silently drops
                        // the confirmation (see TaskRowView). The tint carries
                        // the same meaning.
                        Button {
                            pendingListDelete = list
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(FlowTheme.destructive)
                    }
                    #endif
                }
                Button {
                    showCreateList = true
                } label: {
                    Label("New list", systemImage: "plus")
                }
                .tint(FlowTheme.accent)
            }
            .listRowBackground(FlowTheme.surface(scheme))

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

    /// The title strip is intentionally a single native Menu rather than six
    /// narrow buttons. Paging owns the swipe; the Menu gives the same ordered
    /// destinations to a tap, VoiceOver and Dynamic Type without cramming the
    /// strip or making small dots pretend to be controls.
    private var taskPageTitleStrip: some View {
        HStack(spacing: FlowSpacing.m) {
            Menu {
                ForEach(Self.taskPages) { candidate in
                    Button {
                        selectTaskPage(candidate)
                    } label: {
                        if candidate == taskPage {
                            Label(candidate.title, systemImage: "checkmark")
                        } else {
                            Text(candidate.title)
                        }
                    }
                    .accessibilityIdentifier("task-page-\(candidate.rawValue)")
                }
            } label: {
                HStack(spacing: FlowSpacing.xs) {
                    Text(taskPage.title)
                        .font(FlowFont.cardTitle)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                    Image(systemName: "chevron.down")
                        .font(FlowFont.caption.weight(.semibold))
                        .foregroundStyle(FlowTheme.tertiaryText(scheme))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Task page: \(taskPage.title)")
            .accessibilityHint("Shows Inbox, Today, Upcoming, Anytime, All tasks and Completed")

            Spacer(minLength: FlowSpacing.s)

            HStack(spacing: FlowSpacing.xxs) {
                ForEach(Self.taskPages) { candidate in
                    Circle()
                        .fill(candidate == taskPage ? FlowTheme.accent : FlowTheme.separator(scheme))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)
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

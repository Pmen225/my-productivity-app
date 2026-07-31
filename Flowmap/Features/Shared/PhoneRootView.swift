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
                    Label("Map + Today", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
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
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @Query private var allTasks: [FlowTask]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \TaskSegment.startDate) private var allSegments: [TaskSegment]
    @Query(sort: \FocusSession.startedAt) private var allSessions: [FocusSession]
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
    /// Which accordion rows are open, keyed by a stable id per row.
    @State private var expandedRows: Set<String> = []
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

    /// The five `SmartView` cases the TASKS section shows as accordions.
    /// `.inbox` is left out on purpose: `PlanInboxSection` already renders
    /// the whole inbox inline with editing directly above, and the tab
    /// already carries the inbox badge — unfolding it a second time here
    /// would be duplication, not parity. Exposed so a test can assert this
    /// list directly rather than reading the view body.
    static let taskAccordionViews: [SmartView] = [.today, .upcoming, .anytime, .allTasks, .completed]

    /// The exact tasks a TASKS accordion shows, sorted for display. Both the
    /// header's count and the unfolded rows read this one array, never two
    /// separately written filters, so they cannot disagree.
    static func taskAccordionContent(for view: SmartView, in tasks: [FlowTask], now: Date) -> [FlowTask] {
        view.sorted(view.matches(tasks, now: now), grouping: .manual)
    }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = flow?.settings.firstWeekday ?? 2
        return calendar
    }

    /// Today's headline numbers for the Stats row's unfolded tile strip —
    /// the same `ProgressMetrics` maths `ProgressScreen` uses, never a
    /// second metrics path.
    private var statsSummary: ProgressSummary {
        let range = ProgressPeriod.today.range(containing: flow?.now ?? Date(), calendar: calendar)
        return ProgressMetrics.summary(tasks: allTasks, segments: allSegments, sessions: allSessions, range: range)
    }

    var body: some View {
        List {
            // Triage first: what has no slot yet, above the places to go
            // looking for everything that has one.
            PlanInboxSection(
                showingDuel: $showingDuel,
                showingPlanPreview: $showingPlanPreview,
                planProposal: $planProposal
            )
            Section(header: sectionHeader("TASKS")) {
                ForEach(Array(Self.taskAccordionViews.enumerated()), id: \.element) { index, view in
                    taskAccordion(view, token: Self.rowTokens[index % Self.rowTokens.count])
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

            Section(header: sectionHeader("BUILD")) {
                projectsAccordion
                notesAccordion
            }
            .listRowBackground(FlowTheme.surface(scheme))

            Section(header: sectionHeader("REVIEW")) {
                statsAccordion
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
            // No `+` here. The shell's floating create button already floats
            // over this tab and opens the same `QuickCaptureView`, so a second
            // one only crowded the bar — and the duplicate presented from
            // inside this screen rendered a text field that never became first
            // responder, so it was the broken copy of the two.
            // Stats: decision 1b drops it off the tab bar; reached instead
            // by this chart-icon push, normal `NavigationLink` behaviour, not
            // a tab and not a sheet. Separate from the REVIEW section's Stats
            // accordion below, which only unfolds today's tile strip in
            // place — this pushes the full `ProgressScreen`.
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
        // Hosted here, not on `PlanInboxSection`'s `Section`. A `.sheet`
        // attached to a `Section` nested inside this `List` never presents:
        // the flag flips and nothing appears, with no error and no test
        // failure. That is how the duel silently stopped opening when T6
        // moved its entry point off `TaskListScreen`.
        .sheet(isPresented: $showingDuel) {
            PrioritiseDuelView(tasks: SmartView.inbox.matches(allTasks))
        }
        .sheet(isPresented: $showingPlanPreview) {
            PlanPreviewView(
                proposal: planProposal ?? PlanProposal(),
                tasksByID: Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) }),
                onApply: applyPlan,
                onReplanWholeDay: replanWholeDay
            )
        }
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

    // MARK: - TASKS accordions

    @ViewBuilder
    private func taskAccordion(_ view: SmartView, token: ColourToken) -> some View {
        let tasks = Self.taskAccordionContent(for: view, in: allTasks, now: flow?.now ?? Date())
        LibraryAccordionRow(
            title: view.displayName,
            symbol: view.symbolName,
            token: token,
            count: tasks.count,
            isExpanded: expansionBinding(for: view.rawValue)
        ) {
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
                }
            }
        }
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
                    VStack(alignment: .leading, spacing: FlowSpacing.s) {
                        notePreviewRow(note)
                        NoteAttachRow(note: note, candidates: noteCandidates) { task in
                            toggleAttach(note: note, task: task)
                        }
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
        .onTapGesture { inspectedNote = note }
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

    // MARK: - REVIEW accordion

    private var statsAccordion: some View {
        LibraryAccordionRow(
            title: "Stats",
            symbol: "chart.bar",
            token: .pink,
            count: nil,
            isExpanded: expansionBinding(for: "stats")
        ) {
            ProgressStatTilesRow(summary: statsSummary)
        }
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

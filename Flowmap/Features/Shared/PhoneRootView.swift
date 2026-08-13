#if !os(macOS)
import SwiftData
import SwiftUI

/// The iPhone shell: a real, native tab bar with three destinations —
/// Plan, Focus, Settings — restyled with `FlowTheme`.
///
/// Decision 1b (2026-07-29) reverses the `≡` glass menu subtask 37 built.
/// That menu still switched tabs through a hidden 7-tag `TabView`, and iOS
/// collapses any `TabView` past 5 tags into a stock system "More" list
/// regardless of `.toolbar(.hidden, for: .tabBar)` — confirmed the hard way
/// on Stats/Settings. Capping this `TabView` at exactly 5 tags and letting it
/// draw its own chrome (instead of hiding it behind a custom overlay) avoids
/// the bug and gives a genuinely native tab bar, not a web-style hamburger.
///
/// Decision 40/41 (2026-08-10) drop this to three tags: Map and Calendar
/// left the bar. Map + Today folded into Plan as its own segment (the Map
/// tab is gone); Calendar is now a button on Plan's own nav bar instead of
/// a tab. Founder, verbatim and angry: "TODAY should [come] FROM MAPS, only
/// ONE TODAY... Map tab should be gone, content inside moved to plan tab."
struct PhoneRootView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var allTasks: [FlowTask]

    // The mockup's launch screen is Focus (`00-initial.png`). The focused
    // hierarchy harness opens Plan directly so screenshot evidence does not
    // depend on iOS 26 tab-hit-test timing; production still always opens Focus.
    @State private var tab: DeepLink = ProcessInfo.processInfo.arguments.contains("-flowmapHarnessHierarchy")
        ? .library
        : .focus
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
                .tabItem { Label("Plan", systemImage: "list.bullet") }
                .tag(DeepLink.library)
                .badge(inboxCount > 0 ? "\(inboxCount)" : nil)

                NavigationStack {
                    FocusScreen()
                }
                .tabItem { Label("Focus", systemImage: "timer") }
                .tag(DeepLink.focus)

                NavigationStack {
                    SettingsScreen()
                }
                // iOS substitutes a symbol's `.fill` variant in a tab item when
                // one exists. `list.bullet` and `timer` have none, so they stay
                // hairline while `gearshape` was swapped for `gearshape.fill`
                // and read far heavier than its neighbours. `slider.horizontal.3`
                // has no filled variant, so all three strokes now match.
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(DeepLink.settings)
            }
            // The bar carries Flowmap only through its tint. Its background is
            // the system's own — pinning `.ultraThinMaterial` visible fought
            // the platform's adaptive bar material, which the HIG reserves to
            // itself ("bars are an overlay layer, never custom chrome"), and
            // froze the bar opaque where it should thin over scrolling
            // content. Task 102.
            .tint(FlowTheme.accent)
            .background {
                if #available(iOS 26.0, *) {
                    // The detached capture control owns the trailing lane. Move
                    // only UIKit's native tab-bar surface left so the bottom
                    // reads as one horizontal group: [tabs] [capture]. The
                    // TabView content and its safe-area layout stay untouched.
                    NativeTabBarHorizontalShift(distance: FlowSpacing.xl)
                        .frame(width: 0, height: 0)
                }
            }
        }
        // One capture control in one stable place on every destination.
        // Focus-created tasks must use the same TaskDraft path as Plan and
        // Map; hiding this control there made that journey impossible.
        .overlay(alignment: .bottomTrailing) {
            positionedCaptureAssistantOrb
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
                // Task composition needs the full canvas: the medium detent
                // opened behind the keyboard and cropped the worth control on
                // first contact. Keep the native sheet and its dismissal cue,
                // but start at the compose-sized detent used by Mail/Messages.
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
        // Decision 40/41: `.map`/`.calendar` are no longer tabs on iPhone, but
        // nothing in the app posts those destinations as a deep link today
        // (grepped every `DeepLinkRequest(destination:` call site), so the
        // `default` branch below staying a no-op-on-phone is dead code, not a
        // live gap. `.today` keeps its existing sheet path rather than
        // threading a `PlanSegment` binding down through `LibraryView` —
        // both render the identical `TodayView`, so behaviour is preserved.
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
            shellStroke: FlowTheme.separator(scheme),
            // Tiimo's branded face is approximately 70% of the detached
            // circle. Keep the outer shell equal to the tab pill while the
            // accent face stays inside it as a distinct Liquid Glass plate.
            faceScale: 0.70,
            iconScale: 0.32,
            accessibilityLabel: "New task, project or initiative",
            assistantAction: { showingAssistantDock = true },
            hapticsEnabled: flow?.settings.focusHapticsEnabled ?? false
        ) {
            showingCapture = true
        }
    }

    @ViewBuilder
    private var positionedCaptureAssistantOrb: some View {
        if #available(iOS 26.0, *) {
            captureAssistantOrb
                // Match the floating bar's visual height and baseline while
                // leaving the outer glass shell fully visible at the edge.
                .padding(.trailing, FlowSpacing.xl)
                .padding(.bottom, FlowSpacing.s)
                .offset(y: FlowSpacing.bottomControlBaselineOffset)
        } else {
            // The legacy full-width bar has no detached trailing slot.
            captureAssistantOrb
                .padding(.trailing, FlowSpacing.screen)
                .padding(.bottom, FlowSpacing.floatingControlsInset)
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

/// Applies a visual-only translation to SwiftUI's underlying native tab bar.
/// Keeping the adjustment on `UITabBar` preserves native tab selection,
/// badges, accessibility, Liquid Glass, and the content's full-width layout.
@available(iOS 26.0, *)
private struct NativeTabBarHorizontalShift: UIViewRepresentable {
    let distance: CGFloat

    func makeUIView(context: Context) -> ProbeView {
        ProbeView(distance: distance)
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        view.distance = distance
        view.applyShift()
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: Void) {
        view.resetShift()
    }

    final class ProbeView: UIView {
        var distance: CGFloat

        init(distance: CGFloat) {
            self.distance = distance
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.applyShift()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyShift()
        }

        func applyShift() {
            guard let tabBar = resolvedTabBarController()?.tabBar else { return }
            tabBar.transform = .identity
            let shift = CGAffineTransform(
                translationX: -distance,
                y: 0
            )
            tabBar.subviews.forEach { $0.transform = shift }
        }

        func resetShift() {
            guard let tabBar = resolvedTabBarController()?.tabBar else { return }
            tabBar.transform = .identity
            tabBar.subviews.forEach { $0.transform = .identity }
        }

        private func resolvedTabBarController() -> UITabBarController? {
            guard let root = window?.rootViewController else { return nil }
            return findTabBarController(in: root)
        }

        private func findTabBarController(in controller: UIViewController) -> UITabBarController? {
            if let tabBarController = controller as? UITabBarController {
                return tabBarController
            }
            if let presented = controller.presentedViewController,
               let match = findTabBarController(in: presented) {
                return match
            }
            for child in controller.children {
                if let match = findTabBarController(in: child) {
                    return match
                }
            }
            return nil
        }
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
    @Query(sort: \Initiative.sortOrder) private var initiatives: [Initiative]
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
    /// The Plan tab's fixed top-level page (decision 40). Replaces the old
    /// task-page chips and the "Smart task views" menu.
    @State private var planSegment: PlanSegment = .inbox
    @Namespace private var planSegmentSelection
    /// Decision 41: Calendar is a Plan nav-bar button, not a tab — pushes the
    /// same root the old Calendar tab used, on Plan's own NavigationStack.
    @State private var pushCalendar = false
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
    @State private var pendingProjectDelete: Project?
    /// Drives the project push explicitly. The accordion cannot use
    /// `NavigationLink(value:)`: its expanded rows all share ONE `List` cell,
    /// and every link in that cell activates together — one tap on any project
    /// pushed all five and stranded the user in the last one.
    @State private var selectedProject: Project?
    @State private var editingInitiative: Initiative?

    /// The Plan tab's three fixed top-level pages (decision 40, 2026-08-10).
    /// Replaces the old task-page chips and "Smart task views" menu, which
    /// the founder called "so tiny to touch... very claustrophobic". One
    /// Today (folds Map + Today's old Today pane into Plan), one Map, Inbox
    /// unchanged. No menu, no paging — all three always on screen at once.
    enum PlanSegment: String, CaseIterable, Identifiable {
        case today, inbox, map

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: "Today"
            case .inbox: "Inbox"
            case .map: "Map"
            }
        }
    }

    /// Ordered peers in the Plan tab's task surface. Inbox is deliberately
    /// page zero because it is the capture-to-triage entry point; completed is
    /// last because it is history, not the next action.
    ///
    /// Retained purely for `taskPageContent`/`smartTaskPages`/
    /// `taskPageSelection` below, which `Tests/LibraryAccordionTests.swift`
    /// covers directly and Slice 2's Browse rows reuse — the pager UI that
    /// used to switch over this enum is gone (decision 40).
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
        VStack(spacing: 0) {
            planSegmentControl
            planSurface
        }
        .background(FlowTheme.background(scheme).ignoresSafeArea())
            // Named for the tab that reaches it (decision 1b), not for the type —
            // a screen titled "Library" under a tab labelled "Plan" reads as two
            // different places.
            .flowScreenTitle("Plan")
            #if os(iOS)
            // Switching from the scrolling Inbox to the geometry-backed Map
            // can inherit a collapsed/transparent navigation-bar state from
            // SwiftUI. Plan always owns this bar, so restate its visibility
            // at the owning screen instead of letting a child surface decide.
            .toolbar(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSearch = true } label: { Image(systemName: "magnifyingglass") }
                        .accessibilityLabel("Search")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { pushStats = true } label: { Image(systemName: "chart.bar") }
                        .accessibilityLabel("Stats")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { pushCalendar = true } label: { Image(systemName: "calendar") }
                        .accessibilityLabel("Calendar")
                }
            }
            .navigationDestination(isPresented: $pushStats) {
                ProgressScreen()
            }
            .navigationDestination(isPresented: $pushCalendar) {
                CalendarRootView()
            }
            .navigationDestination(for: Project.self) { project in
                ProjectDetailView(project: project)
            }
            .navigationDestination(item: $selectedProject) { project in
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
            .fullScreenCover(isPresented: $showingDuel) {
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
            .flowDeleteConfirmation(
                isPresented: projectDeleteBinding,
                itemTitle: pendingProjectDelete?.title ?? "",
                hasChildren: !(pendingProjectDelete?.tasks ?? []).isEmpty,
                onDelete: deletePendingProject
            )
            .sheet(item: $editingInitiative) { InitiativeEditSheet(initiative: $0) }
    }

    /// One fixed 3-way control replaces the old task-page chips and the
    /// "Smart task views" menu (decision 40). One implementation serves every
    /// supported iOS version: native Button interaction stays stable while the
    /// extracted OpenAI Apps control language supplies compact labels and a
    /// selected underline.
    @ViewBuilder
    private var planSegmentControl: some View {
        tokenPlanSegmentControl
        .padding(.horizontal, FlowSpacing.screen)
        .padding(.top, FlowSpacing.s)
        .padding(.bottom, FlowSpacing.xs)
        .sensoryFeedback(.selection, trigger: planSegment)
    }

    private var tokenPlanSegmentControl: some View {
        HStack(spacing: FlowSpacing.xxs) {
            ForEach(PlanSegment.allCases) { segment in
                let isSelected = planSegment == segment

                Button {
                    selectPlanSegment(segment)
                } label: {
                    VStack(spacing: 0) {
                        Text(segment.title)
                            .font(FlowFont.caption.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(
                                isSelected
                                    ? FlowTheme.accentText(scheme)
                                    : FlowTheme.secondaryText(scheme)
                            )
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 40)

                        Rectangle()
                            .fill(isSelected ? FlowTheme.accent : .clear)
                            .frame(height: FlowSpacing.xs)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlanSegmentPressStyle())
                .accessibilityIdentifier("plan-segment-\(segment.rawValue)")
                .accessibilityLabel(segment.title)
                .accessibilityHint("Shows the \(segment.title.lowercased()) view")
                .accessibilityValue(isSelected ? "Selected" : "")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, FlowSpacing.s)
        .background(
            Capsule(style: .continuous)
                .fill(FlowTheme.glass(scheme))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(FlowTheme.glassBorder(scheme), lineWidth: 1)
                }
        )
        .frame(minHeight: 52)
    }

    private func selectPlanSegment(_ segment: PlanSegment) {
        guard planSegment != segment else { return }
        if reduceMotion {
            planSegment = segment
        } else {
            withAnimation(FlowMotion.tap) {
                planSegment = segment
            }
        }
    }

    private struct PlanSegmentPressStyle: ButtonStyle {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.72 : 1)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(reduceMotion ? nil : FlowMotion.tap, value: configuration.isPressed)
        }
    }

    /// Only the active segment is ever in the hierarchy — a `ZStack` with
    /// `if`/`else`, not `Group { switch }`, which has silently broken tab
    /// switching elsewhere in this app when paired with a `.toolbar`.
    @ViewBuilder
    private var planSurface: some View {
        ZStack {
            if planSegment == .today {
                TodayView()
            } else if planSegment == .inbox {
                planList(for: .inbox)
            } else {
                AutoMapScreen(scope: .day, showsScreenTitle: false, includesBacklog: true)
            }
        }
        // A `List` claims the height on its own; the map's empty state does
        // not, and without this the whole `VStack` shrank to its content and
        // centred — dragging the segment control down off the header line.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func planList(for page: TaskPage) -> some View {
        List {
            directListRoute

            taskPageSection(page)

            Section(header: sectionHeader("BUILD")) {
                projectsAccordion
                initiativesAccordion
                notesAccordion
            }
            .listRowBackground(FlowTheme.surface(scheme))

            browseSection
        }
        // Closes the dead vertical gaps between Personal, Inbox, and BUILD
        // (fix 2, board task 138) — the default `List` section spacing on
        // grouped style read as blank cream between cards. `.compact` is the
        // built-in preset for exactly this, not a new spacing constant.
        .listSectionSpacing(.compact)
        // This must live on the actual List. Applying an inset to the
        // surrounding NavigationStack is accepted but reserves no List space.
        // Safe-area padding shrinks the visible viewport, so a trailing count
        // can never sit behind the fixed capture control even mid-scroll.
        .safeAreaPadding(.bottom, FlowSpacing.floatingControlsInset)
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

    /// Keep one direct list route for existing workflows (decision 40's
    /// "Lists strip", unchanged on the Inbox segment). Hosting this as a native
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
                .buttonStyle(FlowNavigationRowPressStyle())
            }
            .listRowBackground(FlowTheme.surface(scheme))
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

    // MARK: - Browse (decision 40, Slice 2)

    /// Replaces the dead "Smart task views" menu: one large row per smart
    /// view, always visible, no menu to open first. Today is excluded — it
    /// is its own Plan segment now, not a Browse destination. Reuses
    /// `TaskListScreen`'s existing smart-view rendering; no new matching
    /// logic here.
    static let browsePages: [TaskPage] = [.upcoming, .anytime, .allTasks, .completed]

    private var browseSection: some View {
        Section(header: CompactSectionHeader(title: "Browse")) {
            ForEach(Self.browsePages) { page in
                browseRow(page)
            }
        }
        .listRowBackground(FlowTheme.surface(scheme))
    }

    @ViewBuilder
    private func browseRow(_ page: TaskPage) -> some View {
        if let view = page.smartView {
            let count = Self.taskPageContent(for: view, in: allTasks, now: flow?.now ?? Date()).count
            NavigationLink {
                TaskListScreen(source: .smartView(view))
            } label: {
                HStack(spacing: FlowSpacing.m) {
                    FlowNavigationGlyph(systemImage: view.symbolName, token: view.colour)

                    Text(page.title)
                        .font(FlowFont.body.weight(.semibold))
                        .foregroundStyle(FlowTheme.primaryText(scheme))

                    Spacer(minLength: FlowSpacing.s)

                    Text("\(count)")
                        .font(FlowFont.caption.weight(.semibold))
                        .foregroundStyle(FlowTheme.tertiaryText(scheme))
                }
                .padding(.vertical, FlowSpacing.xs)
                .frame(minHeight: 44)
            }
            .accessibilityLabel("\(page.title), \(count)")
            .buttonStyle(FlowNavigationRowPressStyle())
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
                    Button {
                        selectedProject = project
                    } label: {
                        ProjectRow(project: project)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
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

    private var initiativesAccordion: some View {
        LibraryAccordionRow(
            title: "Initiatives",
            symbol: "scope",
            token: .violet,
            count: initiatives.count,
            isExpanded: expansionBinding(for: "initiatives")
        ) {
            if initiatives.isEmpty {
                emptyRow("No initiatives yet. Group projects under one to see them here.")
            } else {
                ForEach(initiatives) { initiative in
                    Button {
                        editingInitiative = initiative
                    } label: {
                        HStack(spacing: FlowSpacing.m) {
                            // An initiative's colour is user-chosen identity, so
                            // it stays on the glyph — but no filled tile behind
                            // it (fix 1, board task 138). `.base`, not `.onSoft`:
                            // `onSoft` is white for several tokens and is only
                            // legible sitting on that token's own tinted fill.
                            Image(systemName: initiative.iconName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(initiative.colour.base)
                                .frame(width: 36, height: 36)

                            Text(initiative.title)
                                .font(FlowFont.cardTitle)
                                .foregroundStyle(FlowTheme.primaryText(scheme))

                            Spacer(minLength: FlowSpacing.s)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
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
            // A user list's colour is its identity, so it stays on the glyph —
            // no filled tile behind it (fix 1, board task 138). `.base`, not
            // `.onSoft`: `onSoft` is white for several tokens and is only
            // legible sitting on that token's own tinted fill.
            FlowNavigationGlyph(systemImage: symbol, token: token)
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

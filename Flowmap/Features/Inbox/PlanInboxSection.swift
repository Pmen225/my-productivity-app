import SwiftData
import SwiftUI

/// The Plan tab's inbox block: everything captured that has not been given a
/// slot yet, the capacity left to give it, and the two ways of giving it one.
///
/// Sits above the Plan tab's own library sections rather than being its own
/// screen — triage and the rest of the plan belong on one page, which is what
/// the mock does with `planBodyEl` followed by `libBodyEl`.
struct PlanInboxSection: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context

    @Query private var allTasks: [FlowTask]

    /// Which row has been tapped open. One at a time: two editors expanded at
    /// once is a list nobody can read.
    @State private var editingTaskID: UUID?
    /// Both duel and plan-preview presentation are driven from here but
    /// HOSTED by `LibraryView`, which owns the `.sheet` modifiers. A `.sheet`
    /// attached to this view's own `Section` never presents: `Section` is
    /// only one of several children inside `LibraryView`'s outer `List`, and
    /// SwiftUI does not reliably host a presentation controller for a
    /// modifier attached that deep inside another List's content — the
    /// duel's own entry point silently stopped opening the moment T6 moved
    /// it from `TaskListScreen` (where `.sheet` sat on the screen's own
    /// top-level `List`) into this nested `Section`. Bindings, not local
    /// `@State`, so the parent's `.sheet` toggles the same flag this button
    /// sets.
    @Binding var showingDuel: Bool
    @Binding var showingPlanPreview: Bool
    @Binding var planProposal: PlanProposal?
    /// The paged Plan surface supplies its own title strip. Keeping the
    /// existing section header optional lets Inbox remain the same triage
    /// implementation without displaying its title twice.
    let showsHeader: Bool

    init(
        showingDuel: Binding<Bool>,
        showingPlanPreview: Binding<Bool>,
        planProposal: Binding<PlanProposal?>,
        showsHeader: Bool = true
    ) {
        _showingDuel = showingDuel
        _showingPlanPreview = showingPlanPreview
        _planProposal = planProposal
        self.showsHeader = showsHeader
    }

    private var inbox: [FlowTask] {
        SmartView.inbox.matches(allTasks)
    }

    struct HierarchyEntry: Identifiable {
        let task: FlowTask
        let depth: Int
        var id: UUID { task.id }
    }

    /// A filtered child whose parent lives on another page becomes a display
    /// root here. This keeps every matching task visible exactly once while
    /// still showing the relationship whenever both ends are in Inbox.
    private var hierarchyRows: [HierarchyEntry] {
        Self.hierarchyRows(for: inbox)
    }

    /// Produces a stable pre-order hierarchy for the visual list. Keeping the
    /// grouping rule separate from SwiftUI makes the parent/dependency contract
    /// directly testable: every visible task appears once, immediately after
    /// its visible parent, while an off-page parent never hides its child.
    static func hierarchyRows(for tasks: [FlowTask]) -> [HierarchyEntry] {
        let visibleIDs = Set(tasks.map(\.id))
        let roots = tasks.filter { task in
            guard let parentID = task.parentTask?.id else { return true }
            return !visibleIDs.contains(parentID)
        }
        var result: [HierarchyEntry] = []
        var visited: Set<UUID> = []

        func append(_ task: FlowTask, depth: Int) {
            guard visibleIDs.contains(task.id), visited.insert(task.id).inserted else { return }
            result.append(HierarchyEntry(task: task, depth: min(depth, FlowTask.maximumHierarchyLevels - 1)))
            for child in task.orderedChildTasks where visibleIDs.contains(child.id) {
                append(child, depth: depth + 1)
            }
        }

        for root in roots { append(root, depth: 0) }
        for task in tasks where !visited.contains(task.id) { append(task, depth: 0) }
        return result
    }

    /// Card joining follows the flattened pre-order list: a root whose next
    /// row is deeper starts a group; every dependency continues that group;
    /// the dependency before the next root closes it.
    static func hierarchyPosition(
        at index: Int,
        in rows: [HierarchyEntry]
    ) -> TaskRowView.HierarchyPosition {
        guard rows.indices.contains(index) else { return .standalone }
        let entry = rows[index]
        let nextDepth = rows.indices.contains(index + 1) ? rows[index + 1].depth : nil
        if entry.depth == 0 {
            return (nextDepth ?? 0) > 0 ? .groupRoot : .standalone
        }
        return nextDepth == nil || nextDepth == 0 ? .groupEnd : .groupMiddle
    }

    /// The duel's own set — today's open tasks (flagged, due, or scheduled
    /// today), never the inbox. Planning must not require the game, so the
    /// game is offered as a way to order what's already lined up for today,
    /// not a gate in front of triage (state/specs/cognitive-profile.md,
    /// "product thesis").
    private var today: [FlowTask] {
        SmartView.today.matches(allTasks, now: flow?.now ?? Date())
    }

    var body: some View {
        Section {
            if inbox.isEmpty {
                // An empty store has planned nothing, so claiming otherwise on
                // the screen a new user is sent to reads as a dead end.
                Text(allTasks.isEmpty
                     ? "Nothing captured yet — tap + to add your first task."
                     : "Inbox zero — everything is planned.")
                    .font(FlowFont.secondary)
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(Array(hierarchyRows.enumerated()), id: \.element.id) { index, entry in
                    row(
                        entry.task,
                        depth: entry.depth,
                        position: Self.hierarchyPosition(at: index, in: hierarchyRows)
                    )
                }
                actions
            }
        } header: {
            if showsHeader {
                header
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
            CompactSectionHeader(title: "Inbox", count: inbox.count)
            Text(capacityLine)
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .textCase(nil)
        }
    }

    /// `4h 30m free before 21:00 · plan places tasks in the earliest slots`.
    private var capacityLine: String {
        guard let flow else { return "" }
        let free = flow.scheduling().freeMinutesRemainingToday(now: flow.now)
        let until = flow.settings.workdayEndLabel
        return "\(DurationFormatter.compact(minutes: free)) free before \(until)"
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(
        _ task: FlowTask,
        depth: Int,
        position: TaskRowView.HierarchyPosition
    ) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.m) {
            TaskRowView(
                task: task,
                onEdit: { toggleEditor(for: task) },
                hierarchyPosition: position,
                hierarchyDepth: depth
            )
            if editingTaskID == task.id {
                editor(task)
            }
        }
        .listRowInsets(EdgeInsets(
            top: depth == 0 ? FlowSpacing.xs : 0,
            leading: FlowSpacing.screen,
            bottom: position == .groupEnd || position == .standalone
                ? FlowSpacing.xs
                : 0,
            trailing: FlowSpacing.screen
        ))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityHint(
            depth > 0
                ? "Dependency of \(task.parentTask?.title ?? "its parent"). Shows task editing controls."
                : "Shows task editing controls"
        )
        .accessibilityIdentifier(depth > 0 ? "Dependency task: \(task.title)" : "Task: \(task.title)")
        .accessibilityAction(named: "Edit task") { toggleEditor(for: task) }
        #if os(iOS)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                addToToday(task)
            } label: {
                Label("Today", systemImage: SmartView.today.symbolName)
            }
            .tint(SmartView.today.colour.base)
        }
        #endif
    }

    /// The mock's in-row editor: identity, rename, re-time, and place — the
    /// things worth doing during triage without leaving the Plan list.
    private func editor(_ task: FlowTask) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.m) {
            HStack(alignment: .center, spacing: FlowSpacing.m) {
                FlowTaskIconPicker(selection: iconSelection(for: task), tint: task.colour)
                TextField("Task name", text: Binding(get: { task.title }, set: { task.title = $0 }))
                    .font(FlowFont.body)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Rename task")
            }
            // Label above, not beside: the wheel is a full spinning picker
            // now, and a tall control next to a one-line label reads as two
            // competing left edges.
            VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                Text("Duration")
                    .font(FlowFont.body)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                FlowDurationWheel(
                    minutes: Binding(
                        get: { task.estimatedMinutes },
                        set: { task.estimatedMinutes = $0 }
                    )
                )
            }
            SecondaryActionButton("Plan now — earliest free slot", systemImage: "calendar.badge.clock") {
                planNow(task)
            }
        }
        .padding(.leading, FlowSpacing.xl)
    }

    private func iconSelection(for task: FlowTask) -> Binding<String> {
        Binding(
            get: { task.iconName.isEmpty ? "circle" : task.iconName },
            set: { symbol in
                task.iconName = symbol
                task.touch()
                try? context.save()
            }
        )
    }

    private var actions: some View {
        // The duel only has something to say once there are two of today's
        // tasks to compare — the same rule `TaskListScreen` used before Plan
        // existed, now over today's set rather than the inbox.
        let duelAvailable = PrioritiseDuel.isAvailable(for: today.map(\.id))
        // Primary act first, optional game second, no caption — the founder's
        // rule zero (state/specs/space-notes.md): a control that needs a
        // caption is the wrong control, and the primary action leads.
        return VStack(spacing: FlowSpacing.s) {
            // Decision 12: the whole day is previewed before it moves.
            PrimaryActionButton("Start planning") {
                planProposal = flow?.planToday(replanExisting: false)
                showingPlanPreview = true
            }
            if duelAvailable {
                SecondaryActionButton("Prioritise today — play the game", systemImage: "play.fill") {
                    showingDuel = true
                }
            }
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Actions

    private func toggleEditor(for task: FlowTask) {
        editingTaskID = editingTaskID == task.id ? nil : task.id
    }

    private func planNow(_ task: FlowTask) {
        guard let flow else { return }
        if flow.scheduling().planNow(task: task, now: flow.now) != nil {
            flow.moments.show(.hud("\(task.title) planned"))
            editingTaskID = nil
        } else {
            flow.moments.show(.hud("No free slots left today"))
        }
    }

    private func addToToday(_ task: FlowTask) {
        Self.moveToToday(task, in: context)
        flow?.moments.show(.hud("\(task.title) added to Today"))
        editingTaskID = nil
    }

    /// Sets exactly what `SmartView.today` reads — `isFlaggedForToday`, the
    /// same flag `QuickCapture`'s `flagForTodayIfUndated` already sets at
    /// creation time. `static`, not `private`, so it is directly unit-testable
    /// without instantiating the view (see `TaskRowView.duplicate`).
    static func moveToToday(_ task: FlowTask, in context: ModelContext) {
        task.isFlaggedForToday = true
        try? context.save()
    }
}

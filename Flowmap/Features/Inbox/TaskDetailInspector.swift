import SwiftData
import SwiftUI

/// The full editor for one task: description, duration, its schedule
/// (`TaskSegment`s), priority, project, list, subtasks, and its linked map
/// node and note. Every field writes straight back to the model — there is
/// no separate draft state to lose.
///
/// This is also the ONE task-creation card (one-task-card spec, 2026-08-10):
/// the founder rejected having a separate, differently designed sheet for
/// creating a task, so `QuickCaptureView` opens this same `body` in a second,
/// draft-backed mode rather than a second view. See `init(draftSeed:kindSelection:)`.
public struct TaskDetailInspector: View {
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @Query(sort: \Project.sortOrder) private var projects: [Project]
    @Query(sort: \FlowTask.createdAt) private var tasks: [FlowTask]

    @Bindable private var task: FlowTask

    @State private var newSubtaskTitle = ""
    @State private var showAddSegment = false
    @State private var newSegmentStart = Date()
    @State private var showWorthWheel = false

    /// Creation-mode only. `nil` in edit mode, where the body is otherwise
    /// identical.
    private let isCreating: Bool
    private let seed: TaskDraft.Seed?
    private let kindSelection: Binding<FlowCreateKind>?

    @FocusState private var titleFieldFocused: Bool
    @State private var didInsertDraft = false
    // Guards the draft's exit rule from running twice: Cancel/Done already
    // resolve the draft before dismissing, so the `.onDisappear` that also
    // catches a swipe-to-dismiss must not resolve it a second time.
    @State private var didResolveDraft = false

    /// EDIT mode: writes straight through to an existing task. No draft, no
    /// Cancel/Done, no kind menu — unchanged from before the fused card.
    public init(task: FlowTask) {
        self._task = Bindable(task)
        self.isCreating = false
        self.seed = nil
        self.kindSelection = nil
    }

    /// CREATE mode: the fused task card's draft lifecycle. `draftTask` is
    /// owned by the presenting `QuickCaptureView` as `@State` — a plain
    /// `@Bindable` here would mint a FRESH task on every struct re-init,
    /// orphaning the inserted draft and losing the typed title. It is not
    /// yet inserted into `modelContext`; that happens on first appear, once
    /// `flow` is available to resolve the default duration and the
    /// due-date/"flag for today" seeding (`SchedulingService.dueDateForNewTask`).
    /// `kindSelection` lets the founder switch to Project/Initiative from
    /// this same card via `FlowKindMenu`.
    public init(draftTask: FlowTask, draftSeed: TaskDraft.Seed, kindSelection: Binding<FlowCreateKind>) {
        self._task = Bindable(draftTask)
        self.isCreating = true
        self.seed = draftSeed
        self.kindSelection = kindSelection
    }

    public var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: FlowSpacing.m) {
                    FlowTaskIconPicker(selection: iconSelection, tint: task.colour)
                    taskTitleField
                }
            }
            .listRowBackground(FlowTheme.surface(scheme))

            Section {
                HStack(spacing: FlowSpacing.s) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(FlowTheme.tertiaryText(scheme))
                        .accessibilityHidden(true)
                    TextField("Notes (optional)", text: $task.details, axis: .vertical)
                        .font(FlowFont.body)
                        .lineLimit(1...3)
                        .accessibilityLabel("Notes, optional")
                }
            }
            .listRowBackground(FlowTheme.surface(scheme))

            Section {
                FlowColourPicker(selection: Binding(
                    get: { task.colour },
                    set: { task.colourToken = $0.rawValue; task.touch() }
                ), scrollable: true)
            }
            .listRowInsets(EdgeInsets(top: FlowSpacing.xs, leading: FlowSpacing.m, bottom: FlowSpacing.xs, trailing: FlowSpacing.m))

            worthSection

            Section {
                FlowFieldRow("List", symbol: "tray", symbolColour: .green) {
                    Menu {
                        Picker("List", selection: listSelection) {
                            Text("Inbox").tag(UUID?.none)
                            ForEach(lists.filter { !$0.isArchived }) { list in
                                Text(list.name).tag(Optional(list.id))
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        FlowFieldChip(task.list?.name ?? "Inbox")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: FlowSpacing.xxs, leading: 0, bottom: FlowSpacing.xxs, trailing: 0))
                .listRowSeparator(.hidden)

                FlowFieldRow("Project", symbol: "folder", symbolColour: .blue) {
                    Menu {
                        Picker("Project", selection: projectSelection) {
                            Text("None").tag(UUID?.none)
                            ForEach(projects) { project in
                                Text(project.title).tag(Optional(project.id))
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        FlowFieldChip(task.project?.title ?? "None")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: FlowSpacing.xxs, leading: 0, bottom: FlowSpacing.xxs, trailing: 0))
                .listRowSeparator(.hidden)

                FlowFieldRow("Parent", symbol: "arrow.turn.down.right", symbolColour: .violet) {
                    Menu {
                        Picker("Parent task", selection: parentSelection) {
                            Text("None").tag(UUID?.none)
                            ForEach(parentCandidates) { candidate in
                                Label(candidate.title, systemImage: candidate.iconName)
                                    .tag(Optional(candidate.id))
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        FlowFieldChip(task.parentTask?.title ?? "None")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: FlowSpacing.xxs, leading: 0, bottom: FlowSpacing.xxs, trailing: 0))
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("task-parent-picker")

                FlowFieldRow("Repeat", symbol: "repeat", symbolColour: .peach) {
                    Menu {
                        Picker("Repeat", selection: $task.recurrence) {
                            ForEach(RecurrenceFrequency.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        FlowFieldChip(task.recurrence.displayName)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: FlowSpacing.xxs, leading: 0, bottom: FlowSpacing.xxs, trailing: 0))
                .listRowSeparator(.hidden)
            }

            scheduleSection

            Section {
                Picker("Priority", selection: $task.priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Label(priority.displayName, systemImage: priority.symbolName).tag(priority)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Priority")
            }
            .listRowBackground(FlowTheme.surface(scheme))

            subtasksSection
            if !isCreating || task.mapNode != nil {
                linkedMapNodeSection
            }
            if !isCreating || task.notes?.isEmpty == false {
                linkedNoteSection
            }
        }
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .listSectionSpacing(.compact)
        #endif
        .contentMargins(.top, FlowSpacing.xs, for: .scrollContent)
        // Keep ordinary vertical scrolling available while the title keyboard
        // is up. The worth wheel now expands only after a deliberate tap.
        .scrollDismissesKeyboard(.interactively)
        .background(FlowTheme.background(scheme).ignoresSafeArea())
        .navigationTitle(isCreating ? "" : "Task")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .presentationCornerRadius(FlowRadius.large)
        .toolbar { creationToolbar }
        .onAppear(perform: insertDraftIfNeeded)
        .onDisappear(perform: resolveDraftOnDismiss)
    }

    // MARK: - Task identity

    /// Xcode 27's bordered text input participates in the current system
    /// styling. Earlier SDKs keep the existing unbordered form row.
    @ViewBuilder
    private var taskTitleField: some View {
        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
            taskTitleFieldBase
                .textFieldStyle(.bordered)
                .textInputBorderShape(.roundedRectangle)
        } else {
            taskTitleFieldBase
                .padding(.vertical, FlowSpacing.s)
        }
        #else
        taskTitleFieldBase
            .padding(.vertical, FlowSpacing.s)
        #endif
    }

    private var taskTitleFieldBase: some View {
        TextField("Task title", text: $task.title)
            .font(FlowFont.sectionTitle)
            .focused($titleFieldFocused)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityLabel("Task title")
    }

    // MARK: - Worth

    /// The Tiimo-style wheel stays available without owning the whole first
    /// viewport or intercepting an ordinary form scroll. Its compact summary
    /// is the default; expansion is a deliberate action.
    private var worthSection: some View {
        Section {
            Button(action: toggleWorthWheel) {
                FlowFieldRow("Worth", symbol: "clock", symbolColour: .violet) {
                    HStack(spacing: FlowSpacing.xs) {
                        FlowFieldChip(task.durationLabel)
                        Image(systemName: showWorthWheel ? "chevron.up" : "chevron.down")
                            .font(FlowFont.caption.weight(.semibold))
                            .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Worth")
            .accessibilityValue(task.durationAccessibilityLabel)
            .accessibilityHint(showWorthWheel ? "Hides the time wheel" : "Shows the time wheel")
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: FlowSpacing.xxs, leading: 0, bottom: FlowSpacing.xxs, trailing: 0))
            .listRowSeparator(.hidden)

            if showWorthWheel {
                FlowDurationWheel(minutes: $task.estimatedMinutes, accessibilityLabel: "Worth")
                    .listRowBackground(Color.clear)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func toggleWorthWheel() {
        if reduceMotion {
            showWorthWheel.toggle()
        } else {
            withAnimation(FlowMotion.expand) {
                showWorthWheel.toggle()
            }
        }
    }

    // MARK: - Draft lifecycle (creation mode)

    @ToolbarContentBuilder
    private var creationToolbar: some ToolbarContent {
        if isCreating {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: cancelDraft) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .flowHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            ToolbarItem(placement: .principal) {
                if let kindSelection {
                    FlowKindMenu(kind: kindSelection)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: finishDraft) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? FlowTheme.tertiaryText(scheme)
                                : FlowTheme.accent
                        )
                        .flowHitTarget()
                }
                .buttonStyle(.plain)
                // Deliberately never `.disabled` — an empty title must stay
                // tappable so Done can silently discard an abandoned draft,
                // exactly like Cancel. Only the colour signals "nothing to keep".
                .accessibilityLabel("Keep task")
            }
        }
    }

    /// Inserts the draft on first appear, once `flow` is available to resolve
    /// the default duration and the seeded due date / "flag for today"
    /// behaviour — the same resolution `QuickCaptureView.capture()` performs
    /// today, moved here since the draft is now inserted at open, not at
    /// confirmation.
    private func insertDraftIfNeeded() {
        guard isCreating, !didInsertDraft, let seed else { return }
        task.estimatedMinutes = flow?.settings.defaultTaskMinutes ?? 30
        titleFieldFocused = true

        let now = flow?.now ?? Date()
        let hasDue = seed.dueDate != nil
        let resolvedDueDate = flow?.scheduling().dueDateForNewTask(seed.dueDate, now: now)
        let shouldFlagToday = seed.flagForTodayIfUndated
            && !hasDue
            && !(flow?.scheduling().isPlanSealed(on: now) ?? false)

        didInsertDraft = TaskDraft.insert(
            task,
            context: context,
            seed: seed,
            projects: projects,
            lists: lists,
            tasks: tasks,
            resolvedDueDate: resolvedDueDate,
            shouldFlagToday: shouldFlagToday
        )
        guard didInsertDraft else {
            flow?.moments.show(.notif(
                title: "That parent is no longer available",
                subtitle: "Nothing was created."
            ))
            dismiss()
            return
        }
    }

    private func cancelDraft() {
        didResolveDraft = true
        TaskDraft.cancel(task, context: context)
        dismiss()
    }

    private func finishDraft() {
        didResolveDraft = true
        TaskDraft.finish(task, context: context)
        dismiss()
    }

    /// Catches every exit that isn't Cancel or Done — a swipe-to-dismiss, or
    /// the card being replaced when the founder switches kind away from
    /// Task. Same rule either way: keep a real title, discard an empty one.
    private func resolveDraftOnDismiss() {
        guard isCreating, didInsertDraft, !didResolveDraft else { return }
        didResolveDraft = true
        TaskDraft.finish(task, context: context)
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        Section {
            if task.allSegmentsOrdered.isEmpty && !showAddSegment {
                Button {
                    newSegmentStart = Date()
                    showAddSegment = true
                } label: {
                    FlowFieldRow("Schedule", symbol: "calendar", symbolColour: .pink) {
                        FlowFieldChip("Anytime")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Schedule a block")
                .accessibilityValue("Anytime")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: FlowSpacing.xxs, leading: 0, bottom: FlowSpacing.xxs, trailing: 0))
                .listRowSeparator(.hidden)
            } else {
                ForEach(task.allSegmentsOrdered) { segment in
                    segmentRow(segment)
                }
                .listRowBackground(FlowTheme.surface(scheme))
            }
            if showAddSegment {
                DatePicker("Start", selection: $newSegmentStart)
                    .listRowBackground(FlowTheme.surface(scheme))
                HStack {
                    Button("Cancel") { showAddSegment = false }
                    Spacer()
                    Button("Add") {
                        addSegment()
                    }
                }
                .listRowBackground(FlowTheme.surface(scheme))
            } else if !task.allSegmentsOrdered.isEmpty {
                Button {
                    newSegmentStart = Date()
                    showAddSegment = true
                } label: {
                    Label("Schedule a block", systemImage: "plus")
                }
                .listRowBackground(FlowTheme.surface(scheme))
            }
        } header: {
            if !task.allSegmentsOrdered.isEmpty || showAddSegment {
                FlowEyebrow("Schedule")
            }
        }
    }

    /// Places the new block and says so. A taken slot returns `nil`, silently,
    /// from `SchedulingService` — same success/refusal handling as
    /// `TaskRowView`'s scheduler popover, so the two surfaces agree.
    private func addSegment() {
        let now = flow?.now ?? Date()
        guard let segment = flow?.scheduling().schedule(task: task, at: newSegmentStart) else {
            flow?.moments.show(.notif(
                title: "That time is taken",
                subtitle: "Nothing was changed — pick another slot."
            ))
            return
        }
        showAddSegment = false
        let subtitle = Calendar.current.isDate(segment.startDate, inSameDayAs: now)
            ? "On today's timeline."
            : "Find it in Upcoming."
        flow?.moments.show(.notif(
            title: "Scheduled — \(ScheduleWording.startLabel(segment.startDate, now: now, calendar: .current))",
            subtitle: subtitle
        ))
    }

    private func segmentRow(_ segment: TaskSegment) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
                Text(DurationFormatter.timeRange(from: segment.startDate, to: segment.endDate))
                if let badge = segment.badgeText {
                    Text(badge).font(FlowFont.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            StatusIndicator(
                token: task.colour,
                symbolName: segmentSymbol(for: segment.state),
                label: segment.state.rawValue.capitalized
            )
        }
        .swipeActions {
            if segment.state.occupiesTimeline {
                Button(role: .destructive) {
                    flow?.scheduling().unschedule(segment: segment)
                } label: {
                    Label("Unschedule", systemImage: "calendar.badge.minus")
                }
            }
        }
    }

    private func segmentSymbol(for state: SegmentState) -> String {
        switch state {
        case .scheduled: return "clock"
        case .elapsed: return "hourglass"
        case .completed: return "checkmark"
        case .missed: return "exclamationmark.triangle"
        case .cancelled: return "xmark"
        }
    }

    // MARK: - Subtasks

    private var subtasksSection: some View {
        Section {
            ForEach(task.orderedSubtasks) { subtask in
                subtaskRow(subtask)
            }
            .onMove(perform: moveSubtasks)
            .onDelete(perform: deleteSubtasks)
            .listRowBackground(FlowTheme.surface(scheme))

            // Always available, session or not: the plan gate forces one subtask
            // before a task can start, and freezing the field afterwards capped
            // every started task at exactly that one step.
            HStack {
                TextField("Add a subtask", text: $newSubtaskTitle)
                    .onSubmit(addSubtask)
                Button(action: addSubtask) {
                    Image(systemName: "plus.circle.fill")
                        .flowHitTarget()
                }
                .buttonStyle(.plain)
                .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add subtask")
            }
            .listRowBackground(FlowTheme.surface(scheme))
        } header: {
            FlowEyebrow("Subtasks")
        }
    }

    private func subtaskRow(_ subtask: Subtask) -> some View {
        Button {
            flow?.gamification.toggleSubtask(subtask)
        } label: {
            HStack {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(subtask.isCompleted ? task.colour.base : .secondary)
                Text(subtask.title)
                    .strikethrough(subtask.isCompleted)
                    .foregroundStyle(subtask.isCompleted ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: FlowSpacing.s)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subtask.title)
        .accessibilityValue(subtask.isCompleted ? "Completed" : "Not completed")
        .accessibilityHint(subtask.isCompleted ? "Marks this subtask as incomplete" : "Marks this subtask as complete")
    }

    // MARK: - Linked map node / note

    private var linkedMapNodeSection: some View {
        Section {
            if let node = task.mapNode {
                HStack {
                    Image(systemName: node.iconName.isEmpty ? "circle.grid.2x2" : node.iconName)
                        .foregroundStyle(node.colour.base)
                    Text(node.title)
                    Spacer()
                    Button("Unlink", role: .destructive) {
                        task.mapNode = nil
                        try? context.save()
                    }
                }
                .listRowBackground(FlowTheme.surface(scheme))
            } else {
                Text("Not linked to a map node.")
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    .listRowBackground(FlowTheme.surface(scheme))
            }
        } header: {
            FlowEyebrow("Linked map node")
        }
    }

    private var linkedNoteSection: some View {
        Section {
            if let note = task.notes?.first {
                HStack {
                    Image(systemName: note.iconName)
                        .foregroundStyle(FlowTheme.accent)
                    Text(note.title.isEmpty ? "Untitled note" : note.title)
                    Spacer()
                    Button("Unlink", role: .destructive) {
                        note.task = nil
                        try? context.save()
                    }
                }
                .listRowBackground(FlowTheme.surface(scheme))
            } else {
                Text("Not linked to a note.")
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    .listRowBackground(FlowTheme.surface(scheme))
            }
        } header: {
            FlowEyebrow("Linked note")
        }
    }

    // MARK: - Picker bridges

    private var iconSelection: Binding<String> {
        Binding(
            get: { task.iconName.isEmpty ? "circle" : task.iconName },
            set: { symbol in
                task.iconName = symbol
                task.touch()
                try? context.save()
            }
        )
    }

    private var listSelection: Binding<UUID?> {
        Binding(
            get: { task.list?.id },
            set: { newID in
                task.list = lists.first { $0.id == newID }
                task.touch()
                try? context.save()
            }
        )
    }

    private var projectSelection: Binding<UUID?> {
        Binding(
            get: { task.project?.id },
            set: { newID in
                task.project = projects.first { $0.id == newID }
                task.touch()
                try? context.save()
            }
        )
    }

    private var parentCandidates: [FlowTask] {
        tasks.filter { candidate in
            candidate.id != task.id
                && (task.parentTask?.id == candidate.id || task.canAssignParent(candidate))
        }
    }

    private var parentSelection: Binding<UUID?> {
        Binding(
            get: { task.parentTask?.id },
            set: { newID in
                let parent = tasks.first { $0.id == newID }
                guard task.assignParent(parent) else { return }
                if let parent {
                    task.project = parent.project
                    task.list = parent.list
                    task.workspace = parent.workspace
                }
                task.touch()
                try? context.save()
            }
        )
    }

    // MARK: - Subtask mutation

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let subtask = Subtask(title: trimmed, sortOrder: task.orderedSubtasks.count, task: task)
        context.insert(subtask)
        try? context.save()
        newSubtaskTitle = ""
    }

    private func moveSubtasks(from offsets: IndexSet, to destination: Int) {
        var reordered = task.orderedSubtasks
        reordered.move(fromOffsets: offsets, toOffset: destination)
        for (index, subtask) in reordered.enumerated() { subtask.sortOrder = index }
        try? context.save()
    }

    private func deleteSubtasks(at offsets: IndexSet) {
        let ordered = task.orderedSubtasks
        for index in offsets { context.delete(ordered[index]) }
        try? context.save()
    }
}

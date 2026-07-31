import SwiftData
import SwiftUI

/// The full editor for one task: description, duration, its schedule
/// (`TaskSegment`s), priority, project, list, subtasks, and its linked map
/// node and note. Every field writes straight back to the model — there is
/// no separate draft state to lose.
public struct TaskDetailInspector: View {
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    @Bindable private var task: FlowTask

    @State private var newSubtaskTitle = ""
    @State private var showAddSegment = false
    @State private var newSegmentStart = Date()

    public init(task: FlowTask) {
        self._task = Bindable(task)
    }

    public var body: some View {
        Form {
            Section {
                TextField("Task title", text: $task.title)
                    .font(FlowFont.cardTitle)
            } header: {
                FlowEyebrow("Title")
            }

            Section {
                TextEditor(text: $task.details)
                    .frame(minHeight: 80)
            } header: {
                FlowEyebrow("Description")
            }

            Section {
                Stepper(
                    DurationFormatter.compact(minutes: task.estimatedMinutes),
                    value: $task.estimatedMinutes,
                    in: 5...480,
                    step: 5
                )
                .accessibilityLabel("Duration, \(task.durationAccessibilityLabel)")
            } header: {
                FlowEyebrow("Duration")
            }

            Section {
                Picker("Priority", selection: $task.priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in
                        Label(priority.displayName, systemImage: priority.symbolName).tag(priority)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                FlowEyebrow("Priority")
            }

            Section {
                Picker("List", selection: listSelection) {
                    Text("Inbox").tag(UUID?.none)
                    ForEach(lists.filter { !$0.isArchived }) { list in
                        Text(list.name).tag(Optional(list.id))
                    }
                }
            } header: {
                FlowEyebrow("List")
            }

            Section {
                Picker("Project", selection: projectSelection) {
                    Text("None").tag(UUID?.none)
                    ForEach(projects) { project in
                        Text(project.title).tag(Optional(project.id))
                    }
                }
            } header: {
                FlowEyebrow("Project")
            }

            Section {
                Picker("Repeat", selection: $task.recurrence) {
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            } header: {
                FlowEyebrow("Repeat")
            }

            scheduleSection
            subtasksSection
            linkedMapNodeSection
            linkedNoteSection
        }
        .navigationTitle("Task")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .presentationCornerRadius(FlowRadius.large)
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        Section {
            if task.allSegmentsOrdered.isEmpty {
                Text("Not scheduled yet.")
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            } else {
                ForEach(task.allSegmentsOrdered) { segment in
                    segmentRow(segment)
                }
            }
            if showAddSegment {
                DatePicker("Start", selection: $newSegmentStart)
                HStack {
                    Button("Cancel") { showAddSegment = false }
                    Spacer()
                    Button("Add") {
                        addSegment()
                    }
                }
            } else {
                Button {
                    newSegmentStart = Date()
                    showAddSegment = true
                } label: {
                    Label("Schedule a block", systemImage: "plus")
                }
            }
        } header: {
            FlowEyebrow("Schedule")
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

            HStack {
                TextField("Add a subtask", text: $newSubtaskTitle)
                    .onSubmit(addSubtask)
                Button(action: addSubtask) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add subtask")
            }
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
            }
        }
        .buttonStyle(.plain)
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
            } else {
                Text("Not linked to a map node.")
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
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
            } else {
                Text("Not linked to a note.")
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            }
        } header: {
            FlowEyebrow("Linked note")
        }
    }

    // MARK: - Picker bridges

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

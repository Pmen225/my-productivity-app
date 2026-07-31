import SwiftData
import SwiftUI

/// The compact creation form revealed after pressing the `+` control.
///
/// Styled after the design's "New" sheet: title, duration chips, a project
/// pill grid, date, subtasks and a note show by default — priority,
/// constraints, recurrence and splitting live under the collapsed `Advanced`
/// disclosure. There is never a permanent full-width "Add it to your list" row;
/// this view only exists on screen while its parent's `+` has been pressed.
public struct QuickAddTaskView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    private let smartView: SmartView?
    private let presetList: TaskList?
    private let presetProject: Project?
    private let onFinished: () -> Void

    @State private var title = ""
    @State private var minutes = 30
    @State private var hasDate = false
    @State private var date = Date()
    @State private var destination: Destination
    @State private var subtaskDraft = ""
    @State private var subtaskTitles: [String] = []
    @State private var note = ""

    @State private var isAdvancedExpanded = false
    @State private var priority: TaskPriority = .none
    @State private var hasEarliestStart = false
    @State private var earliestStart = Date()
    @State private var hasLatestFinish = false
    @State private var latestFinish = Date()
    @State private var preferredPeriod: DayPeriod = .anytime
    @State private var recurrence: RecurrenceFrequency = .none
    @State private var isSplittable = false
    @State private var minimumChunkMinutes = 15

    @FocusState private var titleFocused: Bool

    private let durationOptions = [15, 25, 30, 45, 60, 90]

    /// Where a new task lands: unlisted, a user list, or a project.
    private enum Destination: Hashable {
        case inbox
        case list(TaskList)
        case project(Project)
    }

    public init(
        smartView: SmartView? = nil,
        presetList: TaskList? = nil,
        presetProject: Project? = nil,
        onFinished: @escaping () -> Void = {}
    ) {
        self.smartView = smartView
        self.presetList = presetList
        self.presetProject = presetProject
        self.onFinished = onFinished
        if let presetProject {
            _destination = State(initialValue: .project(presetProject))
        } else if let presetList {
            _destination = State(initialValue: .list(presetList))
        } else {
            _destination = State(initialValue: .inbox)
        }
    }

    public var body: some View {
        FlowCard(padding: FlowSpacing.m) {
            VStack(alignment: .leading, spacing: FlowSpacing.m) {
                header
                titleField
                durationSection
                if presetList == nil && presetProject == nil {
                    projectSection
                }
                dateControl
                subtasksSection
                noteSection
                advancedDisclosure
                createButton
            }
        }
        .onAppear { titleFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("New")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onFinished) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(FlowTheme.surfaceWell(scheme)))
                    .flowHitTarget()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    // MARK: - Title

    private var titleField: some View {
        TextField("Task name…", text: $title)
            .focused($titleFocused)
            .onSubmit(createTask)
            .quickAddField()
            .accessibilityLabel("Task name")
    }

    // MARK: - Duration

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow("Worth · how much of your time?")
            ChipFlowLayout(spacing: FlowSpacing.s) {
                ForEach(durationOptions, id: \.self) { value in
                    durationChip(value)
                }
            }
        }
    }

    private func durationChip(_ value: Int) -> some View {
        let isSelected = value == minutes
        return Button {
            minutes = value
        } label: {
            Text(DurationFormatter.compact(minutes: value))
                .font(FlowFont.caption.weight(.bold))
                .foregroundStyle(isSelected ? .white : FlowTheme.secondaryText(scheme))
                .padding(.horizontal, FlowSpacing.m)
                // HIG override: the mock's chips read shorter than 44pt; the
                // tappable frame guarantees the hit target regardless.
                .frame(minHeight: 44)
                .background(Capsule().fill(isSelected ? FlowTheme.accent : FlowTheme.surface(scheme)))
                .overlay(
                    Capsule().strokeBorder(FlowTheme.separator(scheme), lineWidth: isSelected ? 0 : 1)
                )
                .shadow(color: isSelected ? .clear : FlowTheme.shadow(scheme), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(DurationFormatter.spoken(minutes: value))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Project

    private var destinationOptions: [Destination] {
        [.inbox] + lists.filter { !$0.isArchived }.map { .list($0) } + projects.map { .project($0) }
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow("PROJECT")
            ChipFlowLayout(spacing: FlowSpacing.s) {
                ForEach(destinationOptions, id: \.self) { option in
                    destinationPill(option)
                }
            }
        }
    }

    private func destinationPill(_ option: Destination) -> some View {
        let isSelected = option == destination
        return Button {
            destination = option
        } label: {
            HStack(spacing: FlowSpacing.xs) {
                Circle()
                    .fill(isSelected ? Color.white : pillColour(for: option))
                    .frame(width: 8, height: 8)
                Text(pillLabel(for: option))
                    .font(FlowFont.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? .white : FlowTheme.primaryText(scheme))
            .padding(.horizontal, FlowSpacing.m)
            .frame(minHeight: 44)
            .background(Capsule().fill(isSelected ? FlowTheme.accent : FlowTheme.surface(scheme)))
            .overlay(
                Capsule().strokeBorder(FlowTheme.separator(scheme), lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pillLabel(for: option))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func pillColour(for option: Destination) -> Color {
        switch option {
        case .inbox: return FlowTheme.tertiaryText(scheme)
        case .list(let list): return list.colour.base
        case .project(let project): return project.colour.base
        }
    }

    private func pillLabel(for option: Destination) -> String {
        switch option {
        case .inbox: return "Inbox"
        case .list(let list): return list.name
        case .project(let project): return project.title
        }
    }

    // MARK: - Date

    private var dateControl: some View {
        Group {
            if hasDate {
                HStack(spacing: FlowSpacing.xs) {
                    Image(systemName: "calendar").font(.system(size: 13, weight: .semibold))
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                    Button {
                        hasDate = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear date")
                }
                .foregroundStyle(FlowTheme.primaryText(scheme))
            } else {
                Button {
                    hasDate = true
                } label: {
                    HStack(spacing: FlowSpacing.xs) {
                        Image(systemName: "calendar").font(.system(size: 13, weight: .semibold))
                        Text("Date").font(FlowFont.caption.weight(.semibold))
                    }
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add due date")
            }
        }
        .padding(.horizontal, FlowSpacing.m)
        .frame(minHeight: 44)
        .background(Capsule().fill(FlowTheme.surface(scheme)))
        .overlay(Capsule().strokeBorder(FlowTheme.separator(scheme), lineWidth: 1))
    }

    // MARK: - Subtasks

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow("SUBTASKS")
            TextField("Add a subtask + return…", text: $subtaskDraft)
                .onSubmit(addSubtask)
                .quickAddField()
                .accessibilityLabel("Add a subtask")
            if !subtaskTitles.isEmpty {
                VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                    ForEach(Array(subtaskTitles.enumerated()), id: \.offset) { _, subtaskTitle in
                        HStack(spacing: FlowSpacing.xs) {
                            Circle().fill(FlowTheme.tertiaryText(scheme)).frame(width: 4, height: 4)
                            Text(subtaskTitle)
                                .font(FlowFont.caption)
                                .foregroundStyle(FlowTheme.secondaryText(scheme))
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Subtasks: \(subtaskTitles.joined(separator: ", "))")
            }
        }
    }

    private func addSubtask() {
        let trimmed = subtaskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        subtaskTitles.append(trimmed)
        subtaskDraft = ""
    }

    // MARK: - Note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow("NOTE")
            TextField("Optional note — attaches to this task…", text: $note)
                .quickAddField()
                .accessibilityLabel("Note")
        }
    }

    // MARK: - Advanced

    private var advancedDisclosure: some View {
        DisclosureGroup("Advanced", isExpanded: $isAdvancedExpanded) {
            VStack(alignment: .leading, spacing: FlowSpacing.m) {
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Preferred time of day", selection: $preferredPeriod) {
                    ForEach(DayPeriod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }

                Toggle("Earliest start", isOn: $hasEarliestStart)
                if hasEarliestStart {
                    DatePicker("", selection: $earliestStart).labelsHidden()
                }

                Toggle("Latest finish", isOn: $hasLatestFinish)
                if hasLatestFinish {
                    DatePicker("", selection: $latestFinish).labelsHidden()
                }

                Picker("Repeat", selection: $recurrence) {
                    ForEach(RecurrenceFrequency.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }

                Toggle("Allow splitting across sessions", isOn: $isSplittable)
                if isSplittable {
                    Stepper(
                        "Minimum chunk: \(DurationFormatter.compact(minutes: minimumChunkMinutes))",
                        value: $minimumChunkMinutes,
                        in: 5...120,
                        step: 5
                    )
                }
            }
            .padding(.top, FlowSpacing.s)
        }
        .font(FlowFont.secondary)
    }

    // MARK: - Create

    private var createButton: some View {
        Button(action: createTask) {
            Text("Create")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: FlowRadius.field, style: .continuous).fill(FlowTheme.accent))
        }
        .buttonStyle(.plain)
        .opacity(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel("Create task")
    }

    // MARK: - Save

    private func createTask() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var list: TaskList?
        var project: Project?
        switch destination {
        case .inbox: break
        case .list(let l): list = l
        case .project(let p): project = p
        }

        let task = FlowTask(
            title: trimmed,
            details: note.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .inbox,
            priority: priority,
            estimatedMinutes: minutes,
            dueDate: hasDate ? date : nil,
            list: list,
            project: project
        )
        task.preferredPeriod = preferredPeriod
        task.recurrence = recurrence
        task.isSplittable = isSplittable
        task.minimumChunkMinutes = minimumChunkMinutes
        if hasEarliestStart { task.earliestStart = earliestStart }
        if hasLatestFinish { task.latestFinish = latestFinish }
        if smartView == .today, !hasDate { task.isFlaggedForToday = true }

        context.insert(task)

        for (index, subtaskTitle) in subtaskTitles.enumerated() {
            let subtask = Subtask(title: subtaskTitle, sortOrder: index, task: task)
            context.insert(subtask)
        }

        try? context.save()
        onFinished()
    }
}

// MARK: - Field style

/// The rounded white field shared by the title, subtask and note inputs.
private struct QuickAddFieldBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .font(FlowFont.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: FlowRadius.field, style: .continuous)
                    .fill(FlowTheme.surface(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: FlowRadius.field, style: .continuous)
                    .strokeBorder(FlowTheme.separatorStrong(scheme), lineWidth: 1)
            )
    }
}

extension View {
    fileprivate func quickAddField() -> some View { modifier(QuickAddFieldBackground()) }
}

// MARK: - Chip wrap

/// Wraps chips onto multiple rows when they don't fit one line, so a
/// `1H 30M` duration chip or a long project name never clips off the
/// trailing edge on a narrower phone. Deliberately local to this file rather
/// than a shared kit component — same simple flow-layout technique as the
/// FAB's own "New" sheet, duplicated rather than exported.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

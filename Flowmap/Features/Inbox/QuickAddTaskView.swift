import SwiftData
import SwiftUI

/// The compact creation form revealed after pressing the `+` control.
///
/// Only title, duration, date and list/project show by default — priority,
/// constraints, recurrence and splitting live under the collapsed `Advanced`
/// disclosure. There is never a permanent full-width "Add it to your list" row;
/// this view only exists on screen while its parent's `+` has been pressed.
public struct QuickAddTaskView: View {
    @Environment(\.modelContext) private var context
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
                TextField("New task title", text: $title)
                    .font(FlowFont.cardTitle)
                    .focused($titleFocused)
                    .onSubmit(createTask)

                HStack(spacing: FlowSpacing.m) {
                    durationControl
                    dateControl
                    if presetList == nil && presetProject == nil {
                        destinationControl
                    }
                }

                advancedDisclosure

                HStack {
                    Button("Cancel") { onFinished() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Spacer()
                    PrimaryActionButton("Add task", systemImage: "plus", action: createTask)
                        .fixedSize()
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear { titleFocused = true }
    }

    // MARK: - Default-visible controls

    private var durationControl: some View {
        Menu {
            ForEach([15, 30, 45, 60, 90, 120], id: \.self) { value in
                Button(DurationFormatter.compact(minutes: value)) { minutes = value }
            }
        } label: {
            Label(DurationFormatter.compact(minutes: minutes), systemImage: "clock")
                .font(FlowFont.caption)
        }
        .accessibilityLabel("Duration, \(DurationFormatter.spoken(minutes: minutes))")
    }

    private var dateControl: some View {
        HStack(spacing: FlowSpacing.xs) {
            if hasDate {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                Button {
                    hasDate = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear date")
            } else {
                Button {
                    hasDate = true
                } label: {
                    Label("Date", systemImage: "calendar")
                        .font(FlowFont.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var destinationControl: some View {
        Menu {
            Button("Inbox") { destination = .inbox }
            if !lists.isEmpty {
                Section("Lists") {
                    ForEach(lists.filter { !$0.isArchived }) { list in
                        Button(list.name) { destination = .list(list) }
                    }
                }
            }
            if !projects.isEmpty {
                Section("Projects") {
                    ForEach(projects) { project in
                        Button(project.title) { destination = .project(project) }
                    }
                }
            }
        } label: {
            Label(destinationLabel, systemImage: destinationSymbol)
                .font(FlowFont.caption)
        }
        .accessibilityLabel("List or project: \(destinationLabel)")
    }

    private var destinationLabel: String {
        switch destination {
        case .inbox: return "Inbox"
        case .list(let list): return list.name
        case .project(let project): return project.title
        }
    }

    private var destinationSymbol: String {
        switch destination {
        case .inbox: return "tray"
        case .list(let list): return list.iconName
        case .project(let project): return project.iconName
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

        var status: TaskStatus = .inbox
        if smartView == .someday, list == nil, project == nil { status = .planned }

        let task = FlowTask(
            title: trimmed,
            status: status,
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
        try? context.save()
        onFinished()
    }
}

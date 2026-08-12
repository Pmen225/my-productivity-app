import SwiftData
import SwiftUI

private enum TaskIdentityLevel {
    case parent
    case subtask

    var dimension: CGFloat {
        switch self {
        case .parent: FlowControlSize.secondary
        case .subtask: FlowSpacing.xxl
        }
    }

    var radius: CGFloat {
        switch self {
        case .parent: FlowRadius.small
        case .subtask: FlowRadius.tile
        }
    }

    var font: Font {
        switch self {
        case .parent: FlowFont.body.weight(.bold)
        case .subtask: FlowFont.caption.weight(.semibold)
        }
    }
}

/// A task's identity stays on the leading edge. Subtasks inherit the parent
/// symbol at a smaller scale so the hierarchy reads without a schema change.
private struct TaskIdentityBadge: View {
    @Environment(\.colorScheme) private var scheme

    let symbolName: String
    let tint: ColourToken
    let level: TaskIdentityLevel

    var body: some View {
        Image(systemName: resolvedSymbolName)
            .font(level.font)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint.onSoft)
            .frame(width: level.dimension, height: level.dimension)
            .background(
                RoundedRectangle(cornerRadius: level.radius, style: .continuous)
                    .fill(tint.soft)
            )
            .overlay(
                RoundedRectangle(cornerRadius: level.radius, style: .continuous)
                    .strokeBorder(FlowTheme.separatorStrong(scheme), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    private var resolvedSymbolName: String {
        symbolName.isEmpty ? "circle" : symbolName
    }
}

private struct TaskSubtaskRevealHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// One polished task card with direct editing, completion, scheduling, moving,
/// deletion, and an inline sub-task disclosure when the task has children.
public struct TaskRowView: View {
    public enum HierarchyPosition: Equatable, Sendable {
        case standalone
        case groupRoot
        case groupMiddle
        case groupEnd
    }

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    let task: FlowTask
    private let onEdit: (() -> Void)?
    private let onDeleted: (() -> Void)?
    /// Parent and dependency rows stay as separate native List cells so their
    /// swipe actions keep working, while this presentation joins them into one
    /// calm visual stack instead of a wall of equal standalone cards.
    private let hierarchyPosition: HierarchyPosition
    private let hierarchyDepth: Int

    @State private var showDeleteConfirm = false
    @State private var showScheduler = false
    @State private var showMoveDialog = false
    @State private var scheduleDate = Date()
    /// Not persisted — collapses again next time this row is built, matching
    /// every other per-row disclosure in the app.
    @State private var isSubtasksExpanded = false
    /// The child content is always measured, then clipped from zero to its
    /// natural height. This makes the card itself unfold instead of swapping
    /// one list state for another.
    @State private var subtaskRevealHeight: CGFloat = 0

    private struct MetadataItem: Identifiable {
        let id: String
        let text: String
        let systemImage: String?
        let accessibilityLabel: String?
    }

    public init(
        task: FlowTask,
        onEdit: (() -> Void)? = nil,
        onDeleted: (() -> Void)? = nil,
        hierarchyPosition: HierarchyPosition = .standalone,
        hierarchyDepth: Int = 0
    ) {
        self.task = task
        self.onEdit = onEdit
        self.onDeleted = onDeleted
        self.hierarchyPosition = hierarchyPosition
        self.hierarchyDepth = max(0, hierarchyDepth)
    }

    private var isDependency: Bool { hierarchyDepth > 0 }
    private var hasSubtasks: Bool { !task.orderedSubtasks.isEmpty }

    private var cardShape: AnyShape {
        switch hierarchyPosition {
        case .standalone:
            AnyShape(RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous))
        case .groupRoot:
            AnyShape(UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: FlowRadius.medium,
                    bottomLeading: 0,
                    bottomTrailing: 0,
                    topTrailing: FlowRadius.medium
                ),
                style: .continuous
            ))
        case .groupMiddle:
            AnyShape(Rectangle())
        case .groupEnd:
            AnyShape(UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 0,
                    bottomLeading: FlowRadius.medium,
                    bottomTrailing: FlowRadius.medium,
                    topTrailing: 0
                ),
                style: .continuous
            ))
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            parentRow

            if hasSubtasks {
                subtaskReveal

                Divider()
                    .padding(.leading, hierarchyInset + FlowSpacing.m)
                subtaskDisclosureRow
            }
        }
        .background(
            cardShape
                .fill(isDependency ? FlowTheme.surfaceSunken(scheme) : FlowTheme.surface(scheme))
        )
        .clipShape(cardShape)
        .overlay {
            cardShape
                .stroke(FlowTheme.separator(scheme), lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            if isDependency {
                Capsule()
                    .fill(task.colour.base.opacity(0.65))
                    .frame(width: FlowSpacing.xxs)
                    .padding(.leading, FlowSpacing.xs)
                    .padding(.vertical, FlowSpacing.s)
            }
        }
        .contentShape(Rectangle())
        #if os(iOS)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                toggleComplete()
            } label: {
                Label(
                    task.status == .completed ? "Reopen" : "Complete",
                    systemImage: task.status == .completed ? "arrow.uturn.backward" : "checkmark"
                )
            }
            .tint(task.status == .completed ? FlowTheme.tertiaryText(scheme) : FlowTheme.accentDeep)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let onEdit {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(task.colour.base)
            }
            Button {
                showScheduler = true
            } label: {
                Label("Schedule", systemImage: "calendar.badge.clock")
            }
            .tint(FlowTheme.accent)
            Button {
                showMoveDialog = true
            } label: {
                Label("Move", systemImage: "folder")
            }
            .tint(FlowTheme.accentDeep)
            // No `role: .destructive`: that role rebuilds the row as the swipe
            // closes, which resets this view's state and silently drops the
            // confirmation card. The tint carries the same meaning.
            Button {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(FlowTheme.destructive)
        }
        #endif
        .contextMenu { contextMenuItems }
        .flowDeleteConfirmation(
            isPresented: $showDeleteConfirm,
            itemTitle: task.title,
            // Always the item wording: the branch wording names a project and
            // its tasks, which a task with subtasks is not.
            hasChildren: false,
            onDelete: deleteTask
        )
        .confirmationDialog("Move to…", isPresented: $showMoveDialog, titleVisibility: .visible) {
            Button("Inbox") { move(toList: nil, project: nil) }
            ForEach(lists.filter { !$0.isArchived }) { list in
                Button(list.name) { move(toList: list, project: nil) }
            }
            ForEach(projects) { project in
                Button(project.title) { move(toList: nil, project: project) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .popover(isPresented: $showScheduler) { schedulerPopover }
        .onChange(of: task.orderedSubtasks.count) { _, count in
            if count == 0 {
                isSubtasksExpanded = false
                subtaskRevealHeight = 0
            }
        }
    }

    private var hierarchyInset: CGFloat {
        CGFloat(hierarchyDepth) * FlowSpacing.l
    }

    // MARK: - Parent task

    private var parentRow: some View {
        HStack(alignment: .top, spacing: FlowSpacing.m) {
            editTarget
            completeToggle
        }
        .padding(.leading, hierarchyInset + FlowSpacing.m)
        .padding(.trailing, FlowSpacing.m)
        .padding(.vertical, isDependency ? FlowSpacing.s : FlowSpacing.m)
    }

    @ViewBuilder
    private var editTarget: some View {
        if let onEdit {
            Button(action: onEdit) {
                taskContent
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.title)
            .accessibilityValue(taskAccessibilityValue)
            .accessibilityHint("Opens task editing controls")
        } else {
            taskContent
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
    }

    private var taskContent: some View {
        HStack(alignment: .top, spacing: FlowSpacing.m) {
            TaskIdentityBadge(symbolName: task.iconName, tint: task.colour, level: .parent)
            taskSummary
        }
    }

    @ViewBuilder
    private var taskSummary: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: FlowSpacing.s) {
                titleAndMetadata
                DurationChip(minutes: task.estimatedMinutes, tint: task.colour)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: FlowSpacing.s) {
                titleAndMetadata
                Spacer(minLength: FlowSpacing.s)
                DurationChip(minutes: task.estimatedMinutes, tint: task.colour)
            }
        }
    }

    private var titleAndMetadata: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
            Text(task.title)
                .font(FlowFont.body)
                .strikethrough(task.status == .completed)
                .foregroundStyle(
                    task.status == .completed
                        ? FlowTheme.tertiaryText(scheme)
                        : FlowTheme.primaryText(scheme)
                )
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            metadataLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var taskAccessibilityValue: String {
        var values = [task.durationAccessibilityLabel]
        if let progress = task.subtaskProgressLabel {
            values.append("\(progress) sub-tasks complete")
        }
        if task.status == .completed {
            values.append("completed")
        }
        return values.joined(separator: ", ")
    }

    // MARK: - Complete toggle

    private var completeToggle: some View {
        Button(action: toggleComplete) {
            Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                .font(FlowFont.body)
                .foregroundStyle(task.colour.base.opacity(task.status == .completed ? 1 : 0.62))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44, alignment: .trailing)
        .accessibilityLabel(task.status == .completed ? "Reopen task" : "Mark task complete")
        .accessibilityHint(task.status == .completed ? "Marks this task as incomplete" : "Marks this task as complete")
    }

    // MARK: - Metadata line

    private var metadataLine: some View {
        HStack(spacing: FlowSpacing.s) {
            ForEach(Array(metadataItems.prefix(2))) { item in
                if let systemImage = item.systemImage {
                    Label(item.text, systemImage: systemImage)
                        .accessibilityLabel(item.accessibilityLabel ?? item.text)
                } else {
                    Text(item.text)
                        .accessibilityLabel(item.accessibilityLabel ?? item.text)
                }
            }
        }
        .font(FlowFont.caption)
        .foregroundStyle(FlowTheme.secondaryText(scheme))
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    /// Keep the row to one calm metadata line. Sub-task progress lives only in
    /// the quiet disclosure footer, preventing duplicate competing metadata.
    private var metadataItems: [MetadataItem] {
        let now = flow?.now ?? Date()
        var items: [MetadataItem] = []
        if let parent = task.parentTask {
            items.append(MetadataItem(
                id: "parent",
                text: parent.title,
                systemImage: "arrow.turn.down.right",
                accessibilityLabel: "Child of \(parent.title)"
            ))
        }
        if task.priority != .none {
            items.append(MetadataItem(
                id: "priority",
                text: task.priority.displayName,
                systemImage: task.priority.symbolName,
                accessibilityLabel: "Priority \(task.priority.displayName)"
            ))
        }
        if let due = task.dueDate {
            let isStartOfDay = due == Calendar.current.startOfDay(for: due)
            let text = due.formatted(
                date: .abbreviated,
                time: isStartOfDay ? .omitted : .shortened
            )
            items.append(MetadataItem(id: "due", text: text, systemImage: "calendar", accessibilityLabel: "Due \(text)"))
        }
        if let upcoming = task.nextSegment(after: now) {
            let label = ScheduleWording.startLabel(upcoming.startDate, now: now, calendar: .current)
            items.append(MetadataItem(id: "scheduled", text: label, systemImage: "calendar.badge.clock", accessibilityLabel: label))
        }
        if let badge = task.liveSegments.first?.badgeText {
            items.append(MetadataItem(id: "carryover", text: badge, systemImage: nil, accessibilityLabel: badge))
        }
        return items
    }

    // MARK: - Sub-task disclosure

    /// The child content keeps its identity in the hierarchy while the outer
    /// card animates between zero and its measured height. The footer therefore
    /// travels with the card instead of jumping between two list states.
    private var subtaskReveal: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.leading, hierarchyInset + FlowSpacing.m)
            subtaskList
        }
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TaskSubtaskRevealHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
        .onPreferenceChange(TaskSubtaskRevealHeightKey.self) { height in
            guard height > 0 else { return }
            subtaskRevealHeight = height
        }
        .frame(height: isSubtasksExpanded ? subtaskRevealHeight : 0, alignment: .top)
        .opacity(isSubtasksExpanded ? 1 : 0)
        .scaleEffect(x: 1, y: isSubtasksExpanded ? 1 : 0.94, anchor: .top)
        .clipped()
        .allowsHitTesting(isSubtasksExpanded)
        .accessibilityHidden(!isSubtasksExpanded)
    }

    /// The entire quiet footer is the disclosure target. Expanded child rows
    /// remain above it inside the same outer task-card boundary.
    private var subtaskDisclosureRow: some View {
        Button(action: toggleSubtasksExpanded) {
            HStack(spacing: FlowSpacing.s) {
                ProgressView(value: task.subtaskCompletionFraction)
                    .progressViewStyle(.linear)
                    .tint(task.colour.base)
                    .frame(width: FlowSpacing.xxxl)
                    .accessibilityHidden(true)

                Text(task.subtaskProgressLabel ?? "")
                    .font(FlowFont.caption)
                    .monospacedDigit()

                Spacer(minLength: FlowSpacing.s)

                Image(systemName: "chevron.right")
                    .font(FlowFont.caption.weight(.semibold))
                    .rotationEffect(.degrees(isSubtasksExpanded && !reduceMotion ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(FlowTheme.tertiaryText(scheme))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .padding(.leading, hierarchyInset + FlowSpacing.m)
            .padding(.trailing, FlowSpacing.m)
            .background(FlowTheme.surfaceSunken(scheme))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSubtasksExpanded ? "Collapse sub-tasks" : "Expand sub-tasks")
        .accessibilityValue(task.subtaskProgressLabel ?? "")
        .accessibilityHint(isSubtasksExpanded ? "Hides the sub-task list" : "Shows the sub-task list")
    }

    /// Reduce Motion keeps state changes explicit without rotation or sliding.
    private func toggleSubtasksExpanded() {
        if reduceMotion {
            isSubtasksExpanded.toggle()
        } else {
            withAnimation(FlowMotion.expand) {
                isSubtasksExpanded.toggle()
            }
        }
    }

    // MARK: - Sub-task list

    private var subtaskList: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            ForEach(task.orderedSubtasks) { subtask in
                subtaskRow(subtask)
            }
        }
        .padding(.leading, hierarchyInset + FlowSpacing.xl)
        .padding(.trailing, FlowSpacing.m)
        .padding(.vertical, FlowSpacing.s)
    }

    private func subtaskRow(_ subtask: Subtask) -> some View {
        HStack(spacing: FlowSpacing.s) {
            TaskIdentityBadge(symbolName: task.iconName, tint: task.colour, level: .subtask)
            Text(subtask.title)
                .font(FlowFont.caption)
                .foregroundStyle(
                    subtask.isCompleted
                        ? FlowTheme.tertiaryText(scheme)
                        : FlowTheme.primaryText(scheme)
                )
                .strikethrough(subtask.isCompleted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: FlowSpacing.s)
            Button {
                flow?.gamification.toggleSubtask(subtask)
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(FlowFont.body)
                    .foregroundStyle(task.colour.base.opacity(subtask.isCompleted ? 1 : 0.62))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(subtask.title)
            .accessibilityValue(subtask.isCompleted ? "Completed" : "Not completed")
            .accessibilityHint(subtask.isCompleted ? "Marks this sub-task as incomplete" : "Marks this sub-task as complete")
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    // MARK: - Context menu (both platforms)

    @ViewBuilder
    private var contextMenuItems: some View {
        if let onEdit {
            Button(action: onEdit) {
                Label("Edit task", systemImage: "pencil")
            }
        }
        Button {
            toggleComplete()
        } label: {
            Label(
                task.status == .completed ? "Reopen" : "Complete",
                systemImage: task.status == .completed ? "arrow.uturn.backward" : "checkmark"
            )
        }
        Button {
            startTaskNow()
        } label: {
            Label("Start task", systemImage: "play")
        }
        Button {
            showScheduler = true
        } label: {
            Label("Schedule…", systemImage: "calendar.badge.clock")
        }
        Button {
            rescheduleForTomorrow()
        } label: {
            Label("Reschedule for Tomorrow", systemImage: "sunrise")
        }
        Menu("Move to…") {
            Button("Inbox") { move(toList: nil, project: nil) }
            ForEach(lists.filter { !$0.isArchived }) { list in
                Button(list.name) { move(toList: list, project: nil) }
            }
            ForEach(projects) { project in
                Button(project.title) { move(toList: nil, project: project) }
            }
        }
        Button {
            duplicateTask()
        } label: {
            Label("Make a Copy", systemImage: "doc.on.doc")
        }
        Divider()
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Scheduler popover

    private var schedulerPopover: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.m) {
            Text("Schedule").font(FlowFont.cardTitle)
            DatePicker("Start", selection: $scheduleDate)
                .labelsHidden()
            PrimaryActionButton("Place on timeline") {
                placeOnTimeline()
            }
        }
        .padding(FlowSpacing.l)
        .frame(width: 280)
    }

    // MARK: - Actions

    private func toggleComplete() {
        withAnimation(FlowMotion.tap) {
            if task.status == .completed {
                task.reopen()
            } else {
                task.markCompleted()
            }
            try? context.save()
        }
    }

    /// Places the task on the timeline at `scheduleDate` and says so. A taken
    /// slot returns `nil`, silently, from `SchedulingService` — this is the
    /// one place that turns that silence into something the user can see and
    /// act on, per the HIG's "feedback near the action" rule.
    private func placeOnTimeline() {
        let now = flow?.now ?? Date()
        guard let segment = flow?.scheduling().schedule(task: task, at: scheduleDate) else {
            flow?.moments.show(.notif(
                title: "That time is taken",
                subtitle: "Nothing was changed — pick another slot."
            ))
            return
        }
        showScheduler = false
        let subtitle = Calendar.current.isDate(segment.startDate, inSameDayAs: now)
            ? "On today's timeline."
            : "Find it in Upcoming."
        flow?.moments.show(.notif(
            title: "Scheduled — \(ScheduleWording.startLabel(segment.startDate, now: now, calendar: .current))",
            subtitle: subtitle
        ))
    }

    /// Starts focus on this task now, through `FocusEngine`'s own existing
    /// "start arbitrary task" path — the same one every other caller uses
    /// (state/specs/task61-handover.md lists them). A blocked start returns
    /// `nil` and sets `pendingGate`; this row has no gate dialog of its own,
    /// so it surfaces the refusal as a moment, matching `TodayView`'s wording.
    private func startTaskNow() {
        guard let flow else { return }
        if flow.focusEngine.start(task: task, now: flow.now) != nil {
            flow.moments.show(.notif(
                title: "Focusing on \(task.title)",
                subtitle: "Open Focus to see the timer."
            ))
        } else {
            let needsPlan = flow.focusEngine.pendingGate?.kind == .planGate
            flow.moments.show(.notif(
                title: needsPlan ? "Needs a Definition of Done" : "Clock in from Focus",
                subtitle: needsPlan
                    ? "Open Focus and write a Definition of Done before this can start."
                    : "This task is mid-carryover — open Focus to clock back in."
            ))
        }
    }

    /// Frees today's segments (if any) and places the task in tomorrow's
    /// earliest opening via the same `planNow` `PlanInboxSection` already
    /// uses for its own "Plan now" action — no new placement algorithm, just
    /// `unschedule` + `planNow` composed for a fixed target day. Falls back
    /// to flagging the task into tomorrow's inbox, the same fallback
    /// `moveRolloverTaskToTomorrow` uses when its own search finds no room,
    /// rather than losing the intent silently.
    private func rescheduleForTomorrow() {
        guard let flow else { return }
        let tomorrow = Self.tomorrowStart(after: flow.now)
        for segment in task.liveSegments {
            flow.scheduling().unschedule(segment: segment)
        }
        if let segment = flow.scheduling().planNow(task: task, now: tomorrow, lookaheadDays: 1) {
            flow.moments.show(.notif(
                title: "Moved to tomorrow",
                subtitle: ScheduleWording.startLabel(segment.startDate, now: flow.now, calendar: .current)
            ))
        } else {
            task.status = .inbox
            task.dueDate = tomorrow
            task.isFlaggedForToday = false
            try? context.save()
            flow.moments.show(.notif(
                title: "Moved to tomorrow",
                subtitle: "No free slot yet — find it in tomorrow's inbox."
            ))
        }
    }

    /// Start of the day after `date` — the one piece of date maths this
    /// quick action needs beyond what `SchedulingService` already exposes.
    /// `static`, not `private`, so it is directly unit-testable.
    static func tomorrowStart(after date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start
    }

    private func duplicateTask() {
        Self.duplicate(task, in: context)
    }

    /// Copies title, colour, duration and sub-tasks into a new task in the
    /// same list/project — never completion state or schedule (fresh
    /// `.inbox` status, no due date, no segments). No existing duplicate
    /// helper was found anywhere in the codebase (grepped for
    /// "duplicate"/"Make a Copy"/"copy(", none present) — this is new.
    /// `static`, not `private`, so it is directly unit-testable.
    @discardableResult
    static func duplicate(_ task: FlowTask, in context: ModelContext) -> FlowTask {
        let copy = FlowTask(
            title: task.title,
            estimatedMinutes: task.estimatedMinutes,
            colourToken: task.colourToken,
            iconName: task.iconName,
            sortOrder: task.sortOrder,
            list: task.list,
            project: task.project,
            workspace: task.workspace
        )
        _ = TaskCreationService.insert(copy, parent: task.parentTask, in: context)
        copy.colourToken = task.colourToken
        for subtask in task.orderedSubtasks {
            context.insert(Subtask(
                title: subtask.title,
                isCompleted: false,
                sortOrder: subtask.sortOrder,
                estimatedMinutes: subtask.estimatedMinutes,
                task: copy
            ))
        }
        try? context.save()
        return copy
    }

    private func move(toList list: TaskList?, project: Project?) {
        task.list = list
        task.project = project
        task.touch()
        try? context.save()
    }

    private func deleteTask() {
        let childCount = task.orderedChildTasks.count
        let title = task.title
        withAnimation(FlowMotion.tap) {
            context.delete(task)
            try? context.save()
            onDeleted?()
        }
        if childCount > 0 {
            flow?.moments.show(.notif(
                title: "\(title) deleted",
                subtitle: childCount == 1
                    ? "Its child task moved to the top level."
                    : "Its \(childCount) child tasks moved to the top level."
            ))
        }
    }
}

import SwiftData
import SwiftUI

/// One row on a to-do screen: a completion toggle, title, and trailing badges
/// that stay consistent everywhere the task appears. Swipe (iOS) and context
/// menu (both platforms) expose complete, schedule, move and delete.
public struct TaskRowView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    let task: FlowTask
    private let onDeleted: (() -> Void)?

    @State private var showDeleteConfirm = false
    @State private var showScheduler = false
    @State private var showMoveDialog = false
    @State private var scheduleDate = Date()
    /// Not persisted — collapses again next time this row is built, matching
    /// every other per-row disclosure in the app.
    @State private var isSubtasksExpanded = false

    /// The 44pt `completeToggle` column plus the row's own `HStack` spacing —
    /// sub-task content indents to line up under the title, not under the toggle.
    private static let subtaskIndent: CGFloat = 44 + FlowSpacing.m

    private struct MetadataItem: Identifiable {
        let id: String
        let text: String
        let systemImage: String?
        let accessibilityLabel: String?
    }

    public init(task: FlowTask, onDeleted: (() -> Void)? = nil) {
        self.task = task
        self.onDeleted = onDeleted
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            HStack(alignment: .top, spacing: FlowSpacing.m) {
                completeToggle
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
                    metadataLine
                }
                Spacer(minLength: FlowSpacing.s)
                DurationChip(minutes: task.estimatedMinutes, tint: task.colour)
            }
            // Disclosure row and expanded list are additive: a row with no
            // sub-tasks renders exactly as before, no dead chevron.
            if !task.orderedSubtasks.isEmpty {
                subtaskDisclosureRow
                if isSubtasksExpanded {
                    subtaskList
                }
            }
        }
        .padding(FlowSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .fill(FlowTheme.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .strokeBorder(FlowTheme.separator(scheme), lineWidth: 1)
        )
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
            // No `role: .destructive`: that role rebuilds the row as the swipe
            // closes, which resets this view's state and silently drops the
            // confirmation card. The tint carries the same meaning.
            Button {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(FlowTheme.destructive)
            Button {
                showMoveDialog = true
            } label: {
                Label("Move", systemImage: "folder")
            }
            .tint(FlowTheme.accentDeep)
            Button {
                showScheduler = true
            } label: {
                Label("Schedule", systemImage: "calendar.badge.clock")
            }
            .tint(FlowTheme.accent)
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
    }

    // MARK: - Complete toggle

    private var completeToggle: some View {
        Button(action: toggleComplete) {
            Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                .font(FlowFont.body)
                .foregroundStyle(task.colour.base.opacity(task.status == .completed ? 1 : 0.5))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
        .accessibilityLabel(task.status == .completed ? "Completed" : "Mark complete")
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

    /// Keep the row to one calm metadata line. The first two facts are the
    /// only ones that survive on a compact surface; the detail view remains
    /// the place for the rest, per the spatial-economy rule.
    private var metadataItems: [MetadataItem] {
        let now = flow?.now ?? Date()
        var items: [MetadataItem] = []
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
        if let label = task.subtaskProgressLabel {
            items.append(MetadataItem(id: "subtasks", text: label, systemImage: "checklist", accessibilityLabel: label))
        }
        if let badge = task.liveSegments.first?.badgeText {
            items.append(MetadataItem(id: "carryover", text: badge, systemImage: nil, accessibilityLabel: badge))
        }
        return items
    }

    // MARK: - Sub-task disclosure (collapsed: progress bar + chevron)

    /// Thin progress capsule plus the disclosure chevron — the only new tap
    /// surface this row gains. The capsule itself carries no gesture, so
    /// tapping it falls through to whatever the row already does.
    private var subtaskDisclosureRow: some View {
        HStack(spacing: FlowSpacing.s) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(FlowTheme.separator(scheme))
                    Capsule()
                        .fill(task.colour.base)
                        .frame(width: proxy.size.width * task.subtaskCompletionFraction)
                }
            }
            .frame(height: FlowSpacing.xs)
            // Decorative: the "N of M" label already speaks this progress in
            // `metadataLine`. Hiding it keeps the chevron the row's only
            // sub-task VoiceOver stop, so its own "Show/Hide" label is heard.
            .accessibilityHidden(true)
            chevronButton
        }
        .padding(.leading, Self.subtaskIndent)
    }

    private var chevronButton: some View {
        Button(action: toggleSubtasksExpanded) {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .rotationEffect(.degrees(isSubtasksExpanded ? 90 : 0))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSubtasksExpanded ? "Hide sub-tasks" : "Show sub-tasks")
    }

    /// Reduce Motion swaps the rotate for a plain appear/disappear — no
    /// rotation, no slide, per the spec's accessibility requirement.
    private func toggleSubtasksExpanded() {
        if reduceMotion {
            isSubtasksExpanded.toggle()
        } else {
            withAnimation(.snappy) {
                isSubtasksExpanded.toggle()
            }
        }
    }

    // MARK: - Sub-task list (expanded)

    private var subtaskList: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            ForEach(task.orderedSubtasks) { subtask in
                subtaskRow(subtask)
            }
        }
        .padding(.leading, Self.subtaskIndent)
        .padding(.top, FlowSpacing.xxs)
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }

    private func subtaskRow(_ subtask: Subtask) -> some View {
        HStack(spacing: FlowSpacing.s) {
            Circle()
                .fill(task.colour.base)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(subtask.title)
                .font(FlowFont.caption)
                .foregroundStyle(
                    subtask.isCompleted
                        ? FlowTheme.tertiaryText(scheme)
                        : FlowTheme.primaryText(scheme)
                )
                .strikethrough(subtask.isCompleted)
                // Titles wrap rather than clip, per spec — Dynamic Type must
                // never truncate a sub-task's name.
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: FlowSpacing.s)
            Button {
                flow?.gamification.toggleSubtask(subtask)
            } label: {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(FlowFont.body)
                    .foregroundStyle(task.colour.base.opacity(subtask.isCompleted ? 1 : 0.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(subtask.title), \(subtask.isCompleted ? "completed" : "not completed")")
        }
    }

    // MARK: - Context menu (both platforms)

    @ViewBuilder
    private var contextMenuItems: some View {
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
        withAnimation(.snappy) {
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
        context.insert(copy)
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
        withAnimation(.snappy) {
            context.delete(task)
            try? context.save()
            onDeleted?()
        }
    }
}

import SwiftData
import SwiftUI

/// One row on a to-do screen: a completion toggle, title, and trailing badges
/// that stay consistent everywhere the task appears. Swipe (iOS) and context
/// menu (both platforms) expose complete, schedule, move and delete.
public struct TaskRowView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskList.sortOrder) private var lists: [TaskList]
    @Query(sort: \Project.sortOrder) private var projects: [Project]

    let task: FlowTask
    private let onDeleted: (() -> Void)?

    @State private var showDeleteConfirm = false
    @State private var showScheduler = false
    @State private var showMoveDialog = false
    @State private var scheduleDate = Date()

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
            showScheduler = true
        } label: {
            Label("Schedule…", systemImage: "calendar.badge.clock")
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

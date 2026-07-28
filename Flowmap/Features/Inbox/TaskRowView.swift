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
            .tint(task.status == .completed ? .gray : .green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                showMoveDialog = true
            } label: {
                Label("Move", systemImage: "folder")
            }
            .tint(.blue)
            Button {
                showScheduler = true
            } label: {
                Label("Schedule", systemImage: "calendar.badge.clock")
            }
            .tint(.orange)
        }
        #endif
        .contextMenu { contextMenuItems }
        .confirmationDialog(
            "Delete “\(task.title)”?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deleteTask)
            Button("Cancel", role: .cancel) {}
        }
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
                .font(.system(size: 20))
                .foregroundStyle(task.colour.base.opacity(task.status == .completed ? 1 : 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.status == .completed ? "Completed" : "Mark complete")
    }

    // MARK: - Metadata line

    private var metadataLine: some View {
        HStack(spacing: FlowSpacing.s) {
            if task.priority != .none {
                Image(systemName: task.priority.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .accessibilityLabel("Priority \(task.priority.displayName)")
            }
            if let due = task.dueDate {
                Text(due, style: .date)
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }
            if let label = task.subtaskProgressLabel {
                Label(label, systemImage: "checklist")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }
            if let badge = task.liveSegments.first?.badgeText {
                Text(badge)
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }
        }
        .labelStyle(.titleAndIcon)
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
                _ = flow?.scheduling().schedule(task: task, at: scheduleDate)
                showScheduler = false
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

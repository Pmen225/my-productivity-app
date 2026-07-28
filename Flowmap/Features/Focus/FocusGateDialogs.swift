import SwiftUI

/// The compulsory planning gate — the mock's "define done before you start"
/// modal. Demands a free-text Definition of Done plus an inline subtask
/// list; "Start task" is blocked (not merely dimmed) until the definition
/// is non-empty, surfacing the design's own copy for the block.
struct PlanGateDialog: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context
    @Environment(\.flow) private var flow

    let task: FlowTask
    let onStart: (String) -> Void

    @State private var definition: String = ""
    @State private var newSubtaskTitle: String = ""
    @State private var showsBlockedMessage = false

    var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.m) {
            FlowEyebrow("Before you start", tint: FlowTheme.accent)
            Text(task.title)
                .font(FlowFont.dialogTitle)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            definitionField
            subtaskList

            if showsBlockedMessage {
                Text("Write your definition of done first")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.accent)
                    .accessibilityLabel("Write your definition of done first")
            }

            PrimaryActionButton("Start task", action: attemptStart)
                .padding(.top, FlowSpacing.xs)
        }
        .padding(FlowSpacing.l)
        .frame(maxWidth: 340)
        .flowGlass(radius: FlowRadius.sheet)
        .accessibilityElement(children: .contain)
        .onAppear { definition = task.definitionOfDone }
    }

    private var definitionField: some View {
        TextField(
            "Definition of done — e.g. '10 pages read & summarised'",
            text: $definition,
            axis: .vertical
        )
        .font(FlowFont.body)
        .lineLimit(2...4)
        .padding(FlowSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.field, style: .continuous)
                .fill(FlowTheme.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.field, style: .continuous)
                .strokeBorder(FlowTheme.separatorStrong(scheme), lineWidth: 1)
        )
        .accessibilityLabel("Definition of done")
        .onChange(of: definition) { _, _ in showsBlockedMessage = false }
    }

    /// Mirrors `TaskDetailInspector`'s subtask row/add-box idiom so the same
    /// checklist model reads identically wherever it is edited.
    private var subtaskList: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow("Subtasks")
            ForEach(task.orderedSubtasks) { subtask in
                subtaskRow(subtask)
            }
            HStack {
                TextField("Add a subtask", text: $newSubtaskTitle)
                    .font(FlowFont.secondary)
                    .onSubmit(addSubtask)
                Button(action: addSubtask) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(FlowTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Add subtask")
            }
        }
    }

    private func subtaskRow(_ subtask: Subtask) -> some View {
        Button {
            flow?.gamification.toggleSubtask(subtask)
        } label: {
            HStack(spacing: FlowSpacing.xs) {
                Image(systemName: subtask.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(subtask.isCompleted ? task.colour.base : FlowTheme.tertiaryText(scheme))
                Text(subtask.title)
                    .font(FlowFont.secondary)
                    .strikethrough(subtask.isCompleted)
                    .foregroundStyle(subtask.isCompleted ? FlowTheme.tertiaryText(scheme) : FlowTheme.primaryText(scheme))
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func addSubtask() {
        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let subtask = Subtask(title: trimmed, sortOrder: task.orderedSubtasks.count, task: task)
        context.insert(subtask)
        try? context.save()
        newSubtaskTitle = ""
    }

    private func attemptStart() {
        let trimmed = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showsBlockedMessage = true
            return
        }
        onStart(trimmed)
    }
}

/// The lighter re-confirmation for a task that has already been planned —
/// the mock's Clock-in modal. `FlowDialog` already has this exact
/// eyebrow/title/message/CTA shape, so nothing new is composed here.
struct ClockInDialog: View {
    let task: FlowTask
    let onClockIn: () -> Void

    var body: some View {
        FlowDialog(
            eyebrow: "Clock in",
            title: task.title,
            message: "The clock keeps ticking — unfinished work always comes around again.",
            ctaTitle: "Clock in",
            ctaAction: onClockIn
        )
    }
}

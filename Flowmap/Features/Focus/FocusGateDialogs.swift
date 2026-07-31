import SwiftUI

/// The compulsory planning gate — the mock's "define done before you start"
/// modal. Demands an inline subtask checklist; "Start task" is blocked (not
/// merely dimmed) until the task has at least one subtask — the checklist
/// itself is the definition of done (feedback task 21).
struct PlanGateDialog: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context
    @Environment(\.flow) private var flow

    /// The mockup's own gate copy, held as statics so the tests can pin the
    /// exact wording rather than re-typing it and drifting.
    static let gateMessage = "Break it down. A clear checklist stops the endless tweaking."
    static let blockedMessage = "Add at least one subtask — that is your definition of done."
    static let allCompletedBlockedMessage = "Everything here is already ticked — un-tick or add what is left."

    /// The mockup labels the list `SUBTASKS · N`, so the count travels with
    /// the eyebrow rather than sitting in a separate badge.
    static func subtasksEyebrow(count: Int) -> String { "Subtasks · \(count)" }

    let task: FlowTask
    let onStart: () -> Void

    @State private var newSubtaskTitle: String = ""
    @State private var showsBlockedMessage = false

    var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.m) {
            FlowEyebrow("Plan before you start", tint: FlowTheme.accent)
            Text(task.title)
                .font(FlowFont.dialogTitle)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Text(Self.gateMessage)
                .font(FlowFont.secondary)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            subtaskList

            if showsBlockedMessage {
                Text(blockedMessage)
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.accent)
                    .accessibilityLabel(blockedMessage)
            }

            PrimaryActionButton("Start task", action: attemptStart)
                .padding(.top, FlowSpacing.xs)
        }
        .padding(FlowSpacing.l)
        .frame(maxWidth: 340)
        .flowGlass(radius: FlowRadius.sheet)
        .accessibilityElement(children: .contain)
        // A task arriving at the gate with old prose but no subtasks yet
        // (written before this checklist existed) gets that text seeded as
        // its first subtask, so nothing anyone wrote is lost.
        .onAppear { seedSubtaskFromDefinitionOfDoneIfNeeded() }
    }

    private func seedSubtaskFromDefinitionOfDoneIfNeeded() {
        let trimmed = task.definitionOfDone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard task.orderedSubtasks.isEmpty, !trimmed.isEmpty else { return }
        newSubtaskTitle = trimmed
        addSubtask()
    }

    /// Mirrors `TaskDetailInspector`'s subtask row/add-box idiom so the same
    /// checklist model reads identically wherever it is edited.
    private var subtaskList: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            FlowEyebrow(Self.subtasksEyebrow(count: task.orderedSubtasks.count))
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
        showsBlockedMessage = false
    }

    private func attemptStart() {
        guard !task.orderedSubtasks.isEmpty else {
            showsBlockedMessage = true
            return
        }
        guard !task.orderedSubtasks.allSatisfy(\.isCompleted) else {
            showsBlockedMessage = true
            return
        }
        onStart()
    }

    private var blockedMessage: String {
        !task.orderedSubtasks.isEmpty && task.orderedSubtasks.allSatisfy(\.isCompleted)
            ? Self.allCompletedBlockedMessage
            : Self.blockedMessage
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
            eyebrow: "Next up",
            title: task.title,
            message: "Clock in to start the timer. The clock keeps ticking — unfinished work always comes around again.",
            ctaTitle: "Clock in ▸",
            ctaAction: onClockIn
        )
    }
}

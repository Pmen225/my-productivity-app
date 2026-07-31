import SwiftData
import SwiftUI

/// The Plan tab's inbox block: everything captured that has not been given a
/// slot yet, the capacity left to give it, and the two ways of giving it one.
///
/// Sits above the Plan tab's own library sections rather than being its own
/// screen — triage and the rest of the plan belong on one page, which is what
/// the mock does with `planBodyEl` followed by `libBodyEl`.
struct PlanInboxSection: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.flow) private var flow

    @Query private var allTasks: [FlowTask]

    /// Which row has been tapped open. One at a time: two editors expanded at
    /// once is a list nobody can read.
    @State private var editingTaskID: UUID?
    /// Both duel and plan-preview presentation are driven from here but
    /// HOSTED by `LibraryView`, which owns the `.sheet` modifiers. A `.sheet`
    /// attached to this view's own `Section` never presents: `Section` is
    /// only one of several children inside `LibraryView`'s outer `List`, and
    /// SwiftUI does not reliably host a presentation controller for a
    /// modifier attached that deep inside another List's content — the
    /// duel's own entry point silently stopped opening the moment T6 moved
    /// it from `TaskListScreen` (where `.sheet` sat on the screen's own
    /// top-level `List`) into this nested `Section`. Bindings, not local
    /// `@State`, so the parent's `.sheet` toggles the same flag this button
    /// sets.
    @Binding var showingDuel: Bool
    @Binding var showingPlanPreview: Bool
    @Binding var planProposal: PlanProposal?

    private var inbox: [FlowTask] {
        SmartView.inbox.matches(allTasks)
    }

    /// The duel's own set — today's open tasks (flagged, due, or scheduled
    /// today), never the inbox. Planning must not require the game, so the
    /// game is offered as a way to order what's already lined up for today,
    /// not a gate in front of triage (state/specs/cognitive-profile.md,
    /// "product thesis").
    private var today: [FlowTask] {
        SmartView.today.matches(allTasks, now: flow?.now ?? Date())
    }

    var body: some View {
        Section {
            if inbox.isEmpty {
                Text("Inbox zero — everything is planned.")
                    .font(FlowFont.secondary)
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(inbox) { task in
                    row(task)
                }
                actions
            }
        } header: {
            header
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
            CompactSectionHeader(title: "Inbox", count: inbox.count)
            Text(capacityLine)
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .textCase(nil)
        }
    }

    /// `4h 30m free before 21:00 · plan places tasks in the earliest slots`.
    private var capacityLine: String {
        guard let flow else { return "" }
        let free = flow.scheduling().freeMinutesRemainingToday(now: flow.now)
        let until = flow.settings.workdayEndLabel
        return "\(DurationFormatter.compact(minutes: free)) free before \(until) · plan places tasks in the earliest slots"
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ task: FlowTask) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.m) {
            TaskRowView(task: task)
            if editingTaskID == task.id {
                editor(task)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleEditor(for: task) }
    }

    /// The mock's in-row editor: rename, re-time, and place — the three things
    /// worth doing during triage, without leaving the list to do them.
    private func editor(_ task: FlowTask) -> some View {
        VStack(alignment: .leading, spacing: FlowSpacing.m) {
            TextField("Task name", text: Binding(get: { task.title }, set: { task.title = $0 }))
                .font(FlowFont.body)
                .accessibilityLabel("Rename task")
            HStack(spacing: FlowSpacing.m) {
                Text("Duration")
                    .font(FlowFont.body)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                FlowDurationWheel(
                    minutes: Binding(
                        get: { task.estimatedMinutes },
                        set: { task.estimatedMinutes = $0 }
                    )
                )
            }
            SecondaryActionButton("Plan now — earliest free slot", systemImage: "calendar.badge.clock") {
                planNow(task)
            }
        }
        .padding(.leading, FlowSpacing.xl)
    }

    private var actions: some View {
        // The duel only has something to say once there are two of today's
        // tasks to compare — the same rule `TaskListScreen` used before Plan
        // existed, now over today's set rather than the inbox.
        let duelAvailable = PrioritiseDuel.isAvailable(for: today.map(\.id))
        // Primary act first, optional game second, no caption — the founder's
        // rule zero (state/specs/space-notes.md): a control that needs a
        // caption is the wrong control, and the primary action leads.
        return VStack(spacing: FlowSpacing.s) {
            // Decision 12: the whole day is previewed before it moves.
            PrimaryActionButton("Start planning") {
                planProposal = flow?.planToday(replanExisting: false)
                showingPlanPreview = true
            }
            if duelAvailable {
                SecondaryActionButton("Prioritise today — play the game", systemImage: "play.fill") {
                    showingDuel = true
                }
            }
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Actions

    private func toggleEditor(for task: FlowTask) {
        editingTaskID = editingTaskID == task.id ? nil : task.id
    }

    private func planNow(_ task: FlowTask) {
        guard let flow else { return }
        if flow.scheduling().planNow(task: task, now: flow.now) != nil {
            flow.moments.show(.hud("\(task.title) planned"))
            editingTaskID = nil
        } else {
            flow.moments.show(.hud("No free slots left today"))
        }
    }
}

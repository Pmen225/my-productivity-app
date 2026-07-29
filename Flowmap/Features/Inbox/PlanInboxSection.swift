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
    @State private var showingDuel = false
    @State private var showingPlanPreview = false
    @State private var planProposal: PlanProposal?

    private var inbox: [FlowTask] {
        SmartView.inbox.matches(allTasks)
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
        .sheet(isPresented: $showingDuel) { PrioritiseDuelView(tasks: inbox) }
        .sheet(isPresented: $showingPlanPreview) {
            PlanPreviewView(
                proposal: planProposal ?? PlanProposal(),
                tasksByID: Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) }),
                onApply: applyPlan,
                onReplanWholeDay: replanWholeDay
            )
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
        VStack(spacing: FlowSpacing.s) {
            // The duel only has something to say once there are two tasks to
            // compare — the same rule `TaskListScreen` used before Plan existed.
            if PrioritiseDuel.isAvailable(for: inbox.map(\.id)) {
                SecondaryActionButton("Play the game", systemImage: "play.fill") {
                    showingDuel = true
                }
            }
            // Decision 12: the whole day is previewed before it moves.
            PrimaryActionButton("Start planning") {
                planProposal = flow?.planToday(replanExisting: false)
                showingPlanPreview = true
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

    private func applyPlan() {
        guard let flow, let planProposal else { return }
        flow.applyPlan(planProposal, replanExisting: false)
        showingPlanPreview = false
    }

    private func replanWholeDay() {
        guard let flow else { return }
        planProposal = flow.planToday(replanExisting: true)
    }
}

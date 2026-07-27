import SwiftUI

/// Previews a `Plan my day` proposal before anything is written. Changed
/// blocks are highlighted, deferred work and unplaceable reasons are called
/// out plainly, and the user can widen the action to a full replan.
struct PlanPreviewView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    let proposal: PlanProposal
    let tasksByID: [UUID: FlowTask]
    let onApply: () -> Void
    let onReplanWholeDay: () -> Void

    private var changedBlocks: [PlannedBlock] {
        proposal.blocks.filter { block in
            guard let existingID = block.existingSegmentID else { return true }
            return !proposal.unchangedSegmentIDs.contains(existingID)
        }
    }

    private var deferredTasks: [FlowTask] {
        proposal.deferredTaskIDs.compactMap { tasksByID[$0] }
    }

    var body: some View {
        NavigationStack {
            Group {
                if proposal.isEmpty {
                    FlowEmptyState(
                        symbol: "checkmark.circle",
                        title: "Nothing to plan",
                        message: "Your day already looks complete."
                    )
                } else {
                    List {
                        if !changedBlocks.isEmpty {
                            Section("New and moved blocks") {
                                ForEach(Array(changedBlocks.enumerated()), id: \.offset) { _, block in
                                    planRow(for: block)
                                }
                            }
                        }
                        if !deferredTasks.isEmpty {
                            Section("Moved to a later day") {
                                ForEach(deferredTasks) { task in
                                    Text(task.title).font(FlowFont.secondary)
                                }
                            }
                        }
                        if !proposal.unplaceable.isEmpty {
                            Section("Could not be placed") {
                                ForEach(Array(proposal.unplaceable.values), id: \.self) { reason in
                                    Text(reason)
                                        .font(FlowFont.secondary)
                                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Plan my day")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: FlowSpacing.s) {
                    PrimaryActionButton("Apply plan") {
                        onApply()
                        dismiss()
                    }
                    SecondaryActionButton("Replan the whole day", systemImage: "arrow.triangle.2.circlepath") {
                        onReplanWholeDay()
                    }
                }
                .padding(FlowSpacing.screen)
                .background(.bar)
            }
        }
    }

    @ViewBuilder
    private func planRow(for block: PlannedBlock) -> some View {
        let task = tasksByID[block.taskID]
        HStack(spacing: FlowSpacing.s) {
            Image(systemName: task?.iconName ?? "circle")
                .foregroundStyle(task?.colour.onSoft ?? FlowTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(task?.title ?? "Task")
                    .font(FlowFont.cardTitle)
                Text(DurationFormatter.timeRange(from: block.start, to: block.end))
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }
            Spacer()
            DurationChip(minutes: block.minutes, tint: task?.colour)
        }
        .listRowBackground(FlowTheme.accent.opacity(0.08))
    }
}

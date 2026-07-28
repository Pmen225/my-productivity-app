import SwiftUI

/// The mock's 3-up stat-tile row: Completed, Carried, Focus. Deliberately
/// plain — a number and a label, no colour-coded pass/fail, no red.
/// Completion rate lives in the summary card instead, since a fourth tile
/// would break the row out of the mock's three-across proportions.
struct ProgressStatTilesRow: View {
    let summary: ProgressSummary

    var body: some View {
        HStack(spacing: FlowSpacing.s) {
            StatTile(value: "\(summary.completedTaskCount)", label: "Completed")
            StatTile(value: "\(summary.carryoverCount)", label: "Carried")
            StatTile(value: DurationFormatter.compact(minutes: summary.actualMinutes), label: "Focus")
        }
    }
}

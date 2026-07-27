import SwiftUI

/// The four headline tiles. Deliberately plain: a number, a label, and — for
/// completion rate — a neutral fraction. No colour-coded pass/fail, no red.
struct ProgressMetricsGrid: View {
    @Environment(\.colorScheme) private var scheme

    let summary: ProgressSummary

    private let columns = [
        GridItem(.flexible(), spacing: FlowSpacing.m),
        GridItem(.flexible(), spacing: FlowSpacing.m),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: FlowSpacing.m) {
            tile(
                title: "Completed",
                value: "\(summary.completedTaskCount)",
                accessibilityValue: "\(summary.completedTaskCount) tasks completed"
            )
            tile(
                title: "Focus minutes",
                value: "\(DurationFormatter.compact(minutes: summary.actualMinutes)) of \(DurationFormatter.compact(minutes: summary.plannedMinutes))",
                accessibilityValue: "\(DurationFormatter.spoken(minutes: summary.actualMinutes)) actual of \(DurationFormatter.spoken(minutes: summary.plannedMinutes)) planned"
            )
            tile(
                title: "Carried over",
                value: "\(summary.carryoverCount)",
                accessibilityValue: "\(summary.carryoverCount) tasks carried over"
            )
            tile(
                title: "Completion rate",
                value: completionRateLabel,
                accessibilityValue: completionRateAccessibilityLabel
            )
        }
    }

    private var completionRateLabel: String {
        guard let rate = summary.completionRate else { return "—" }
        return "\(Int((rate * 100).rounded()))%"
    }

    private var completionRateAccessibilityLabel: String {
        guard let rate = summary.completionRate else { return "Nothing planned in this period" }
        return "\(Int((rate * 100).rounded())) percent completion rate"
    }

    private func tile(title: String, value: String, accessibilityValue: String) -> some View {
        FlowCard(padding: FlowSpacing.l) {
            VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                    .tracking(0.4)
                Text(value)
                    .font(FlowFont.screenTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }
}

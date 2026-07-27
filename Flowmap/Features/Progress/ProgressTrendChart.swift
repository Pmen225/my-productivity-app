import Charts
import SwiftUI

/// Planned versus actual focus minutes, one bar pair per day in the selected
/// period. Deliberately the only chart on this screen — a second one would be
/// dashboard, not progress.
struct ProgressTrendChart: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let points: [ProgressTrendPoint]

    var body: some View {
        FlowCard {
            VStack(alignment: .leading, spacing: FlowSpacing.m) {
                CompactSectionHeader(title: "Trend")
                if points.isEmpty {
                    FlowEmptyState(
                        symbol: "chart.bar",
                        title: "No data yet",
                        message: "Plan or focus on a task to see a trend here."
                    )
                } else {
                    chart
                    legend
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Minutes", point.plannedMinutes)
                )
                .foregroundStyle(FlowTheme.separator(scheme))
                .position(by: .value("Series", "Planned"))

                BarMark(
                    x: .value("Day", point.day, unit: .day),
                    y: .value("Minutes", point.actualMinutes)
                )
                .foregroundStyle(FlowTheme.accent)
                .position(by: .value("Series", "Actual"))
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .animation(reduceMotion ? nil : .default, value: points)
        .frame(height: 160)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Planned versus actual focus minutes by day")
        .accessibilityValue(accessibilitySummary)
    }

    /// VoiceOver gets the totals rather than having to trace bars.
    private var accessibilitySummary: String {
        let planned = points.reduce(0) { $0 + $1.plannedMinutes }
        let actual = points.reduce(0) { $0 + $1.actualMinutes }
        return "\(DurationFormatter.spoken(minutes: actual)) actual of \(DurationFormatter.spoken(minutes: planned)) planned across \(points.count) day\(points.count == 1 ? "" : "s")"
    }

    private var legend: some View {
        HStack(spacing: FlowSpacing.l) {
            legendSwatch(colour: FlowTheme.separator(scheme), label: "Planned")
            legendSwatch(colour: FlowTheme.accent, label: "Actual")
        }
        .font(FlowFont.caption)
        .foregroundStyle(FlowTheme.secondaryText(scheme))
    }

    private func legendSwatch(colour: Color, label: String) -> some View {
        HStack(spacing: FlowSpacing.xs) {
            Circle().fill(colour).frame(width: 8, height: 8)
            Text(label)
        }
    }
}

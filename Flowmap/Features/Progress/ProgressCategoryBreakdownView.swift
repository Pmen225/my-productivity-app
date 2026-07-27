import SwiftUI

/// Where focus time went, broken down by the task's `colourToken` — the same
/// colour shown on that task everywhere else in the app.
struct ProgressCategoryBreakdownView: View {
    @Environment(\.colorScheme) private var scheme

    let slices: [ProgressCategorySlice]

    private var totalMinutes: Int { slices.reduce(0) { $0 + $1.minutes } }

    var body: some View {
        FlowCard {
            VStack(alignment: .leading, spacing: FlowSpacing.m) {
                CompactSectionHeader(title: "By category")
                if slices.isEmpty {
                    FlowEmptyState(
                        symbol: "chart.pie",
                        title: "Nothing to break down yet",
                        message: "Completed tasks and focus sessions will appear here by category."
                    )
                } else {
                    VStack(spacing: FlowSpacing.s) {
                        ForEach(slices) { slice in
                            row(for: slice)
                        }
                    }
                }
            }
        }
    }

    private func row(for slice: ProgressCategorySlice) -> some View {
        let share = totalMinutes > 0 ? Double(slice.minutes) / Double(totalMinutes) : 0

        return VStack(alignment: .leading, spacing: FlowSpacing.xxs) {
            HStack(spacing: FlowSpacing.s) {
                Circle().fill(slice.token.base).frame(width: 10, height: 10)
                Text(slice.token.displayName)
                    .font(FlowFont.secondary)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                Spacer(minLength: FlowSpacing.s)
                Text("\(slice.completedCount) done")
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                DurationChip(minutes: slice.minutes, tint: slice.token)
            }

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: FlowRadius.pill, style: .continuous)
                    .fill(FlowTheme.separator(scheme))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: FlowRadius.pill, style: .continuous)
                            .fill(slice.token.base)
                            .frame(width: proxy.size.width * share)
                    }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slice.token.displayName)
        .accessibilityValue(
            "\(slice.completedCount) completed, \(DurationFormatter.spoken(minutes: slice.minutes))"
        )
    }
}

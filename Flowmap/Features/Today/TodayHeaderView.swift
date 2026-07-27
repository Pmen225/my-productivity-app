import SwiftUI

/// Date, greeting, plan status and the compact completion summary — the
/// scannable header above the timeline. Purely presentational: every figure
/// is derived by `TodayView` from the current segments.
struct TodayHeaderView: View {
    @Environment(\.colorScheme) private var scheme

    let date: Date
    let plannedMinutes: Int
    let remainingMinutes: Int
    let completedCount: Int
    let totalCount: Int
    let action: TodayPrimaryAction
    let onPrimaryAction: () -> Void

    private var greeting: String {
        switch Calendar.current.component(.hour, from: date) {
        case 0..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateLabel)
                    .font(FlowFont.caption.weight(.semibold))
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
                Text(greeting)
                    .font(FlowFont.screenTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
            }

            HStack(alignment: .top, spacing: FlowSpacing.xl) {
                statusColumn(title: "Planned", minutes: plannedMinutes)
                statusColumn(title: "Remaining", minutes: remainingMinutes)
                Spacer(minLength: FlowSpacing.s)
                if totalCount > 0 {
                    Text("\(completedCount) of \(totalCount) done today")
                        .font(FlowFont.secondary)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                        .accessibilityLabel("\(completedCount) of \(totalCount) tasks done today")
                }
            }

            PrimaryActionButton(action.title, systemImage: action.symbolName, action: onPrimaryAction)
        }
    }

    private func statusColumn(title: String, minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .tracking(0.4)
            Text(DurationFormatter.compact(minutes: minutes))
                .font(FlowFont.cardTitle)
                .foregroundStyle(FlowTheme.primaryText(scheme))
                .accessibilityLabel(DurationFormatter.spoken(minutes: minutes))
        }
    }
}

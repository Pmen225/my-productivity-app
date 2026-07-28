import SwiftUI

/// Tracked date eyebrow, day title and the compact planned/left figures — the
/// scannable header above the NOW strip and timeline. Purely presentational:
/// every figure is derived by `TodayView` from the current segments.
struct TodayHeaderView: View {
    @Environment(\.colorScheme) private var scheme

    let date: Date
    let plannedMinutes: Int
    let remainingMinutes: Int
    let inboxCount: Int
    let action: TodayPrimaryAction
    let onPrimaryAction: () -> Void

    /// Decorative only — see `TodayScope`. Local state keeps the popover a
    /// self-contained visual affordance with no data-layer wiring.
    @State private var scope: TodayScope = .day

    /// HIG override: no token in `FlowControlSize` is exactly 44pt (nearest
    /// are 42/48), so this is a local literal until the design system adds
    /// one — flagged in the report.
    private let minimumHitHeight: CGFloat = 44

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date).uppercased()
    }

    private var pillLabel: String {
        switch action {
        case .planDay: "Plan · \(inboxCount)"
        case .startCurrentTask: "Start"
        }
    }

    private var pillAccessibilityValue: String {
        switch action {
        case .planDay: "\(inboxCount) in inbox"
        case .startCurrentTask: ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            scopeMenu
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(FlowFont.screenTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))

                Spacer(minLength: FlowSpacing.s)

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(DurationFormatter.compact(minutes: plannedMinutes)) planned")
                    Text("\(DurationFormatter.compact(minutes: remainingMinutes)) left")
                }
                .font(FlowFont.caption)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .multilineTextAlignment(.trailing)

                planPill
            }
        }
    }

    /// The mock's Day/Week/Month scope switcher. No `FlowPopoverMenu` exists
    /// yet in `Flowmap/DesignSystem/Components/` (checked before writing
    /// this), so this uses a system `Menu` for now — its rounded-card,
    /// selected-row-in-clay styling is OS-drawn, not the mock's exact look,
    /// pending that component landing.
    private var scopeMenu: some View {
        Menu {
            ForEach(TodayScope.allCases) { option in
                Button {
                    scope = option
                } label: {
                    if option == scope {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            FlowEyebrow(dateLabel)
                .contentShape(Rectangle())
                .frame(minHeight: minimumHitHeight, alignment: .leading)
        }
        .accessibilityLabel("Scope: \(scope.rawValue), showing \(dateLabel.capitalized)")
    }

    /// Outlined, not filled — the mock's "Plan · N" pill sits inline with the
    /// planned/left figures rather than as a full-width primary button.
    private var planPill: some View {
        Button(action: onPrimaryAction) {
            Text(pillLabel)
                .font(FlowFont.caption.weight(.semibold))
                .foregroundStyle(FlowTheme.accent)
                .padding(.horizontal, FlowSpacing.m)
                .frame(minHeight: minimumHitHeight)
                .background(Capsule().strokeBorder(FlowTheme.accent, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityValue(pillAccessibilityValue)
    }
}

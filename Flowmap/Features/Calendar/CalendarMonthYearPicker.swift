import SwiftUI

/// The mock's jump panel: a `‹ 2026 ›` year stepper over a grid of month
/// abbreviations, the anchored month filled in accent. It takes the month
/// grid's place while it is open rather than covering it, so the page never
/// grows a second scrolling layer.
///
/// Stepping the year is a preview — nothing moves until a month is tapped, so
/// a wrong year costs a second tap rather than a lost place in the calendar.
struct CalendarMonthYearPicker: View {
    @Environment(\.colorScheme) private var scheme

    let anchorDate: Date
    let calendar: Calendar
    /// Handed the first day of the chosen month.
    let onSelect: (Date) -> Void

    @State private var year: Int

    init(anchorDate: Date, calendar: Calendar, onSelect: @escaping (Date) -> Void) {
        self.anchorDate = anchorDate
        self.calendar = calendar
        self.onSelect = onSelect
        _year = State(initialValue: calendar.component(.year, from: anchorDate))
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: FlowSpacing.s), count: 4)
    }

    /// Locale-correct short month names in calendar order, so the grid reads
    /// the same way the rest of the calendar does.
    private var monthSymbols: [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        return formatter.shortMonthSymbols ?? []
    }

    private var anchoredMonth: Int? {
        calendar.component(.year, from: anchorDate) == year
            ? calendar.component(.month, from: anchorDate)
            : nil
    }

    var body: some View {
        VStack(spacing: FlowSpacing.m) {
            yearStepper

            LazyVGrid(columns: columns, spacing: FlowSpacing.s) {
                ForEach(0..<monthSymbols.count, id: \.self) { index in
                    monthButton(index: index)
                }
            }
        }
        .padding(FlowSpacing.m)
        .flowGlass(radius: FlowRadius.medium)
        .padding(.horizontal, FlowSpacing.screen)
        .padding(.vertical, FlowSpacing.m)
    }

    private var yearStepper: some View {
        HStack(spacing: FlowSpacing.s) {
            Button { year -= 1 } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            }
            .flowHitTarget()
            .accessibilityLabel("Previous year")

            Spacer(minLength: 0)

            FlowEyebrow(String(year))

            Spacer(minLength: 0)

            Button { year += 1 } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            }
            .flowHitTarget()
            .accessibilityLabel("Next year")
        }
    }

    private func monthButton(index: Int) -> some View {
        let month = index + 1
        let isAnchored = anchoredMonth == month

        return Button {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            if let date = calendar.date(from: components) { onSelect(date) }
        } label: {
            Text(monthSymbols[index].uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .kerning(0.6)
                .foregroundStyle(isAnchored ? .white : FlowTheme.primaryText(scheme))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: FlowRadius.field, style: .continuous)
                        .fill(isAnchored ? FlowTheme.accent : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isAnchored ? [.isButton, .isSelected] : .isButton)
    }
}

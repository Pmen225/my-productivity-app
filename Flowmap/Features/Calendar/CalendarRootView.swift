import SwiftUI

/// Which of the four views is on screen. Day and Agenda are the default
/// working views; Month is for navigation, not dense editing.
enum CalendarMode: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case agenda

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        case .agenda: "Agenda"
        }
    }
}

/// The Calendar feature's entry point: a mode switcher, date navigation, the
/// contextual `+` menu and the four view bodies. Reads/writes only through
/// `flow.scheduling()` and `flow.calendarService` — never a second store.
struct CalendarRootView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme

    @State private var mode: CalendarMode = .day
    @State private var anchorDate: Date = Date()
    @State private var quickAddSheet: CalendarQuickAddSheet?

    private var calendar: Calendar {
        CalendarDateMath.calendar(firstWeekday: flow?.settings.firstWeekday ?? 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(FlowTheme.separator(scheme))
            content
        }
        .background(FlowTheme.background(scheme))
        .sheet(item: $quickAddSheet) { sheet in
            CalendarQuickAddSheetHost(sheet: sheet, anchorDate: anchorDate) {
                quickAddSheet = nil
            }
        }
        .task(id: monthWindowKey) {
            flow?.refreshCalendarWindow(around: anchorDate)
        }
    }

    /// Changes only when the visible month changes, so the calendar window
    /// isn't reloaded on every minor navigation inside the same month.
    private var monthWindowKey: DateComponents {
        calendar.dateComponents([.year, .month], from: anchorDate)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: FlowSpacing.s) {
            HStack {
                Text(titleLabel)
                    .font(FlowFont.screenTitle)
                    .foregroundStyle(FlowTheme.primaryText(scheme))
                Spacer()
                CalendarQuickAddMenu(activeSheet: $quickAddSheet)
            }

            HStack(spacing: FlowSpacing.s) {
                Picker("View", selection: $mode) {
                    ForEach(CalendarMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Spacer(minLength: FlowSpacing.s)

                Button { step(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                Button("Today") {
                    anchorDate = Date()
                }
                .font(FlowFont.caption.weight(.semibold))
                Button { step(1) } label: {
                    Image(systemName: "chevron.right")
                }
            }
        }
        .padding(.horizontal, FlowSpacing.screen)
        .padding(.vertical, FlowSpacing.s)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .day:
            CalendarDayView(day: anchorDate)
        case .week:
            CalendarWeekView(anchorDate: anchorDate) { day in
                anchorDate = day
                mode = .day
            }
        case .month:
            CalendarMonthView(anchorDate: anchorDate) { day in
                anchorDate = day
                mode = .day
            }
        case .agenda:
            CalendarAgendaView(anchorDate: anchorDate, dayCount: 21) { day in
                anchorDate = day
                mode = .day
            }
        }
    }

    private var titleLabel: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        switch mode {
        case .day, .agenda:
            formatter.setLocalizedDateFormatFromTemplate("EEEEMMMd")
        case .week:
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
        case .month:
            formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        }
        return formatter.string(from: anchorDate)
    }

    // MARK: - Navigation

    private func step(_ direction: Int) {
        switch mode {
        case .day, .agenda:
            anchorDate = CalendarDateMath.addingDays(direction, to: anchorDate, calendar: calendar)
        case .week:
            anchorDate = CalendarDateMath.addingDays(direction * 7, to: anchorDate, calendar: calendar)
        case .month:
            anchorDate = CalendarDateMath.addingMonths(direction, to: anchorDate, calendar: calendar)
        }
    }
}

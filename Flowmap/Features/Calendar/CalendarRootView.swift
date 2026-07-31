import SwiftUI

/// Which page of the panel under the month grid is showing. The two pages the
/// design calls for: the selected day's schedule, and the whole week grouped by
/// the branch each task came off.
enum CalendarPanelPage: String, CaseIterable, Identifiable {
    case agenda
    case weeklyPlan

    var id: String { rawValue }

    var eyebrowTitle: String {
        switch self {
        case .agenda: "AGENDA"
        case .weeklyPlan: "WEEKLY PLAN"
        }
    }
}

/// The Calendar feature's entry point: month navigation, the month grid, and a
/// two-page panel underneath it. Reads/writes only through `flow.scheduling()`
/// and `flow.calendarService` — never a second store.
///
/// The grid is fixed in place rather than scrolling, which is what lets it own
/// a horizontal drag (decision 17) without fighting the panel's own scrolling
/// and paging underneath it.
struct CalendarRootView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var anchorDate: Date = Date()
    @State private var page: CalendarPanelPage = .agenda
    @State private var isPickingMonth = false

    /// Opening the jump panel swaps out half the screen — a spring settle.
    /// Reduce Motion drops straight to a plain cross-fade.
    private var panelSwitchAnimation: Animation? {
        reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.86)
    }

    /// Stepping to another day or month is lighter — a quiet settle.
    private var scopeChangeAnimation: Animation? {
        reduceMotion ? .linear(duration: 0.12) : .smooth
    }

    private var calendar: Calendar {
        CalendarDateMath.calendar(firstWeekday: flow?.settings.firstWeekday ?? 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(FlowTheme.separator(scheme))
            monthArea
            panel
        }
        .background(FlowTheme.background(scheme))
        .navigationTitle("Calendar")
        .flowScreenTitle("Calendar")
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

    /// The mock hides "Today" until there is somewhere to go back to, so the
    /// row stays quiet on the day you are already looking at.
    private var isOnToday: Bool {
        calendar.isDateInToday(anchorDate)
    }

    private var header: some View {
        HStack(spacing: FlowSpacing.xs) {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(FlowFont.caption.weight(.semibold))
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            }
            .flowHitTarget()
            .accessibilityLabel("Previous month")

            Spacer(minLength: 0)

            Button {
                withAnimation(panelSwitchAnimation) { isPickingMonth.toggle() }
            } label: {
                HStack(spacing: FlowSpacing.xs) {
                    Text(titleLabel)
                        .font(FlowFont.sectionTitle)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                    Image(systemName: "chevron.down")
                        .font(FlowFont.caption.weight(.bold))
                        .foregroundStyle(FlowTheme.tertiaryText(scheme))
                        .rotationEffect(.degrees(isPickingMonth ? 180 : 0))
                }
            }
            .buttonStyle(.plain)
            .flowHitTarget()
            .accessibilityLabel("\(titleLabel), choose month")
            .accessibilityAddTraits(isPickingMonth ? [.isButton, .isSelected] : .isButton)

            Spacer(minLength: 0)

            if !isOnToday {
                Button("Today") {
                    anchorDate = Date()
                }
                .font(FlowFont.caption.weight(.semibold))
                .foregroundStyle(FlowTheme.accentText(scheme))
                .flowHitTarget()
            }

            Button { step(1) } label: {
                Image(systemName: "chevron.right")
                    .font(FlowFont.caption.weight(.semibold))
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            }
            .flowHitTarget()
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, FlowSpacing.screen)
        .padding(.vertical, FlowSpacing.xs)
        .animation(scopeChangeAnimation, value: isOnToday)
    }

    // MARK: - Month grid / jump panel

    @ViewBuilder
    private var monthArea: some View {
        if isPickingMonth {
            CalendarMonthYearPicker(anchorDate: anchorDate, calendar: calendar) { month in
                anchorDate = month
                withAnimation(panelSwitchAnimation) { isPickingMonth = false }
            }
            .transition(.opacity)
        } else {
            CalendarMonthView(anchorDate: anchorDate) { day in
                anchorDate = day
            } onStepMonth: { direction in
                withAnimation(scopeChangeAnimation) { step(direction) }
            }
            .transition(.opacity)
        }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            HStack {
                FlowEyebrow(page.eyebrowTitle)
                Spacer()
                pageDots
            }
            .padding(.horizontal, FlowSpacing.screen)

            pages
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(CalendarPanelPage.allCases) { candidate in
                Button {
                    withAnimation(.snappy(duration: 0.24)) { page = candidate }
                } label: {
                    Circle()
                        .fill(
                            candidate == page
                                ? FlowTheme.accent
                                : FlowTheme.separator(scheme)
                        )
                        .frame(width: 6, height: 6)
                        // Same HIG override as the focus card's pager: full
                        // 44pt of height, 24pt of width, so the pair still
                        // reads as one control rather than two far-apart dots.
                        .frame(width: 24, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(candidate.eyebrowTitle)
                .accessibilityAddTraits(candidate == page ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    @ViewBuilder
    private var pages: some View {
        #if os(macOS)
        // A segmented switch reads better than a swipe on a pointer-driven Mac.
        Picker("Page", selection: $page) {
            ForEach(CalendarPanelPage.allCases) { Text($0.eyebrowTitle.capitalized).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, FlowSpacing.screen)
        pageContent(page)
        #else
        TabView(selection: $page) {
            ForEach(CalendarPanelPage.allCases) { candidate in
                pageContent(candidate).tag(candidate)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        #endif
    }

    @ViewBuilder
    private func pageContent(_ candidate: CalendarPanelPage) -> some View {
        switch candidate {
        case .agenda: CalendarDayAgendaView(day: anchorDate)
        case .weeklyPlan: CalendarWeeklyPlanView(anchorDate: anchorDate)
        }
    }

    private var titleLabel: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter.string(from: anchorDate)
    }

    // MARK: - Navigation

    private func step(_ direction: Int) {
        anchorDate = CalendarDateMath.addingMonths(direction, to: anchorDate, calendar: calendar)
    }
}

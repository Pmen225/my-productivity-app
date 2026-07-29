import SwiftData
import SwiftUI

/// What the Map + Today page's right-hand pane shows when the scope is wider
/// than a day: the week as a list of days, or the month as a list of weeks.
///
/// Both are read-only summaries. Anything that moves work happens on the day
/// itself, so there is nothing here to drag, drop or plan — this is the view
/// that answers "what does the shape of the next stretch look like".
struct ScopeAgendaView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme

    @Query(sort: \TaskSegment.startDate) private var allSegments: [TaskSegment]

    let scope: TodayScope

    private var calendar: Calendar { Calendar.current }
    private var now: Date { flow?.now ?? Date() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowSpacing.xl) {
                switch scope {
                case .week, .day: weekBody
                case .month: monthBody
                }
            }
            .padding(FlowSpacing.screen)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(FlowTheme.background(scheme).ignoresSafeArea())
        .navigationTitle(scope.paneTitle)
    }

    // MARK: - Week

    /// Seven days from today, each with the blocks planned on it. Today comes
    /// first and says so, rather than starting the week on a Monday the user
    /// may already be past.
    private var weekBody: some View {
        ForEach(0..<7, id: \.self) { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
            let blocks = segments(on: day)
            VStack(alignment: .leading, spacing: FlowSpacing.s) {
                FlowEyebrow(dayLabel(day, isToday: offset == 0))
                if blocks.isEmpty {
                    Text("Nothing planned.")
                        .font(FlowFont.secondary)
                        .foregroundStyle(FlowTheme.tertiaryText(scheme))
                } else {
                    ForEach(blocks) { segment in
                        agendaRow(segment)
                    }
                }
            }
        }
    }

    private func agendaRow(_ segment: TaskSegment) -> some View {
        HStack(spacing: FlowSpacing.m) {
            Text(timeLabel(segment.startDate))
                .font(FlowFont.durationChip)
                .foregroundStyle(FlowTheme.tertiaryText(scheme))
                .frame(width: 48, alignment: .leading)
            Circle()
                .fill(segment.task?.colour.base ?? FlowTheme.accent)
                .frame(width: 8, height: 8)
            Text(segment.task?.title ?? "Focus")
                .font(FlowFont.secondary)
                .strikethrough(segment.state == .completed)
                .foregroundStyle(
                    segment.state == .completed
                        ? FlowTheme.tertiaryText(scheme)
                        : FlowTheme.primaryText(scheme)
                )
            Spacer(minLength: 0)
            DurationChip(minutes: segment.durationMinutes)
        }
    }

    // MARK: - Month

    /// Four weeks from the one containing today, each summarised. A week with
    /// nothing in it says so rather than showing a zero, because zero planned
    /// and nothing planned yet are different things to a person reading it.
    private var monthBody: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.l) {
            FlowEyebrow(monthLabel)
            ForEach(0..<4, id: \.self) { offset in
                weekSummaryRow(offset: offset)
            }
        }
    }

    private func weekSummaryRow(offset: Int) -> some View {
        let start = weekStart(offset: offset)
        let blocks = segments(inWeekStarting: start)
        let minutes = blocks.reduce(0) { $0 + $1.durationMinutes }
        let isCurrent = offset == 0
        return HStack {
            Text("Week of \(dayMonthLabel(start))")
                .font(isCurrent ? FlowFont.cardTitle : FlowFont.secondary)
                .foregroundStyle(FlowTheme.primaryText(scheme))
            Spacer(minLength: 0)
            Text(
                blocks.isEmpty
                    ? "Not planned yet"
                    : "\(blocks.count) tasks · \(DurationFormatter.compact(minutes: minutes))"
            )
            .font(FlowFont.caption)
            .foregroundStyle(blocks.isEmpty ? FlowTheme.tertiaryText(scheme) : FlowTheme.secondaryText(scheme))
        }
        .padding(.vertical, FlowSpacing.xs)
    }

    // MARK: - Data

    private var plannedSegments: [TaskSegment] {
        allSegments.filter { $0.state.occupiesTimeline }
    }

    private func segments(on day: Date) -> [TaskSegment] {
        plannedSegments.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
    }

    private func weekStart(offset: Int) -> Date {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? calendar.startOfDay(for: now)
        return calendar.date(byAdding: .weekOfYear, value: offset, to: thisWeek) ?? thisWeek
    }

    private func segments(inWeekStarting start: Date) -> [TaskSegment] {
        let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
        return plannedSegments.filter { $0.startDate >= start && $0.startDate < end }
    }

    // MARK: - Labels

    private func dayLabel(_ day: Date, isToday: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d"
        let base = formatter.string(from: day)
        return isToday ? "\(base) · Today" : base
    }

    private func dayMonthLabel(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: day)
    }

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: now)
    }

    private func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

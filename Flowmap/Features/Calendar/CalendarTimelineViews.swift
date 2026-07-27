import SwiftUI

/// Shared hour-grid positioning for one day, used by both the Day and Week
/// views so the two never drift out of sync on how a block's time maps to a
/// pixel offset.
private enum TimelineMath {
    /// Minutes since the day's own start, from `Calendar` — never a raw
    /// `timeIntervalSince1970` divide, which would misplace blocks around a
    /// daylight-saving transition.
    static func minutesFromDayStart(_ date: Date, dayStart: Date) -> Double {
        max(0, date.timeIntervalSince(dayStart) / 60)
    }
}

/// One day's column: an hour grid background plus positioned event/segment
/// chips. Used at full scale by `CalendarDayView` and at a compact scale,
/// side by side, by `CalendarWeekView`.
struct CalendarTimelineColumn: View {
    @Environment(\.colorScheme) private var scheme
    let dayStart: Date
    let hourHeight: CGFloat
    let showsHourLabels: Bool
    let showsNowLine: Bool
    let segments: [TaskSegment]
    let events: [ExternalCalendarEvent]
    let now: Date

    private var labelGutter: CGFloat { showsHourLabels ? 44 : 0 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            hourLines
            ForEach(events) { event in
                block(for: ExternalEventBlockView(event: event), start: event.start, end: event.end)
            }
            ForEach(segments) { segment in
                block(for: TaskSegmentBlockView(segment: segment), start: segment.startDate, end: segment.endDate)
            }
            if showsNowLine {
                nowLine
            }
        }
        .frame(height: hourHeight * 24, alignment: .top)
    }

    @ViewBuilder
    private func block(for content: some View, start: Date, end: Date) -> some View {
        let top = CGFloat(TimelineMath.minutesFromDayStart(start, dayStart: dayStart) / 60) * hourHeight
        let minutes = max(15, end.timeIntervalSince(start) / 60)
        let height = CGFloat(minutes / 60) * hourHeight
        content
            .frame(height: max(20, height), alignment: .top)
            .padding(.leading, labelGutter + FlowSpacing.xs)
            .padding(.trailing, FlowSpacing.xs)
            .offset(y: top)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: FlowSpacing.xs) {
                    if showsHourLabels {
                        Text(hourLabel(hour))
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                            .frame(width: labelGutter, alignment: .trailing)
                    }
                    Rectangle()
                        .fill(FlowTheme.separator(scheme))
                        .frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
            }
        }
    }

    private var nowLine: some View {
        let top = CGFloat(TimelineMath.minutesFromDayStart(now, dayStart: dayStart) / 60) * hourHeight
        return HStack(spacing: FlowSpacing.xs) {
            Circle().fill(FlowTheme.accent).frame(width: 6, height: 6)
            Rectangle().fill(FlowTheme.accent).frame(height: 1.5)
        }
        .padding(.leading, labelGutter)
        .offset(y: top - 3)
        .accessibilityHidden(true)
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else { return "\(hour)" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: date)
    }
}

/// The Day view: fixed calendar events (muted) and Flowmap task blocks on a
/// single scrollable 24-hour timeline. This, with Agenda, is a default
/// working view — Month is for navigation only.
struct CalendarDayView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme

    let day: Date

    @State private var now = Date()

    private var calendar: Calendar {
        CalendarDateMath.calendar(firstWeekday: flow?.settings.firstWeekday ?? 2)
    }

    private var dayInterval: DateInterval {
        CalendarDateMath.dayInterval(containing: day, calendar: calendar)
    }

    private var allDayEvents: [ExternalCalendarEvent] {
        (flow?.calendarService.events ?? []).filter {
            $0.isAllDay && $0.start < dayInterval.end && $0.end > dayInterval.start
        }
    }

    private var timedEvents: [ExternalCalendarEvent] {
        (flow?.calendarService.events ?? []).filter {
            !$0.isAllDay && $0.start < dayInterval.end && $0.end > dayInterval.start
        }
    }

    private var segments: [TaskSegment] {
        guard let flow else { return [] }
        return flow.scheduling().allSegments()
            .filter { $0.state.occupiesTimeline }
            .filter { $0.startDate < dayInterval.end && $0.endDate > dayInterval.start }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowSpacing.m) {
                if !allDayEvents.isEmpty {
                    allDaySection
                }
                CalendarTimelineColumn(
                    dayStart: dayInterval.start,
                    hourHeight: 64,
                    showsHourLabels: true,
                    showsNowLine: calendar.isDate(now, inSameDayAs: day),
                    segments: segments,
                    events: timedEvents,
                    now: now
                )
            }
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.vertical, FlowSpacing.m)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private var allDaySection: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Text("All day")
                .font(FlowFont.caption.weight(.semibold))
                .foregroundStyle(FlowTheme.secondaryText(scheme))
            ForEach(allDayEvents) { event in
                ExternalEventBlockView(event: event)
            }
        }
    }
}

/// The Week view: seven compact day columns sharing one hour axis. A lighter
/// weight than Day — good for orientation, not dense editing.
struct CalendarWeekView: View {
    @Environment(\.flow) private var flow

    let anchorDate: Date
    let onSelectDay: (Date) -> Void

    @State private var now = Date()
    private let hourHeight: CGFloat = 40

    private var calendar: Calendar {
        CalendarDateMath.calendar(firstWeekday: flow?.settings.firstWeekday ?? 2)
    }

    private var days: [Date] {
        CalendarDateMath.weekDays(containing: anchorDate, calendar: calendar)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: FlowSpacing.s) {
                header
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: FlowSpacing.s) {
                        ForEach(Array(days.enumerated()), id: \.element) { index, day in
                            column(for: day, showsHourLabels: index == 0)
                                .frame(width: 140)
                        }
                    }
                }
            }
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.vertical, FlowSpacing.m)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private var header: some View {
        HStack(spacing: FlowSpacing.s) {
            ForEach(days, id: \.self) { day in
                Button { onSelectDay(day) } label: {
                    VStack(spacing: 2) {
                        Text(weekdayLabel(day)).font(FlowFont.caption)
                        Text(dayNumberLabel(day)).font(FlowFont.cardTitle)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(weekdayLabel(day)) \(dayNumberLabel(day))")
            }
        }
    }

    private func column(for day: Date, showsHourLabels: Bool) -> some View {
        let interval = CalendarDateMath.dayInterval(containing: day, calendar: calendar)
        let segments = (flow?.scheduling().allSegments() ?? [])
            .filter { $0.state.occupiesTimeline }
            .filter { $0.startDate < interval.end && $0.endDate > interval.start }
        let events = (flow?.calendarService.events ?? [])
            .filter { !$0.isAllDay && $0.start < interval.end && $0.end > interval.start }

        return CalendarTimelineColumn(
            dayStart: interval.start,
            hourHeight: hourHeight,
            showsHourLabels: showsHourLabels,
            showsNowLine: calendar.isDate(now, inSameDayAs: day),
            segments: segments,
            events: events,
            now: now
        )
    }

    private func weekdayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    private func dayNumberLabel(_ date: Date) -> String {
        "\(calendar.component(.day, from: date))"
    }
}

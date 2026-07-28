import SwiftData
import SwiftUI

/// Shared hour-grid positioning for one day, used by `CalendarWeekView` so its
/// compact columns never drift out of sync on how a block's time maps to a
/// pixel offset. The Day view no longer needs this — it reuses Today's own
/// `TimelineView`, which does its own positioning.
private enum TimelineMath {
    /// Minutes since the day's own start, from `Calendar` — never a raw
    /// `timeIntervalSince1970` divide, which would misplace blocks around a
    /// daylight-saving transition.
    static func minutesFromDayStart(_ date: Date, dayStart: Date) -> Double {
        max(0, date.timeIntervalSince(dayStart) / 60)
    }

    /// Greedy interval-graph colouring: each block takes the lowest-numbered
    /// lane free at its start time, and shares the lane count of every other
    /// block it transitively overlaps. Without this, two blocks at the same
    /// time draw on top of each other full-width — a real collision seen
    /// when screenshotting the Week view against the demo seed data.
    ///
    /// Also returns each block's gap to the next block sharing its lane —
    /// the auto-planner packs blocks back-to-back with zero gap, so a block
    /// short enough to need a minimum-height floor must never let that floor
    /// carry it past where the next one in the same lane starts.
    static func assignLanes<Key: Hashable>(
        _ items: [(key: Key, start: Date, end: Date)]
    ) -> [Key: (lane: Int, count: Int, gapToNext: TimeInterval?)] {
        guard !items.isEmpty else { return [:] }
        let order = items.indices.sorted { items[$0].start < items[$1].start }

        var lane = [Int](repeating: 0, count: items.count)
        var clusterID = [Int](repeating: -1, count: items.count)
        var laneEndTimes: [Date] = []
        var clusterEnd: [Date] = []
        var clusterLaneCount: [Int] = []
        var current = -1

        for index in order {
            let item = items[index]
            if current == -1 || item.start >= clusterEnd[current] {
                current += 1
                laneEndTimes = [item.end]
                clusterEnd.append(item.end)
                clusterLaneCount.append(1)
                lane[index] = 0
                clusterID[index] = current
                continue
            }
            let freeLane = laneEndTimes.firstIndex { $0 <= item.start }
            let placedLane = freeLane ?? laneEndTimes.count
            if freeLane == nil {
                laneEndTimes.append(item.end)
            } else {
                laneEndTimes[placedLane] = item.end
            }
            lane[index] = placedLane
            clusterID[index] = current
            clusterEnd[current] = max(clusterEnd[current], item.end)
            clusterLaneCount[current] = max(clusterLaneCount[current], laneEndTimes.count)
        }

        var gapToNext = [TimeInterval?](repeating: nil, count: items.count)
        var laneGroups: [Int: [Int]] = [:]
        for index in items.indices {
            laneGroups[clusterID[index] * 1000 + lane[index], default: []].append(index)
        }
        for (_, group) in laneGroups {
            let sorted = group.sorted { items[$0].start < items[$1].start }
            for position in 0..<(sorted.count - 1) {
                let thisIndex = sorted[position]
                let nextIndex = sorted[position + 1]
                gapToNext[thisIndex] = items[nextIndex].start.timeIntervalSince(items[thisIndex].start)
            }
        }

        var result: [Key: (lane: Int, count: Int, gapToNext: TimeInterval?)] = [:]
        for index in items.indices {
            result[items[index].key] = (lane[index], clusterLaneCount[clusterID[index]], gapToNext[index])
        }
        return result
    }
}

/// One day's column: an hour grid background plus positioned event/segment
/// chips, at the compact scale `CalendarWeekView` uses side by side.
struct CalendarTimelineColumn: View {
    @Environment(\.colorScheme) private var scheme
    let dayStart: Date
    let hourHeight: CGFloat
    let showsHourLabels: Bool
    let showsNowLine: Bool
    let segments: [TaskSegment]
    let events: [ExternalCalendarEvent]
    let now: Date

    private var labelGutter: CGFloat { showsHourLabels ? 32 : 0 }

    /// Keyed by event/segment identity so each ForEach row can look up its
    /// own lane placement without the two block kinds sharing an id space.
    private enum BlockKey: Hashable {
        case event(String)
        case segment(UUID)
    }

    private var lanePlacement: [BlockKey: (lane: Int, count: Int, gapToNext: TimeInterval?)] {
        let items: [(key: BlockKey, start: Date, end: Date)] =
            events.map { (.event($0.id), $0.start, $0.end) } +
            segments.map { (.segment($0.id), $0.startDate, $0.endDate) }
        return TimelineMath.assignLanes(items)
    }

    var body: some View {
        let placement = lanePlacement
        GeometryReader { proxy in
            let usableWidth = max(0, proxy.size.width - labelGutter - FlowSpacing.xxs * 2)
            ZStack(alignment: .topLeading) {
                hourLines
                ForEach(events) { event in
                    let slot = placement[.event(event.id)] ?? (lane: 0, count: 1, gapToNext: nil)
                    block(
                        for: ExternalEventBlockView(event: event),
                        start: event.start, end: event.end,
                        lane: slot.lane, laneCount: slot.count, gapToNext: slot.gapToNext,
                        usableWidth: usableWidth
                    )
                }
                ForEach(segments) { segment in
                    let slot = placement[.segment(segment.id)] ?? (lane: 0, count: 1, gapToNext: nil)
                    block(
                        for: TaskSegmentBlockView(segment: segment),
                        start: segment.startDate, end: segment.endDate,
                        lane: slot.lane, laneCount: slot.count, gapToNext: slot.gapToNext,
                        usableWidth: usableWidth
                    )
                }
                if showsNowLine {
                    nowLine
                }
            }
        }
        .frame(height: hourHeight * 24, alignment: .top)
    }

    @ViewBuilder
    private func block(
        for content: some View, start: Date, end: Date,
        lane: Int, laneCount: Int, gapToNext: TimeInterval?, usableWidth: CGFloat
    ) -> some View {
        let top = CGFloat(TimelineMath.minutesFromDayStart(start, dayStart: dayStart) / 60) * hourHeight
        let minutes = max(15, end.timeIntervalSince(start) / 60)
        let naturalHeight = max(FlowSpacing.l, CGFloat(minutes / 60) * hourHeight)
        // The auto-planner packs blocks back-to-back with no gap, so a short
        // block's minimum-height floor must never carry it past where the
        // next block in its own lane starts — `ViewThatFits` inside the chip
        // (full row → title-only row → icon-only) absorbs whatever height
        // that leaves.
        let height: CGFloat = {
            guard let gapToNext else { return naturalHeight }
            let gapHeight = CGFloat(gapToNext / 60) * hourHeight - FlowSpacing.xxs
            return max(FlowSpacing.xs, min(naturalHeight, gapHeight))
        }()
        let laneWidth = laneCount > 0 ? usableWidth / CGFloat(laneCount) : usableWidth
        content
            .frame(width: max(0, laneWidth - (laneCount > 1 ? FlowSpacing.xxs : 0)), height: height, alignment: .top)
            .padding(.leading, labelGutter + FlowSpacing.xxs + CGFloat(lane) * laneWidth)
            .offset(y: top)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: FlowSpacing.xxs) {
                    if showsHourLabels {
                        Text(hourLabel(hour))
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.tertiaryText(scheme))
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
        return HStack(spacing: FlowSpacing.xxs) {
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
/// single scrollable 24-hour timeline.
///
/// This reuses Today's own `TimelineView` and its drag-to-move logic wholesale
/// — the same hour grid, the same block styling, the same haptics and refusal
/// handling — rather than a second timeline implementation that could drift
/// out of sync with it. It is, deliberately, the Today timeline addressed at
/// a different date.
struct CalendarDayView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TaskSegment.startDate) private var allSegments: [TaskSegment]
    @Query(sort: \FlowTask.sortOrder) private var allTasks: [FlowTask]

    let day: Date

    @State private var now = Date()
    @State private var planProposal: PlanProposal?
    @State private var isReplanningWholeDay = false
    @State private var showPlanPreview = false
    @State private var lastPlanSnapshot: ScheduleSnapshot?
    @State private var showAppliedBanner = false
    @State private var refusalMessage: String?

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
        allSegments
            .filter { $0.state.occupiesTimeline }
            .filter { $0.startDate < dayInterval.end && $0.endDate > dayInterval.start }
    }

    private var timelineBlocks: [TimelineBlock] {
        (segments.map(TimelineBlock.init(segment:)) + timedEvents.map(TimelineBlock.init(event:)))
            .sorted { $0.start < $1.start }
    }

    private var tasksByID: [UUID: FlowTask] {
        Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
    }

    private var isEmptyDay: Bool {
        allDayEvents.isEmpty && timedEvents.isEmpty && segments.isEmpty
    }

    /// Compares by value, not object identity, so a moved block's new start
    /// time actually registers as a change worth animating.
    private var blockMoveAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowSpacing.m) {
                planAction
                if !allDayEvents.isEmpty {
                    allDaySection
                }
                if isEmptyDay {
                    Text("Nothing scheduled for this day.")
                        .font(FlowFont.secondary)
                        .foregroundStyle(FlowTheme.tertiaryText(scheme))
                } else {
                    TimelineView(
                        dayStart: dayInterval.start,
                        dayEnd: dayInterval.end,
                        blocks: timelineBlocks,
                        now: now,
                        lookupTask: { tasksByID[$0] },
                        onSchedule: attemptSchedule,
                        onMove: attemptMove,
                        onRefusal: showRefusal
                    )
                    .animation(blockMoveAnimation, value: segments.map(\.startDate))
                }
            }
            .padding(.horizontal, FlowSpacing.screen)
            .padding(.vertical, FlowSpacing.m)
        }
        .overlay(alignment: .bottom) { banners }
        .sheet(isPresented: $showPlanPreview) {
            PlanPreviewView(
                proposal: planProposal ?? PlanProposal(),
                tasksByID: tasksByID,
                onApply: applyCurrentPlan,
                onReplanWholeDay: replanWholeDay
            )
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    private var planAction: some View {
        SecondaryActionButton(
            calendar.isDateInToday(day) ? "Plan the rest of the day" : "Plan this day",
            systemImage: "sparkles",
            action: openPlanPreview
        )
        .accessibilityLabel(calendar.isDateInToday(day) ? "Plan the rest of the day" : "Plan this day")
    }

    private var allDaySection: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            FlowEyebrow("All day")
            ForEach(allDayEvents) { event in
                ExternalEventBlockView(event: event)
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: FlowSpacing.s) {
            if showAppliedBanner {
                FlowBanner(
                    text: "The plan is updated.",
                    actions: [("Undo", undoAppliedPlan)],
                    onDismiss: { showAppliedBanner = false }
                )
            }
            if let refusalMessage {
                FlowBanner(text: refusalMessage, onDismiss: { self.refusalMessage = nil })
            }
        }
        .padding(.horizontal, FlowSpacing.screen)
        .padding(.bottom, FlowSpacing.screen)
    }

    // MARK: - Planning
    //
    // Calls straight through to `SchedulingService` — the same propose/apply/
    // undo the Today screen uses via `AppEnvironment`'s "today" shortcuts,
    // just addressed at `day` rather than always at "now".

    private func openPlanPreview() {
        guard let flow else { return }
        isReplanningWholeDay = false
        planProposal = flow.scheduling().proposePlan(for: day, now: flow.now)
        showPlanPreview = true
    }

    private func replanWholeDay() {
        guard let flow else { return }
        isReplanningWholeDay = true
        planProposal = flow.scheduling().proposePlan(for: day, now: flow.now, replanExisting: true)
    }

    private func applyCurrentPlan() {
        guard let flow, let planProposal else { return }
        lastPlanSnapshot = flow.scheduling().apply(planProposal, replanExisting: isReplanningWholeDay, for: day)
        flow.notificationService.rescheduleAll(
            segments: flow.upcomingSegments(from: flow.now),
            settings: flow.settings
        )
        self.planProposal = nil
        showAppliedBanner = true
    }

    private func undoAppliedPlan() {
        guard let flow, let lastPlanSnapshot else { return }
        flow.scheduling().undo(lastPlanSnapshot)
        flow.notificationService.rescheduleAll(
            segments: flow.upcomingSegments(from: flow.now),
            settings: flow.settings
        )
        self.lastPlanSnapshot = nil
        showAppliedBanner = false
    }

    // MARK: - Drag/drop, delegated straight to `SchedulingService`

    private func attemptSchedule(_ task: FlowTask, at date: Date) -> Bool {
        guard let flow, flow.scheduling().schedule(task: task, at: date) != nil else { return false }
        TimelineHaptics.dropSucceeded()
        return true
    }

    private func attemptMove(_ segment: TaskSegment, to date: Date) -> Bool {
        guard let flow, flow.scheduling().move(segment: segment, to: date) else { return false }
        TimelineHaptics.dropSucceeded()
        return true
    }

    private func showRefusal(_ message: String) {
        TimelineHaptics.dropRefused()
        refusalMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if refusalMessage == message { refusalMessage = nil }
        }
    }
}

/// The Week view: seven compact day columns sharing one hour axis. A lighter
/// weight than Day — good for orientation, not dense editing, so its blocks
/// are read-only (tap a day to open it in Day view for the drag-to-move
/// interaction).
struct CalendarWeekView: View {
    @Environment(\.flow) private var flow
    @Environment(\.colorScheme) private var scheme
    @Query(sort: \TaskSegment.startDate) private var allSegments: [TaskSegment]

    let anchorDate: Date
    let onSelectDay: (Date) -> Void

    @State private var now = Date()
    private let hourHeight: CGFloat = 40
    private let columnWidth: CGFloat = 132

    private var calendar: Calendar {
        CalendarDateMath.calendar(firstWeekday: flow?.settings.firstWeekday ?? 2)
    }

    private var days: [Date] {
        CalendarDateMath.weekDays(containing: anchorDate, calendar: calendar)
    }

    var body: some View {
        ScrollView(.vertical) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: FlowSpacing.xs) {
                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                        dayColumn(for: day, showsHourLabels: index == 0)
                            .frame(width: columnWidth)
                    }
                }
                .padding(.horizontal, FlowSpacing.screen)
                .padding(.vertical, FlowSpacing.m)
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
    }

    /// Header and hour grid share one column so today's lift reads as a single
    /// surface, not a tinted header floating over an untinted grid.
    private func dayColumn(for day: Date, showsHourLabels: Bool) -> some View {
        let isToday = calendar.isDateInToday(day)

        return VStack(alignment: .leading, spacing: FlowSpacing.xs) {
            Button { onSelectDay(day) } label: {
                VStack(spacing: 2) {
                    Text(weekdayLabel(day)).font(FlowFont.caption)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                    Text(dayNumberLabel(day)).font(FlowFont.cardTitle)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(weekdayLabel(day)) \(dayNumberLabel(day))")

            column(for: day, showsHourLabels: showsHourLabels)
        }
        .padding(FlowSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .fill(isToday ? FlowTheme.surface(scheme) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FlowRadius.medium, style: .continuous)
                .strokeBorder(isToday ? FlowTheme.separatorStrong(scheme) : .clear, lineWidth: 1)
        )
    }

    private func column(for day: Date, showsHourLabels: Bool) -> some View {
        let interval = CalendarDateMath.dayInterval(containing: day, calendar: calendar)
        let segments = allSegments
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

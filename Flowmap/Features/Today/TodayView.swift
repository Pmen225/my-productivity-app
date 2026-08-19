import SwiftData
import SwiftUI

/// The operational home screen: plan status, the day's timeline and the
/// unscheduled Inbox. Works on both iPhone (stacked, scrolled to the current
/// time) and Mac (timeline and Inbox side by side when width allows).
struct TodayView: View {
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \FlowTask.sortOrder) private var allTasks: [FlowTask]
    @Query(sort: \TaskSegment.startDate) private var allSegments: [TaskSegment]

    @State private var planProposal: PlanProposal?
    @State private var isReplanningWholeDay = false
    @State private var showPlanPreview = false
    @State private var showAppliedBanner = false
    @State private var refusalMessage: String?
    @State private var inspectedTask: FlowTask?
    @State private var selectedDate = Date()
    @State private var monthAnchor = Date()
    @State private var isMonthExpanded = false
    @State private var hasInitialisedDate = false
    /// Wide enough on Mac to show the timeline and Inbox side by side.
    @State private var containerWidth: CGFloat = 900

    private let calendar = Calendar.current

    private var now: Date { flow?.now ?? Date() }

    private var navigationCalendar: Calendar {
        CalendarDateMath.calendar(firstWeekday: flow?.settings.firstWeekday ?? 2)
    }

    private var isSelectedDateToday: Bool {
        calendar.isDate(selectedDate, inSameDayAs: now)
    }

    private var weekDates: [Date] {
        CalendarDateMath.weekDays(containing: selectedDate, calendar: navigationCalendar)
    }

    private var dayStart: Date {
        flow?.settings.workdayStart(on: selectedDate, calendar: calendar)
            ?? calendar.startOfDay(for: selectedDate)
    }

    private var dayEnd: Date {
        flow?.settings.workdayEnd(on: selectedDate, calendar: calendar)
            ?? dayStart.addingTimeInterval(13 * 3600)
    }

    private var daySegments: [TaskSegment] {
        allSegments
            .filter { $0.state.occupiesTimeline }
            .filter { $0.startDate < dayEnd && $0.endDate > dayStart }
            .sorted { $0.startDate < $1.startDate }
    }

    private var externalEvents: [ExternalCalendarEvent] {
        guard let flow else { return [] }
        return flow.calendarService.busyEvents(in: flow.calendarService.events)
            .filter { $0.start < dayEnd && $0.end > dayStart }
    }

    private var timelineBlocks: [TimelineBlock] {
        (daySegments.map(TimelineBlock.init(segment:)) + externalEvents.map(TimelineBlock.init(event:)))
            .sorted { $0.start < $1.start }
    }

    private var inboxTasks: [FlowTask] {
        SmartView.inbox.matches(allTasks, now: now, calendar: calendar)
    }

    private var tasksByID: [UUID: FlowTask] {
        Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
    }

    private var plannedMinutes: Int {
        daySegments.reduce(0) { $0 + $1.durationMinutes }
    }

    private var remainingMinutes: Int {
        daySegments
            .filter { $0.state == .scheduled }
            .reduce(0) {
                $0 + (isSelectedDateToday
                    ? Int(($1.remainingSeconds(at: now) / 60).rounded())
                    : $1.durationMinutes)
            }
    }

    private var primaryAction: TodayPrimaryAction {
        if let segment = flow?.focusEngine.currentSegment(at: now) {
            return .startCurrentTask(segment: segment)
        }
        return .planDay
    }

    /// Only a session that is actually running counts as "live" — a merely
    /// scheduled segment belongs in the timeline, not the strip.
    private var liveSession: FocusSession? { flow?.focusEngine.activeSession }

    var body: some View {
        ScrollView {
            platformLayout
        }
        .scrollIndicators(.hidden)
        .background(FlowTheme.background(scheme))
        .overlay(alignment: .bottom) { banners }
        .sheet(isPresented: $showPlanPreview) {
            PlanPreviewView(
                proposal: planProposal ?? PlanProposal(),
                tasksByID: tasksByID,
                onApply: applyCurrentPlan,
                onReplanWholeDay: replanWholeDay
            )
        }
        .sheet(item: $inspectedTask) { task in
            NavigationStack { TaskDetailInspector(task: task) }
        }
        .onAppear {
            if !hasInitialisedDate {
                selectedDate = calendar.startOfDay(for: now)
                monthAnchor = selectedDate
                hasInitialisedDate = true
            }
            flow?.refreshCalendarWindow(around: selectedDate)
        }
        .onChange(of: selectedDate) { _, date in
            flow?.refreshCalendarWindow(around: date)
        }
    }

    // MARK: - Layout

    @ViewBuilder
    private var platformLayout: some View {
        #if os(macOS)
        Group {
            if containerWidth > 680 {
                sideBySide
            } else {
                stacked
            }
        }
        .padding(FlowSpacing.screen)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        #else
        openAIPhoneLayout
        #endif
    }

    private var openAIPhoneLayout: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: FlowSpacing.l) {
                VStack(alignment: .leading, spacing: FlowSpacing.s) {
                    Text(selectedDayTitle)
                        .font(FlowFont.screenTitle)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                        .accessibilityIdentifier("today-selected-date-title")

                    Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(FlowFont.secondary)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                }

                Spacer(minLength: 0)

                if isSelectedDateToday {
                    Button(action: performPrimaryAction) {
                        Image(systemName: primaryActionSymbol)
                            .font(FlowFont.sectionTitle)
                            .foregroundStyle(.white)
                            .frame(width: FlowControlSize.secondary, height: FlowControlSize.secondary)
                            .background(Circle().fill(FlowTheme.accentFill))
                    }
                    .buttonStyle(TodayOpenAIPressStyle())
                    .accessibilityLabel(primaryActionLabel)
                }
            }
            .padding(.top, FlowSpacing.xxxl)

            dateNavigation
                .padding(.top, FlowSpacing.l)

            Text(daySummary)
                .font(FlowFont.secondary)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .padding(.top, FlowSpacing.l)

            if isSelectedDateToday, liveSession != nil {
                openAINowRow
                    .padding(.top, FlowSpacing.xxl)
            }

            openAISectionLabel("Schedule")
                .padding(.top, FlowSpacing.xxxl)

            if timelineBlocks.isEmpty {
                openAIEmptySchedule
            } else {
                ForEach(Array(timelineBlocks.enumerated()), id: \.element.id) { index, block in
                    openAITimelineRow(block)
                    if index < timelineBlocks.count - 1 {
                        Divider()
                            .overlay(FlowTheme.separator(scheme))
                            .padding(.leading, FlowSpacing.xxxl + FlowSpacing.xl)
                    }
                }
            }

            if isSelectedDateToday {
                Button(action: openPlanPreview) {
                    HStack(spacing: FlowSpacing.s) {
                        Text(timelineBlocks.isEmpty ? "Plan this day" : "Adjust this plan")
                            .font(FlowFont.cardTitle)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                            .font(FlowFont.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, FlowSpacing.l)
                    .frame(maxWidth: .infinity, minHeight: FlowControlSize.secondary)
                    .background(Capsule().fill(FlowTheme.accentFill))
                }
                .buttonStyle(TodayOpenAIPressStyle())
                .padding(.top, FlowSpacing.xxxl)
                .accessibilityHint("Opens a preview before changing the schedule")
            }
        }
        .padding(.horizontal, FlowSpacing.screen)
        .padding(.bottom, FlowSpacing.floatingControlsInset)
    }

    private var daySummary: String {
        if timelineBlocks.isEmpty {
            return isSelectedDateToday
                ? "Your day is open. Nothing is competing for your attention."
                : "Nothing is scheduled on this day."
        }
        let blockWord = timelineBlocks.count == 1 ? "block" : "blocks"
        return isSelectedDateToday
            ? "\(timelineBlocks.count) \(blockWord) · \(DurationFormatter.spoken(minutes: remainingMinutes)) remaining"
            : "\(timelineBlocks.count) \(blockWord) · \(DurationFormatter.spoken(minutes: plannedMinutes)) scheduled"
    }

    private var selectedDayTitle: String {
        isSelectedDateToday
            ? "Today"
            : selectedDate.formatted(.dateTime.weekday(.wide))
    }

    private var dateNavigation: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            Button(action: toggleMonthCalendar) {
                HStack(spacing: FlowSpacing.xs) {
                    Text(selectedDate.formatted(.dateTime.month(.wide).year()))
                        .font(FlowFont.caption.weight(.semibold))
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                    Image(systemName: "chevron.down")
                        .font(FlowFont.durationChip)
                        .foregroundStyle(FlowTheme.tertiaryText(scheme))
                        .rotationEffect(.degrees(isMonthExpanded ? 180 : 0))
                    Spacer(minLength: 0)
                }
                .frame(minHeight: FlowControlSize.minimumTouch)
                .contentShape(Rectangle())
            }
            .buttonStyle(TodayOpenAIPressStyle())
            .accessibilityIdentifier("today-month-toggle")
            .accessibilityLabel(isMonthExpanded ? "Hide month calendar" : "Show month calendar")

            HStack(spacing: FlowSpacing.xxs) {
                ForEach(weekDates, id: \.self) { date in
                    dayButton(date)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today-week-strip")
            .contentShape(Rectangle())
            .simultaneousGesture(weekSwipeGesture)

            if isMonthExpanded {
                CalendarMonthView(
                    anchorDate: monthAnchor,
                    onSelectDay: { selectDate($0, collapseMonth: true) },
                    onStepMonth: stepMonth
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("today-month-calendar")
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func toggleMonthCalendar() {
        let update = {
            monthAnchor = selectedDate
            isMonthExpanded.toggle()
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(FlowMotion.selection, update)
        }
    }

    private func dayButton(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDate(date, inSameDayAs: now)

        return Button {
            selectDate(date, collapseMonth: false)
        } label: {
            VStack(spacing: FlowSpacing.xs) {
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .font(FlowFont.durationChip)
                Text(date.formatted(.dateTime.day()))
                    .font(FlowFont.caption.weight(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(
                isSelected
                    ? FlowTheme.background(scheme)
                    : isToday
                        ? FlowTheme.accentText(scheme)
                        : FlowTheme.secondaryText(scheme)
            )
            .frame(maxWidth: .infinity, minHeight: FlowControlSize.minimumTouch)
            .background(
                RoundedRectangle(cornerRadius: FlowRadius.field, style: .continuous)
                    .fill(isSelected ? FlowTheme.primaryText(scheme) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(TodayOpenAIPressStyle())
        .accessibilityIdentifier(dayIdentifier(date))
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var weekSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let horizontal = abs(value.translation.width)
                guard horizontal > 50, horizontal > abs(value.translation.height) else { return }
                let offset = value.translation.width < 0 ? 1 : -1
                guard let date = calendar.date(byAdding: .day, value: offset, to: selectedDate) else { return }
                selectDate(date, collapseMonth: false)
            }
    }

    private func selectDate(_ date: Date, collapseMonth: Bool) {
        let update = {
            selectedDate = calendar.startOfDay(for: date)
            monthAnchor = selectedDate
            if collapseMonth { isMonthExpanded = false }
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(FlowMotion.selection, update)
        }
    }

    private func stepMonth(_ step: Int) {
        guard let date = calendar.date(byAdding: .month, value: step, to: monthAnchor) else { return }
        withAnimation(reduceMotion ? nil : FlowMotion.selection) {
            monthAnchor = date
        }
    }

    private func dayIdentifier(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "today-day-%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private var primaryActionLabel: String {
        switch primaryAction {
        case .startCurrentTask: "Start focus"
        case .planDay: timelineBlocks.isEmpty ? "Plan day" : "Adjust plan"
        }
    }

    private var primaryActionSymbol: String {
        switch primaryAction {
        case .startCurrentTask: "play.fill"
        case .planDay: "sparkles"
        }
    }

    private func openAISectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(FlowFont.eyebrow)
            .foregroundStyle(FlowTheme.secondaryText(scheme))
            .tracking(0.6)
    }

    @ViewBuilder
    private var openAINowRow: some View {
        if let session = liveSession, let segment = session.segment {
            Button {
                NotificationCenter.default.post(
                    name: .flowmapOpenDeepLink,
                    object: DeepLinkRequest(destination: .focus)
                )
            } label: {
                HStack(spacing: FlowSpacing.m) {
                    Circle()
                        .fill(segment.task?.colour.base ?? FlowTheme.info)
                        .frame(width: FlowSpacing.s, height: FlowSpacing.s)

                    VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                        Text(segment.task?.title ?? "Focus")
                            .font(FlowFont.cardTitle)
                            .foregroundStyle(FlowTheme.primaryText(scheme))
                        Text("In focus · \(session.countdownLabel(at: now))")
                            .font(FlowFont.caption)
                            .foregroundStyle(FlowTheme.secondaryText(scheme))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.right")
                        .font(FlowFont.caption.weight(.semibold))
                        .foregroundStyle(FlowTheme.tertiaryText(scheme))
                }
                .padding(.horizontal, FlowSpacing.l)
                .frame(minHeight: FlowControlSize.create)
                .background(
                    RoundedRectangle(cornerRadius: FlowRadius.large, style: .continuous)
                        .fill(FlowTheme.surfaceSunken(scheme))
                )
            }
            .buttonStyle(TodayOpenAIPressStyle())
            .accessibilityLabel("Open active focus session")
        }
    }

    private var openAIEmptySchedule: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.s) {
            Text("No schedule yet")
                .font(FlowFont.cardTitle)
                .foregroundStyle(FlowTheme.primaryText(scheme))
            Text("Plan the day when you are ready. Flowmap will work around your calendar.")
                .font(FlowFont.secondary)
                .foregroundStyle(FlowTheme.secondaryText(scheme))
        }
        .padding(.vertical, FlowSpacing.xl)
    }

    @ViewBuilder
    private func openAITimelineRow(_ block: TimelineBlock) -> some View {
        let row = HStack(alignment: .top, spacing: FlowSpacing.m) {
            Text(DurationFormatter.time(block.start))
                .font(FlowFont.caption.weight(.semibold))
                .foregroundStyle(FlowTheme.secondaryText(scheme))
                .frame(width: FlowSpacing.xxxl, alignment: .leading)

            Circle()
                .fill(block.colourToken?.base ?? FlowTheme.tertiaryText(scheme))
                .frame(width: FlowSpacing.s, height: FlowSpacing.s)
                .padding(.top, FlowSpacing.xs)

            VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                HStack(spacing: FlowSpacing.s) {
                    Text(block.title)
                        .font(FlowFont.cardTitle)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                        .lineLimit(2)
                    if block.isLocked {
                        Image(systemName: "lock.fill")
                            .font(FlowFont.durationChip)
                            .foregroundStyle(FlowTheme.tertiaryText(scheme))
                    }
                }
                Text(blockMetadata(block))
                    .font(FlowFont.caption)
                    .foregroundStyle(FlowTheme.secondaryText(scheme))
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, FlowSpacing.l)
        .contentShape(Rectangle())

        if let task = block.segment?.task {
            Button { inspectedTask = task } label: { row }
                .buttonStyle(TodayOpenAIPressStyle())
                .accessibilityHint("Opens task details")
        } else {
            row
                .accessibilityElement(children: .combine)
        }
    }

    private func openAIInboxRow(_ task: FlowTask) -> some View {
        Button { inspectedTask = task } label: {
            HStack(alignment: .top, spacing: FlowSpacing.m) {
                Circle()
                    .fill(task.colour.base)
                    .frame(width: FlowSpacing.s, height: FlowSpacing.s)
                    .padding(.top, FlowSpacing.xs)

                VStack(alignment: .leading, spacing: FlowSpacing.xs) {
                    Text(task.title)
                        .font(FlowFont.cardTitle)
                        .foregroundStyle(FlowTheme.primaryText(scheme))
                        .lineLimit(2)
                    Text(DurationFormatter.spoken(minutes: task.estimatedMinutes))
                        .font(FlowFont.caption)
                        .foregroundStyle(FlowTheme.secondaryText(scheme))
                }

                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(FlowFont.caption.weight(.semibold))
                    .foregroundStyle(FlowTheme.tertiaryText(scheme))
            }
            .padding(.vertical, FlowSpacing.l)
            .contentShape(Rectangle())
        }
        .buttonStyle(TodayOpenAIPressStyle())
        .accessibilityHint("Opens task details")
    }

    private func blockMetadata(_ block: TimelineBlock) -> String {
        let end = DurationFormatter.time(block.end)
        let duration = DurationFormatter.spoken(minutes: block.minutes)
        return block.isExternal ? "Calendar · until \(end)" : "Until \(end) · \(duration)"
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xl) {
            header
            nowStrip
            timelineView
            TodayInboxSection(tasks: inboxTasks)
        }
    }

    private var sideBySide: some View {
        HStack(alignment: .top, spacing: FlowSpacing.xl) {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                header
                nowStrip
                timelineView
            }
            .frame(maxWidth: .infinity)

            TodayInboxSection(tasks: inboxTasks)
                .frame(width: 280)
        }
    }

    private var header: some View {
        TodayHeaderView(
            date: now,
            plannedMinutes: plannedMinutes,
            remainingMinutes: remainingMinutes,
            inboxCount: inboxTasks.count,
            action: primaryAction,
            onPrimaryAction: performPrimaryAction
        )
    }

    /// The running task, surfaced above the timeline — wired to the same
    /// `FocusEngine` calls `FocusScreen` uses, so pausing or completing here
    /// is the same action, not a second implementation.
    @ViewBuilder
    private var nowStrip: some View {
        if let session = liveSession, let segment = session.segment {
            NowStrip(
                title: segment.task?.title ?? "Focus",
                countdown: session.countdownLabel(at: now),
                endsLabel: "Ends \(DurationFormatter.time(segment.endDate))",
                progress: session.progress(at: now),
                tint: segment.task?.colour ?? .violet,
                isPaused: session.isPaused,
                onTogglePause: { flow?.focusEngine.togglePause(now: now) },
                onComplete: { flow?.focusEngine.completeCurrentTask(now: now) },
                // The mock's `goFocus`: the whole card is a way back to the
                // task it is describing, not just a readout of it.
                onOpen: {
                    NotificationCenter.default.post(
                        name: .flowmapOpenDeepLink,
                        object: DeepLinkRequest(destination: .focus)
                    )
                }
            )
        }
    }

    private var timelineView: some View {
        TimelineView(
            dayStart: dayStart,
            dayEnd: dayEnd,
            blocks: timelineBlocks,
            now: now,
            lookupTask: { tasksByID[$0] },
            onSchedule: attemptSchedule,
            onMove: attemptMove,
            onRefusal: showRefusal
        )
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: FlowSpacing.s) {
            if let requeue = flow?.requeueBanner {
                FlowBanner(text: requeue.bannerText, onDismiss: { flow?.requeueBanner = nil })
            }
            if showAppliedBanner {
                FlowBanner(
                    text: "Today's plan is updated.",
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

    // MARK: - Actions

    private func performPrimaryAction() {
        switch primaryAction {
        case .startCurrentTask(let segment):
            // Today has no gate/clock-in modal of its own; a blocked start
            // just explains itself via the existing refusal banner and
            // points at Focus, where `FocusScreen` renders the real dialog.
            guard flow?.focusEngine.start(segment: segment) != nil else {
                let needsPlan = flow?.focusEngine.pendingGate?.kind == .planGate
                showRefusal(needsPlan
                    ? "Write a Definition of Done in Focus before this can start."
                    : "Clock in from Focus to start this task.")
                return
            }
        case .planDay:
            openPlanPreview()
        }
    }

    private func openPlanPreview() {
        isReplanningWholeDay = false
        planProposal = flow?.planToday(replanExisting: false)
        showPlanPreview = true
    }

    private func replanWholeDay() {
        isReplanningWholeDay = true
        planProposal = flow?.planToday(replanExisting: true)
    }

    private func applyCurrentPlan() {
        guard let flow, let planProposal else { return }
        flow.applyPlan(planProposal, replanExisting: isReplanningWholeDay)
        self.planProposal = nil
        showAppliedBanner = true
    }

    private func undoAppliedPlan() {
        flow?.undoLastPlan()
        showAppliedBanner = false
    }

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

private struct TodayOpenAIPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : FlowMotion.tap, value: configuration.isPressed)
    }
}

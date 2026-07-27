import SwiftData
import SwiftUI

/// The operational home screen: plan status, the day's timeline and the
/// unscheduled Inbox. Works on both iPhone (stacked, scrolled to the current
/// time) and Mac (timeline and Inbox side by side when width allows).
struct TodayView: View {
    @Environment(\.flow) private var flow
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \FlowTask.sortOrder) private var allTasks: [FlowTask]
    @Query(sort: \TaskSegment.startDate) private var allSegments: [TaskSegment]

    @State private var planProposal: PlanProposal?
    @State private var isReplanningWholeDay = false
    @State private var showPlanPreview = false
    @State private var showAppliedBanner = false
    @State private var refusalMessage: String?
    /// Wide enough on Mac to show the timeline and Inbox side by side.
    @State private var containerWidth: CGFloat = 900

    private let calendar = Calendar.current

    private var now: Date { flow?.now ?? Date() }

    private var dayStart: Date {
        flow?.settings.workdayStart(on: now, calendar: calendar) ?? calendar.startOfDay(for: now)
    }

    private var dayEnd: Date {
        flow?.settings.workdayEnd(on: now, calendar: calendar) ?? dayStart.addingTimeInterval(13 * 3600)
    }

    private var todaySegments: [TaskSegment] {
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
        (todaySegments.map(TimelineBlock.init(segment:)) + externalEvents.map(TimelineBlock.init(event:)))
            .sorted { $0.start < $1.start }
    }

    private var inboxTasks: [FlowTask] {
        SmartView.inbox.matches(allTasks, now: now, calendar: calendar)
    }

    private var tasksByID: [UUID: FlowTask] {
        Dictionary(uniqueKeysWithValues: allTasks.map { ($0.id, $0) })
    }

    private var plannedMinutes: Int {
        todaySegments.reduce(0) { $0 + $1.durationMinutes }
    }

    private var remainingMinutes: Int {
        todaySegments
            .filter { $0.state == .scheduled }
            .reduce(0) { $0 + Int(($1.remainingSeconds(at: now) / 60).rounded()) }
    }

    private var completedCount: Int {
        todaySegments.count { $0.state == .completed }
    }

    private var primaryAction: TodayPrimaryAction {
        if let segment = flow?.focusEngine.currentSegment(at: now) {
            return .startCurrentTask(segment: segment)
        }
        return .planDay
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                platformLayout
            }
            .onAppear {
                #if !os(macOS)
                DispatchQueue.main.async {
                    proxy.scrollTo("now-anchor", anchor: .center)
                }
                #endif
            }
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
        .onAppear { flow?.refreshCalendarWindow(around: now) }
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
        stacked
            .padding(FlowSpacing.screen)
        #endif
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: FlowSpacing.xl) {
            header
            timelineView
            TodayInboxSection(tasks: inboxTasks)
        }
    }

    private var sideBySide: some View {
        HStack(alignment: .top, spacing: FlowSpacing.xl) {
            VStack(alignment: .leading, spacing: FlowSpacing.l) {
                header
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
            completedCount: completedCount,
            totalCount: todaySegments.count,
            action: primaryAction,
            onPrimaryAction: performPrimaryAction
        )
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
            flow?.focusEngine.start(segment: segment)
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

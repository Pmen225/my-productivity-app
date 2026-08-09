import Foundation
import Observation
import SwiftData
import SwiftUI

/// The services every screen shares.
///
/// One instance is created at launch and injected through the environment, so
/// the Assistant and the UI act through exactly the same code paths.
@Observable
@MainActor
public final class AppEnvironment {
    public let context: ModelContext
    public let settings: AppSettings
    public let calendarService: CalendarService
    public let notificationService: NotificationService
    public let voiceService: FocusVoiceService
    public let searchService: SearchService
    /// The one XP total and its curve. `MapNodeView`'s root pill and
    /// `ProgressScreen`'s initiative card both read this rather than each
    /// keeping their own copy of the level maths.
    public let gamification: GamificationService
    /// The one place transient feedback lives — XP toasts, the rank stamp, the
    /// done band, wind-down banners and HUD confirmations. Services raise
    /// moments here; `FlowMomentOverlay` on each platform root draws them.
    public let moments = FlowMomentService()
    /// Every calendar account, merged. The planner reads busy time from here so
    /// it cannot end up with one rule for Apple and another for Google.
    public let calendarHub: CalendarHub
    private let appleCalendarProvider: AppleCalendarProvider
    #if os(iOS) || os(macOS)
    private let googleCalendarProvider: GoogleCalendarProvider
    #endif

    #if os(iOS)
    /// The link to the watch. Nil-safe: with no watch paired it simply never
    /// sends anything.
    public let watchLink = WatchSyncService()
    #endif

    /// Rebuilt whenever the timer ticks so views observing it redraw.
    public var now: Date = Date()

    /// Banner shown after reconciliation moved work. Cleared when dismissed.
    public var requeueBanner: RequeueOutcome?
    /// The compulsory end-of-day review. It is intentionally separate from the
    /// non-blocking requeue banner so no tab can hide unfinished work.
    public var pendingRolloverReview: RolloverReview?
    /// Undo handle for the most recent plan, offered right after applying it.
    public var lastPlanSnapshot: ScheduleSnapshot?

    private(set) public var focusEngine: FocusEngine!

    public init(context: ModelContext) {
        self.context = context
        self.settings = Self.loadOrCreateSettings(in: context)
        // The font tokens are statics, so the persisted choice must be pushed
        // into them before the first view renders.
        FlowFont.choice = settings.appFont
        self.calendarService = CalendarService()
        self.notificationService = NotificationService()
        self.voiceService = FocusVoiceService(moments: moments)
        self.searchService = SearchService(context: context)
        let focusEngine = FocusEngine(
            context: context, settings: settings, voiceService: voiceService, moments: moments
        )
        self.focusEngine = focusEngine
        self.gamification = GamificationService(
            context: context,
            settings: settings,
            moments: moments,
            onChecklistCompleted: { [weak focusEngine] task in
                focusEngine?.completeIfActive(task: task)
            }
        )

        let settings = self.settings
        let appleProvider = AppleCalendarProvider(
            service: self.calendarService,
            isEnabled: settings.calendarIntegrationEnabled,
            selectedIdentifiers: settings.selectedCalendarIdentifiers
        )
        self.appleCalendarProvider = appleProvider

        #if os(iOS) || os(macOS)
        let googleProvider = GoogleCalendarProvider(
            isEnabled: settings.googleCalendarEnabled,
            selectedIdentifiers: settings.selectedGoogleCalendarIdentifiers,
            clientID: settings.googleOAuthClientID,
            accountLabel: settings.googleAccountLabel
        )
        self.googleCalendarProvider = googleProvider
        self.calendarHub = CalendarHub(providers: [appleProvider, googleProvider])
        #else
        self.calendarHub = CalendarHub(providers: [appleProvider])
        #endif

        // Wired after init so focus continuations see the same calendar the
        // planner does, refreshed rather than snapshotted.
        let calendarService = self.calendarService
        let hub = self.calendarHub
        self.focusEngine.externalEventsProvider = {
            let apple = calendarService.busyEvents(in: calendarService.events)
            let remote = hub.busyEvents(in: hub.eventsByKind[.google] ?? [])
            return apple + remote
        }
    }

    /// Busy time from every connected account.
    ///
    /// Apple is read synchronously from the local store; Google arrives on the
    /// network and is served from the hub's cache, so a plan made in the first
    /// second after launch uses whatever Google had last returned rather than
    /// blocking on it.
    public var externalBusyEvents: [ExternalCalendarEvent] {
        let apple = calendarService.busyEvents(in: calendarService.events)
        let remote = calendarHub.busyEvents(in: calendarHub.eventsByKind[.google] ?? [])
        return (apple + remote).sorted { $0.start < $1.start }
    }

    /// The settings record, created on first launch.
    private static func loadOrCreateSettings(in context: ModelContext) -> AppSettings {
        let existing = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        if let first = existing.first {
            // Two devices can each create a record before their first sync;
            // keep the oldest and discard the rest so settings stay singular.
            for duplicate in existing.dropFirst() { context.delete(duplicate) }
            return first
        }
        let created = AppSettings()
        context.insert(created)
        try? context.save()
        return created
    }

    // MARK: - Services

    public func scheduling() -> SchedulingService {
        SchedulingService(
            context: context,
            settings: settings,
            externalEvents: externalBusyEvents
        )
    }

    public var colourScheme: ColorScheme? {
        switch settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    // MARK: - Lifecycle

    /// Runs once whenever the app becomes active: reconciles missed timers,
    /// refreshes calendar data and requeues anything that fell through.
    public func reconcileOnActivation() {
        let moment = Date()
        now = moment

        refreshCalendarWindow(around: moment)

        if pendingRolloverReview == nil {
            if let review = scheduling().prepareRolloverReview(now: moment) {
                pendingRolloverReview = review
            } else {
                focusEngine.processElapsedSessionIfNeeded(now: moment)
                focusEngine.checkVoiceAnnouncements(now: moment)
                let outcomes = scheduling().reconcileMissedWork(now: moment)
                if let first = outcomes.first { requeueBanner = first }
            }
        }

        notificationService.rescheduleAll(
            segments: upcomingSegments(from: moment),
            settings: settings
        )

        settings.lastReconciliationAt = moment
        try? context.save()
    }

    /// Called by the app's shared ticker.
    public func tick(_ date: Date = Date()) {
        now = date
        focusEngine.tick = date
        focusEngine.processElapsedSessionIfNeeded(now: date)
        focusEngine.checkVoiceAnnouncements(now: date)
        #if os(iOS)
        // Cheap: the link drops a snapshot identical to the last one.
        watchLink.publishCurrent()
        #endif
    }

    public func refreshCalendarWindow(around date: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: SchedulingService.lookaheadDays, to: start) ?? start

        // Apple stays synchronous: reconciliation plans on the very next line and
        // must not plan over a meeting that has not arrived yet.
        calendarService.loadEvents(
            from: start,
            to: end,
            selectedIdentifiers: settings.selectedCalendarIdentifiers,
            enabled: settings.calendarIntegrationEnabled
        )
        appleCalendarProvider.update(
            isEnabled: settings.calendarIntegrationEnabled,
            selectedIdentifiers: settings.selectedCalendarIdentifiers
        )
        #if os(iOS) || os(macOS)
        googleCalendarProvider.update(
            isEnabled: settings.googleCalendarEnabled,
            selectedIdentifiers: settings.selectedGoogleCalendarIdentifiers,
            clientID: settings.googleOAuthClientID,
            accountLabel: settings.googleAccountLabel
        )
        #endif

        // Remote accounts are a network round trip, so they refresh behind the
        // scenes and are served from cache until they land.
        let hub = calendarHub
        let selection = calendarSelection
        Task { await hub.loadEvents(from: start, to: end, selection: selection) }
    }

    /// Which calendars each account is allowed to read, from settings.
    public var calendarSelection: [CalendarAccountKind: [String]] {
        [
            .apple: settings.selectedCalendarIdentifiers,
            .google: settings.selectedGoogleCalendarIdentifiers
        ]
    }

    public func upcomingSegments(from date: Date) -> [TaskSegment] {
        let segments = (try? context.fetch(FetchDescriptor<TaskSegment>())) ?? []
        return segments
            .filter { $0.state == .scheduled && $0.endDate > date }
            .sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Planning shortcuts used by both the UI and the Assistant

    public func planToday(replanExisting: Bool = false) -> PlanProposal {
        scheduling().proposePlan(for: now, now: now, replanExisting: replanExisting)
    }

    public func applyPlan(_ proposal: PlanProposal, replanExisting: Bool = false) {
        let snapshot = scheduling().apply(proposal, replanExisting: replanExisting, for: now)
        if !proposal.isEmpty {
            scheduling().sealPlan(for: now)
        }
        lastPlanSnapshot = snapshot
        notificationService.rescheduleAll(
            segments: upcomingSegments(from: now),
            settings: settings
        )
    }

    // MARK: - Sealed-day review

    public func resolveRolloverItem(
        _ itemID: UUID,
        with resolution: RolloverResolution
    ) {
        guard var review = pendingRolloverReview,
              let index = review.items.firstIndex(where: { $0.id == itemID }),
              review.items[index].resolution == nil
        else { return }

        let taskID = review.items[index].taskID
        let service = scheduling()
        let succeeded: Bool
        switch resolution {
        case .tomorrow:
            succeeded = service.moveRolloverTaskToTomorrow(
                taskID: taskID,
                sourceDay: review.sourceDay,
                now: now
            )
        case .backlog:
            succeeded = service.backlogRolloverTask(taskID: taskID)
        case .deleted:
            succeeded = service.deleteRolloverTask(taskID: taskID)
        }
        guard succeeded else { return }
        review.items[index].resolution = resolution
        pendingRolloverReview = review
    }

    public func finishRolloverReview() {
        guard let review = pendingRolloverReview, review.isComplete else { return }
        scheduling().finishRolloverReview(for: review.sourceDay)
        pendingRolloverReview = nil
        notificationService.rescheduleAll(
            segments: upcomingSegments(from: now),
            settings: settings
        )
    }

    public func undoLastPlan() {
        guard let snapshot = lastPlanSnapshot else { return }
        scheduling().undo(snapshot)
        lastPlanSnapshot = nil
        notificationService.rescheduleAll(
            segments: upcomingSegments(from: now),
            settings: settings
        )
    }

    #if os(iOS)
    // MARK: - Watch

    /// Starts publishing to the watch. Called once, at launch.
    ///
    /// The watch is a remote control, not a second brain: it receives what the
    /// phone already computed and sends back commands that land on the very same
    /// `FocusEngine` calls the phone's own buttons use.
    public func activateWatchLink() {
        watchLink.snapshotProvider = { [weak self] in
            self?.watchSnapshot() ?? WatchSnapshot()
        }
        watchLink.commandHandler = { [weak self] command in
            self?.handleWatchCommand(command)
        }
        watchLink.activate()
    }

    public func watchSnapshot() -> WatchSnapshot {
        let moment = now
        let queue = focusEngine.queue(for: moment)
        let session = focusEngine.activeSession
        let activeSegmentID = session?.segment?.id

        let items = queue.map { segment in
            WatchSnapshot.Item(
                id: segment.id,
                title: segment.task?.title ?? "Focus",
                colourToken: (segment.task?.colour ?? .violet).rawValue,
                start: segment.startDate,
                end: segment.endDate,
                isDone: segment.state == .completed,
                isActive: segment.id == activeSegmentID,
                isExternal: segment.externalEventIdentifier != nil
            )
        }

        let remaining = queue
            .filter { $0.state == .scheduled && $0.endDate > moment }
            .reduce(0) { $0 + $1.durationMinutes }

        return WatchSnapshot(
            generatedAt: moment,
            activeTitle: session.map { $0.task?.title ?? "Focus" },
            activeColourToken: session?.task?.colour.rawValue,
            // Only one of these two is ever set: a running block counts down to a
            // date, a paused one holds a fixed remainder.
            activeEndsAt: session.flatMap { $0.isPaused ? nil : moment.addingTimeInterval($0.remainingSeconds(at: moment)) },
            pausedRemaining: session.flatMap { $0.isPaused ? $0.remainingSeconds(at: moment) : nil },
            activeTotalSeconds: session?.plannedSeconds,
            isPaused: session?.isPaused ?? false,
            items: items,
            plannedMinutes: queue.reduce(0) { $0 + $1.durationMinutes },
            remainingMinutes: remaining,
            completedCount: queue.filter { $0.state == .completed }.count,
            totalCount: queue.count
        )
    }

    public func handleWatchCommand(_ command: WatchCommand) {
        switch command {
        case .togglePause:
            focusEngine.togglePause(now: Date())
        case .complete:
            focusEngine.completeCurrentTask(now: Date())
        case .skip:
            focusEngine.skipCurrentTask(now: Date())
        case .startNext:
            let moment = Date()
            guard focusEngine.activeSession == nil else { return }
            let next = focusEngine.currentSegment(at: moment)
                ?? focusEngine.queue(for: moment).first { $0.state == .scheduled && $0.endDate > moment }
            // Deliberately does NOT bypass the compulsory planning gate: the
            // watch has no UI for a Definition of Done, so a gated task just
            // sets `pendingGate` on this same shared engine and surfaces the
            // gate/clock-in modal next time the phone's Focus screen is open.
            if let next { _ = focusEngine.start(segment: next, now: moment) }
        case .capture(let text):
            captureFromWatch(text)
        case .requestSnapshot:
            watchLink.publishCurrent(force: true)
        }
        try? context.save()
        watchLink.publishCurrent(force: true)
    }

    /// Dictated text becomes an inbox task through the assistant's own tool, so
    /// there is one creation path rather than a watch-shaped copy of it.
    private func captureFromWatch(_ text: String) {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let arguments: [String: String] = ["title": title]
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let json = String(data: data, encoding: .utf8) else { return }
        _ = AssistantToolRouter(flow: self).handle(
            toolName: AssistantToolName.createTask.rawValue,
            argumentsJSON: json
        )
    }
    #endif
}

// MARK: - Environment plumbing

private struct AppEnvironmentKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: AppEnvironment? = nil
}

public extension EnvironmentValues {
    var flow: AppEnvironment? {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}

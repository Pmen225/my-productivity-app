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
    public let searchService: SearchService

    /// Rebuilt whenever the timer ticks so views observing it redraw.
    public var now: Date = Date()

    /// Banner shown after reconciliation moved work. Cleared when dismissed.
    public var requeueBanner: RequeueOutcome?
    /// Undo handle for the most recent plan, offered right after applying it.
    public var lastPlanSnapshot: ScheduleSnapshot?

    private(set) public var focusEngine: FocusEngine!

    public init(context: ModelContext) {
        self.context = context
        self.settings = Self.loadOrCreateSettings(in: context)
        self.calendarService = CalendarService()
        self.notificationService = NotificationService()
        self.searchService = SearchService(context: context)
        self.focusEngine = FocusEngine(context: context, settings: settings)
        // Wired after init so focus continuations see the same calendar the
        // planner does, refreshed rather than snapshotted.
        let calendarService = self.calendarService
        self.focusEngine.externalEventsProvider = {
            calendarService.busyEvents(in: calendarService.events)
        }
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
            externalEvents: calendarService.busyEvents(in: calendarService.events)
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

        focusEngine.processElapsedSessionIfNeeded(now: moment)

        let outcomes = scheduling().reconcileMissedWork(now: moment)
        if let first = outcomes.first { requeueBanner = first }

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
    }

    public func refreshCalendarWindow(around date: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: SchedulingService.lookaheadDays, to: start) ?? start
        calendarService.loadEvents(
            from: start,
            to: end,
            selectedIdentifiers: settings.selectedCalendarIdentifiers,
            enabled: settings.calendarIntegrationEnabled
        )
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
        lastPlanSnapshot = snapshot
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

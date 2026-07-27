import EventKit
import Foundation
import Observation

/// A calendar event owned by Apple Calendar, not by Flowmap.
///
/// These are fixed: the planner treats them as immovable busy time and never
/// writes to them unless the user has explicitly turned on write-back.
public struct ExternalCalendarEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarIdentifier: String
    public let calendarTitle: String

    public init(
        id: String,
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        calendarIdentifier: String,
        calendarTitle: String
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarIdentifier = calendarIdentifier
        self.calendarTitle = calendarTitle
    }

    public var durationMinutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
}

/// A calendar the user can choose to show.
public struct SelectableCalendar: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let sourceTitle: String
    public let allowsModification: Bool
}

/// Optional Apple Calendar integration.
///
/// Permission is requested only when the user enables the feature, and only the
/// calendars they pick are read.
@Observable
@MainActor
public final class CalendarService {
    public enum Authorisation: Equatable, Sendable {
        case notDetermined
        case denied
        case restricted
        case authorised

        public var canRead: Bool { self == .authorised }

        public var explanation: String {
            switch self {
            case .notDetermined: "Flowmap has not asked for calendar access yet."
            case .denied: "Calendar access is off. Turn it on in System Settings to see your events as fixed blocks."
            case .restricted: "Calendar access is restricted on this device."
            case .authorised: "Flowmap can read the calendars you selected."
            }
        }
    }

    private let store = EKEventStore()

    public private(set) var authorisation: Authorisation = .notDetermined
    public private(set) var availableCalendars: [SelectableCalendar] = []
    /// Cached events for the window the UI last asked for.
    public private(set) var events: [ExternalCalendarEvent] = []
    public private(set) var lastError: String?

    public init() {
        refreshAuthorisation()
    }

    public func refreshAuthorisation() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: authorisation = .authorised
        case .writeOnly: authorisation = .authorised
        case .denied: authorisation = .denied
        case .restricted: authorisation = .restricted
        case .notDetermined: authorisation = .notDetermined
        @unknown default: authorisation = .notDetermined
        }
        if authorisation.canRead { loadCalendars() }
    }

    /// Asks for permission. Called only from the Settings toggle.
    @discardableResult
    public func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            refreshAuthorisation()
            return granted
        } catch {
            lastError = "Calendar access could not be requested."
            refreshAuthorisation()
            return false
        }
    }

    public func loadCalendars() {
        guard authorisation.canRead else {
            availableCalendars = []
            return
        }
        availableCalendars = store.calendars(for: .event)
            .map {
                SelectableCalendar(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    sourceTitle: $0.source?.title ?? "",
                    allowsModification: $0.allowsContentModifications
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Reads events in `[start, end)` from the selected calendars.
    ///
    /// Returns an empty array — never an error state that blocks planning — when
    /// integration is off or permission is missing.
    @discardableResult
    public func loadEvents(
        from start: Date,
        to end: Date,
        selectedIdentifiers: [String],
        enabled: Bool
    ) -> [ExternalCalendarEvent] {
        guard enabled, authorisation.canRead, end > start else {
            events = []
            return []
        }

        let calendars = store.calendars(for: .event).filter {
            selectedIdentifiers.isEmpty || selectedIdentifiers.contains($0.calendarIdentifier)
        }
        guard !calendars.isEmpty else {
            events = []
            return []
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        // `eventIdentifier` repeats across occurrences of a recurring event, so the
        // occurrence start is folded in to keep identities unique and stable.
        let loaded: [ExternalCalendarEvent] = store.events(matching: predicate).compactMap { event in
            guard let eventStart = event.startDate, let eventEnd = event.endDate else { return nil }
            let base = event.eventIdentifier ?? UUID().uuidString
            return ExternalCalendarEvent(
                id: "\(base)#\(Int(eventStart.timeIntervalSince1970))",
                title: event.title ?? "Busy",
                start: eventStart,
                end: eventEnd,
                isAllDay: event.isAllDay,
                calendarIdentifier: event.calendar?.calendarIdentifier ?? "",
                calendarTitle: event.calendar?.title ?? ""
            )
        }

        // De-duplicate defensively: the same occurrence must never be imported twice.
        var seen = Set<String>()
        events = loaded
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.start < $1.start }
        return events
    }

    /// Busy intervals for the planner. All-day events do not block the timeline —
    /// they are context, not appointments.
    public func busyEvents(in events: [ExternalCalendarEvent]) -> [ExternalCalendarEvent] {
        events.filter { !$0.isAllDay && $0.end > $0.start }
    }

    // MARK: - Optional write-back

    /// Writes a focus block to the user's chosen calendar. Returns the external
    /// identifier so the segment can be updated or removed later.
    @discardableResult
    public func writeFocusBlock(
        title: String,
        start: Date,
        end: Date,
        toCalendarWithIdentifier identifier: String
    ) -> String? {
        guard authorisation.canRead,
              let calendar = store.calendar(withIdentifier: identifier),
              calendar.allowsContentModifications
        else { return nil }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = calendar
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return event.eventIdentifier
        } catch {
            lastError = "That focus block could not be written to your calendar."
            return nil
        }
    }

    public func removeWrittenEvent(identifier: String) {
        guard authorisation.canRead, let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }
}

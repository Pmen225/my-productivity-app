import Foundation
import Observation

/// One busy-time source for the whole app, however many accounts are connected.
///
/// The planner, the timeline and the assistant all read the hub. They never ask
/// "is this Apple or Google?" — the merge happens once, here, so a second
/// account can never mean a second scheduling rule.
@Observable
@MainActor
public final class CalendarHub {

    public private(set) var providers: [CalendarAccountKind: any CalendarProvider] = [:]

    /// Merged, de-duplicated, sorted events for the window last loaded.
    public private(set) var events: [ExternalCalendarEvent] = []

    /// The same events kept per account, because the two accounts arrive on
    /// different clocks: Apple is a synchronous store read, Google is a network
    /// round trip. Callers that must not wait read the Apple slice immediately.
    public private(set) var eventsByKind: [CalendarAccountKind: [ExternalCalendarEvent]] = [:]

    /// Set while an interactive connect or a refresh is in flight, so buttons
    /// can show progress rather than appearing dead.
    public private(set) var isWorking: Bool = false

    private var lastWindow: (start: Date, end: Date)?

    public init(providers: [any CalendarProvider]) {
        for provider in providers { self.providers[provider.kind] = provider }
    }

    // MARK: - Connections

    public var connections: [CalendarConnection] {
        CalendarAccountKind.allCases.compactMap { providers[$0]?.connection }
    }

    public func connection(for kind: CalendarAccountKind) -> CalendarConnection? {
        providers[kind]?.connection
    }

    public var connectedKinds: [CalendarAccountKind] {
        connections.filter(\.isConnected).map(\.kind)
    }

    @discardableResult
    public func connect(_ kind: CalendarAccountKind) async -> Bool {
        guard let provider = providers[kind] else { return false }
        isWorking = true
        defer { isWorking = false }
        let connected = await provider.connect()
        if connected {
            await provider.refreshCalendars()
            await reloadLastWindow()
        }
        return connected
    }

    public func disconnect(_ kind: CalendarAccountKind) {
        providers[kind]?.disconnect()
        Task { await reloadLastWindow() }
    }

    public func refreshCalendars() async {
        isWorking = true
        defer { isWorking = false }
        for provider in providers.values { await provider.refreshCalendars() }
    }

    // MARK: - Events

    /// Loads `[start, end)` from every connected account and merges the result.
    @discardableResult
    public func loadEvents(
        from start: Date,
        to end: Date,
        selection: [CalendarAccountKind: [String]]
    ) async -> [ExternalCalendarEvent] {
        lastWindow = (start, end)
        guard end > start else {
            events = []
            return []
        }

        var merged: [ExternalCalendarEvent] = []
        for kind in CalendarAccountKind.allCases {
            guard let provider = providers[kind], provider.connection.isConnected else {
                eventsByKind[kind] = []
                continue
            }
            let loaded = await provider.events(
                from: start,
                to: end,
                selectedIdentifiers: selection[kind] ?? []
            )
            eventsByKind[kind] = loaded
            merged.append(contentsOf: loaded)
        }

        // Two accounts can hold the same meeting (a Google invite mirrored into
        // Apple Calendar). Fold those together on title and interval so the
        // planner does not treat one meeting as two walls of busy time.
        var seenIdentity = Set<String>()
        events = merged
            .filter { event in
                let identity = "\(event.title)|\(Int(event.start.timeIntervalSince1970))|\(Int(event.end.timeIntervalSince1970))"
                return seenIdentity.insert(identity).inserted
            }
            .sorted { $0.start < $1.start }
        return events
    }

    /// Busy intervals for the planner. All-day events are context, not appointments.
    public func busyEvents(in events: [ExternalCalendarEvent]) -> [ExternalCalendarEvent] {
        events.filter { !$0.isAllDay && $0.end > $0.start }
    }

    private func reloadLastWindow() async {
        guard let lastWindow else { return }
        await loadEvents(from: lastWindow.start, to: lastWindow.end, selection: currentSelection)
    }

    /// The hub's own view of which calendars are selected, refreshed from each
    /// provider so a caller does not have to thread settings through every call.
    public var currentSelection: [CalendarAccountKind: [String]] {
        var selection: [CalendarAccountKind: [String]] = [:]
        for (kind, provider) in providers {
            selection[kind] = provider.connection.selectedIdentifiers
        }
        return selection
    }

    // MARK: - Write-back

    @discardableResult
    public func createEvent(
        kind: CalendarAccountKind,
        title: String,
        start: Date,
        end: Date,
        calendarIdentifier: String
    ) async -> String? {
        await providers[kind]?.createEvent(
            title: title,
            start: start,
            end: end,
            calendarIdentifier: calendarIdentifier
        ) ?? nil
    }

    @discardableResult
    public func moveEvent(kind: CalendarAccountKind, identifier: String, start: Date, end: Date) async -> Bool {
        await providers[kind]?.moveEvent(identifier: identifier, start: start, end: end) ?? false
    }

    @discardableResult
    public func deleteEvent(kind: CalendarAccountKind, identifier: String) async -> Bool {
        await providers[kind]?.deleteEvent(identifier: identifier) ?? false
    }
}

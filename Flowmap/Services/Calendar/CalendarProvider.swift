import Foundation

/// Which account a calendar came from.
public enum CalendarAccountKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case apple
    case google

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .apple: "Apple Calendar"
        case .google: "Google Calendar"
        }
    }

    public var symbolName: String {
        switch self {
        case .apple: "calendar"
        case .google: "globe"
        }
    }
}

/// The state of one calendar account, as shown in Settings and as reported to
/// an assistant through the control API.
public struct CalendarConnection: Identifiable, Sendable, Equatable, Codable {
    public var kind: CalendarAccountKind
    public var isConnected: Bool
    /// The signed-in account, when the provider knows it (an email for Google).
    public var accountLabel: String?
    public var calendars: [SelectableCalendarSummary]
    /// Which of those calendars are being read.
    public var selectedIdentifiers: [String]
    public var lastError: String?

    public var id: String { kind.rawValue }

    public init(
        kind: CalendarAccountKind,
        isConnected: Bool = false,
        accountLabel: String? = nil,
        calendars: [SelectableCalendarSummary] = [],
        selectedIdentifiers: [String] = [],
        lastError: String? = nil
    ) {
        self.kind = kind
        self.isConnected = isConnected
        self.accountLabel = accountLabel
        self.calendars = calendars
        self.selectedIdentifiers = selectedIdentifiers
        self.lastError = lastError
    }
}

/// A calendar as offered to the user, flattened so it can cross the assistant
/// API as JSON without dragging EventKit types with it.
public struct SelectableCalendarSummary: Identifiable, Sendable, Equatable, Codable {
    public var id: String
    public var title: String
    public var sourceTitle: String
    public var allowsModification: Bool

    public init(id: String, title: String, sourceTitle: String, allowsModification: Bool) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.allowsModification = allowsModification
    }
}

/// One calendar account the app can read from and, where permitted, write to.
///
/// Both providers speak `ExternalCalendarEvent` so the planner keeps a single
/// notion of busy time no matter where a meeting came from. Anything account
/// specific — OAuth, permission prompts, refresh tokens — stops at this boundary.
@MainActor
public protocol CalendarProvider: AnyObject {
    var kind: CalendarAccountKind { get }

    /// Current state, cheap to read; the UI observes the hub, not the provider.
    var connection: CalendarConnection { get }

    /// Interactive sign-in or permission request. Returns whether it succeeded.
    @discardableResult
    func connect() async -> Bool

    /// Forgets credentials and cached calendars. Never throws — disconnecting
    /// must always be possible, including from a broken state.
    func disconnect()

    func refreshCalendars() async

    /// Events overlapping `[start, end)` from `selectedIdentifiers`
    /// (all calendars when empty).
    func events(from start: Date, to end: Date, selectedIdentifiers: [String]) async -> [ExternalCalendarEvent]

    /// Writes a block back to the account. Returns the provider's event id.
    @discardableResult
    func createEvent(title: String, start: Date, end: Date, calendarIdentifier: String) async -> String?

    @discardableResult
    func moveEvent(identifier: String, start: Date, end: Date) async -> Bool

    @discardableResult
    func deleteEvent(identifier: String) async -> Bool
}

// MARK: - Apple

/// Adapts the existing `CalendarService` to the provider protocol.
///
/// The EventKit code is not duplicated or moved: everything below forwards, so
/// the permission handling that already shipped stays the only copy.
@MainActor
public final class AppleCalendarProvider: CalendarProvider {
    public let kind: CalendarAccountKind = .apple

    private let service: CalendarService
    private var isEnabled: Bool
    private var selected: [String]

    public init(service: CalendarService, isEnabled: Bool, selectedIdentifiers: [String]) {
        self.service = service
        self.isEnabled = isEnabled
        self.selected = selectedIdentifiers
    }

    /// Kept in step by the hub whenever settings change.
    public func update(isEnabled: Bool, selectedIdentifiers: [String]) {
        self.isEnabled = isEnabled
        self.selected = selectedIdentifiers
    }

    public var connection: CalendarConnection {
        CalendarConnection(
            kind: .apple,
            isConnected: isEnabled && service.authorisation.canRead,
            accountLabel: nil,
            calendars: service.availableCalendars.map {
                SelectableCalendarSummary(
                    id: $0.id,
                    title: $0.title,
                    sourceTitle: $0.sourceTitle,
                    allowsModification: $0.allowsModification
                )
            },
            selectedIdentifiers: selected,
            lastError: service.lastError
        )
    }

    @discardableResult
    public func connect() async -> Bool {
        let granted = await service.requestAccess()
        if granted { service.loadCalendars() }
        return granted
    }

    public func disconnect() {
        // System permission is the user's to revoke; the app forgets its side.
        isEnabled = false
        selected = []
    }

    public func refreshCalendars() async {
        service.refreshAuthorisation()
        service.loadCalendars()
    }

    public func events(
        from start: Date,
        to end: Date,
        selectedIdentifiers: [String]
    ) async -> [ExternalCalendarEvent] {
        service.loadEvents(
            from: start,
            to: end,
            selectedIdentifiers: selectedIdentifiers,
            enabled: isEnabled
        )
    }

    @discardableResult
    public func createEvent(
        title: String,
        start: Date,
        end: Date,
        calendarIdentifier: String
    ) async -> String? {
        service.writeFocusBlock(
            title: title,
            start: start,
            end: end,
            toCalendarWithIdentifier: calendarIdentifier
        )
    }

    @discardableResult
    public func moveEvent(identifier: String, start: Date, end: Date) async -> Bool {
        // EventKit edits are not part of the shipped write-back surface: the app
        // only ever creates and removes its own blocks, so a move is expressed
        // as the caller deleting and re-creating rather than silently editing
        // an event Flowmap may not own.
        false
    }

    @discardableResult
    public func deleteEvent(identifier: String) async -> Bool {
        service.removeWrittenEvent(identifier: identifier)
        return true
    }
}

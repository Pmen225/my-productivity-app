#if os(iOS) || os(macOS)
import Foundation
import Observation

/// The composite identifier handed to the rest of the app for a Google event.
///
/// Recurring occurrences share one `eventId` in Google's API, so the occurrence
/// start is folded in to keep every occurrence unique — the same trick
/// `CalendarService` already uses for EventKit's recurring identifiers.
enum GoogleEventIdentifier {
    static func make(calendarId: String, eventId: String, start: Date) -> String {
        "google:\(calendarId):\(eventId)#\(Int(start.timeIntervalSince1970))"
    }

    /// Splits a composite id back into the calendar id and event id Google's
    /// REST API expects. `nil` for anything that isn't one of ours.
    static func parse(_ identifier: String) -> (calendarId: String, eventId: String)? {
        let prefix = "google:"
        guard identifier.hasPrefix(prefix) else { return nil }
        let remainder = identifier.dropFirst(prefix.count)
        guard let colonIndex = remainder.firstIndex(of: ":") else { return nil }
        let calendarId = String(remainder[..<colonIndex])
        let afterColon = remainder[remainder.index(after: colonIndex)...]
        guard let hashIndex = afterColon.lastIndex(of: "#") else { return nil }
        let eventId = String(afterColon[..<hashIndex])
        guard !calendarId.isEmpty, !eventId.isEmpty else { return nil }
        return (calendarId, eventId)
    }
}

// MARK: - Wire types

/// Decoded straight off `GET /calendar/v3/calendars/{id}/events`. Kept separate
/// from `ExternalCalendarEvent` so the mapping rules (cancelled, transparent,
/// all-day) are pure and testable without a network call.
struct GoogleEventDTO: Decodable {
    struct EventDateTime: Decodable {
        let date: String?
        let dateTime: String?
    }

    let id: String
    let status: String?
    let summary: String?
    let transparency: String?
    let start: EventDateTime?
    let end: EventDateTime?
}

struct GoogleEventsResponse: Decodable {
    let items: [GoogleEventDTO]?
    let nextPageToken: String?
}

struct GoogleCalendarListEntry: Decodable {
    let id: String
    let summary: String?
    let accessRole: String?
}

struct GoogleCalendarListResponse: Decodable {
    let items: [GoogleCalendarListEntry]?
}

/// Turns Google's event JSON into the app's neutral `ExternalCalendarEvent`.
/// Pure and network-free so it is exercised directly in tests.
enum GoogleEventMapper {
    static func map(
        _ dto: GoogleEventDTO,
        calendarId: String,
        calendarTitle: String
    ) -> ExternalCalendarEvent? {
        guard dto.status != "cancelled" else { return nil }
        guard dto.transparency != "transparent" else { return nil }
        guard let start = date(from: dto.start), let end = date(from: dto.end) else { return nil }

        return ExternalCalendarEvent(
            id: GoogleEventIdentifier.make(calendarId: calendarId, eventId: dto.id, start: start),
            title: dto.summary ?? "Busy",
            start: start,
            end: end,
            isAllDay: dto.start?.dateTime == nil,
            calendarIdentifier: calendarId,
            calendarTitle: calendarTitle
        )
    }

    // Formatters are read-only after setup and only ever have `date(from:)`
    // called on them; `nonisolated(unsafe)` avoids a formatter-per-call
    // allocation without claiming a Sendable conformance Foundation doesn't
    // give these types.
    nonisolated(unsafe) private static let dateTimeWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let dateTimePlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let allDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func date(from dt: GoogleEventDTO.EventDateTime?) -> Date? {
        guard let dt else { return nil }
        if let dateTime = dt.dateTime {
            return dateTimeWithFraction.date(from: dateTime) ?? dateTimePlain.date(from: dateTime)
        }
        if let date = dt.date {
            return allDayFormatter.date(from: date)
        }
        return nil
    }
}

private enum GoogleCalendarRequestError: Error {
    case badResponse
}

/// Google Calendar as a second `CalendarProvider` account, sitting behind the
/// same protocol the Apple/EventKit adapter satisfies. All account-specific
/// concerns (OAuth, refresh, the REST calls) stop at this boundary — the
/// planner only ever sees `ExternalCalendarEvent`.
@MainActor
@Observable
public final class GoogleCalendarProvider: CalendarProvider {
    public let kind: CalendarAccountKind = .google

    private let oauth: GoogleOAuth
    private let urlSession: URLSession

    private var isEnabled: Bool
    private var selected: [String]
    private var clientID: String?
    private var accountLabel: String?
    private var calendars: [SelectableCalendarSummary] = []
    private var lastError: String?

    public init(
        isEnabled: Bool,
        selectedIdentifiers: [String],
        clientID: String?,
        accountLabel: String?,
        oauth: GoogleOAuth = GoogleOAuth(),
        urlSession: URLSession = .shared
    ) {
        self.isEnabled = isEnabled
        self.selected = selectedIdentifiers
        self.clientID = clientID
        self.accountLabel = accountLabel
        self.oauth = oauth
        self.urlSession = urlSession
    }

    /// Kept in step by the hub whenever settings change.
    public func update(
        isEnabled: Bool,
        selectedIdentifiers: [String],
        clientID: String?,
        accountLabel: String?
    ) {
        self.isEnabled = isEnabled
        self.selected = selectedIdentifiers
        self.clientID = clientID
        if let accountLabel { self.accountLabel = accountLabel }
    }

    public var connection: CalendarConnection {
        CalendarConnection(
            kind: .google,
            isConnected: isEnabled && oauth.isSignedIn,
            accountLabel: accountLabel,
            calendars: calendars,
            selectedIdentifiers: selected,
            lastError: lastError
        )
    }

    @discardableResult
    public func connect() async -> Bool {
        guard let clientID, !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            lastError = "Add a Google client id in Settings before connecting."
            return false
        }
        do {
            let email = try await oauth.signIn(clientID: clientID)
            accountLabel = email
            lastError = nil
            return true
        } catch {
            lastError = Self.userFacingMessage(for: error)
            return false
        }
    }

    public func disconnect() {
        oauth.signOut()
        calendars = []
        accountLabel = nil
        lastError = nil
    }

    public func refreshCalendars() async {
        guard isEnabled, let clientID else { return }
        do {
            let token = try await oauth.validAccessToken(clientID: clientID)
            calendars = try await fetchCalendarList(accessToken: token)
            lastError = nil
        } catch {
            calendars = []
            lastError = Self.userFacingMessage(for: error)
        }
    }

    public func events(
        from start: Date,
        to end: Date,
        selectedIdentifiers: [String]
    ) async -> [ExternalCalendarEvent] {
        guard isEnabled, let clientID, end > start else { return [] }
        let calendarIDs = selectedIdentifiers.isEmpty ? calendars.map(\.id) : selectedIdentifiers
        guard !calendarIDs.isEmpty else { return [] }

        do {
            let token = try await oauth.validAccessToken(clientID: clientID)
            var all: [ExternalCalendarEvent] = []
            for calendarID in calendarIDs {
                let loaded = try await fetchEvents(
                    calendarId: calendarID,
                    start: start,
                    end: end,
                    accessToken: token
                )
                all.append(contentsOf: loaded)
            }
            lastError = nil
            return all.sorted { $0.start < $1.start }
        } catch {
            lastError = Self.userFacingMessage(for: error)
            return []
        }
    }

    @discardableResult
    public func createEvent(
        title: String,
        start: Date,
        end: Date,
        calendarIdentifier: String
    ) async -> String? {
        guard isEnabled, let clientID else { return nil }
        do {
            let token = try await oauth.validAccessToken(clientID: clientID)
            guard let encodedCalendarID = Self.pathEncode(calendarIdentifier) else { return nil }
            guard
                let url = URL(
                    string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events"
                )
            else { return nil }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "summary": title,
                "start": ["dateTime": Self.rfc3339(start)],
                "end": ["dateTime": Self.rfc3339(end)],
            ])

            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw GoogleCalendarRequestError.badResponse
            }
            let created = try JSONDecoder().decode(GoogleEventDTO.self, from: data)
            lastError = nil
            return GoogleEventIdentifier.make(calendarId: calendarIdentifier, eventId: created.id, start: start)
        } catch {
            lastError = Self.userFacingMessage(for: error)
            return nil
        }
    }

    @discardableResult
    public func moveEvent(identifier: String, start: Date, end: Date) async -> Bool {
        guard isEnabled, let clientID else { return false }
        guard let parsed = GoogleEventIdentifier.parse(identifier) else {
            lastError = "That Google Calendar event could not be found."
            return false
        }
        do {
            let token = try await oauth.validAccessToken(clientID: clientID)
            guard
                let encodedCalendarID = Self.pathEncode(parsed.calendarId),
                let encodedEventID = Self.pathEncode(parsed.eventId),
                let url = URL(
                    string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events/\(encodedEventID)"
                )
            else { return false }

            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "start": ["dateTime": Self.rfc3339(start)],
                "end": ["dateTime": Self.rfc3339(end)],
            ])

            let (_, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw GoogleCalendarRequestError.badResponse
            }
            lastError = nil
            return true
        } catch {
            lastError = Self.userFacingMessage(for: error)
            return false
        }
    }

    @discardableResult
    public func deleteEvent(identifier: String) async -> Bool {
        guard isEnabled, let clientID else { return false }
        guard let parsed = GoogleEventIdentifier.parse(identifier) else { return false }
        do {
            let token = try await oauth.validAccessToken(clientID: clientID)
            guard
                let encodedCalendarID = Self.pathEncode(parsed.calendarId),
                let encodedEventID = Self.pathEncode(parsed.eventId),
                let url = URL(
                    string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events/\(encodedEventID)"
                )
            else { return false }

            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GoogleCalendarRequestError.badResponse }
            // Already gone counts as done — the caller only cares that it is
            // no longer sitting on the calendar.
            guard (200..<300).contains(http.statusCode) || http.statusCode == 404 || http.statusCode == 410 else {
                throw GoogleCalendarRequestError.badResponse
            }
            lastError = nil
            return true
        } catch {
            lastError = Self.userFacingMessage(for: error)
            return false
        }
    }

    // MARK: - Requests

    private func fetchCalendarList(accessToken: String) async throws -> [SelectableCalendarSummary] {
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList") else {
            throw GoogleCalendarRequestError.badResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoogleCalendarRequestError.badResponse
        }
        let decoded = try JSONDecoder().decode(GoogleCalendarListResponse.self, from: data)
        let label = accountLabel ?? "Google"
        return (decoded.items ?? []).map { entry in
            SelectableCalendarSummary(
                id: entry.id,
                title: entry.summary ?? entry.id,
                sourceTitle: label,
                allowsModification: entry.accessRole == "owner" || entry.accessRole == "writer"
            )
        }
    }

    private func fetchEvents(
        calendarId: String,
        start: Date,
        end: Date,
        accessToken: String
    ) async throws -> [ExternalCalendarEvent] {
        let calendarTitle = calendars.first(where: { $0.id == calendarId })?.title ?? calendarId
        var results: [ExternalCalendarEvent] = []
        var pageToken: String?

        repeat {
            guard let encodedCalendarID = Self.pathEncode(calendarId) else { break }
            guard
                var components = URLComponents(
                    string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events"
                )
            else { break }

            var queryItems = [
                URLQueryItem(name: "timeMin", value: Self.rfc3339(start)),
                URLQueryItem(name: "timeMax", value: Self.rfc3339(end)),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "250"),
            ]
            if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = queryItems

            guard let url = components.url else { break }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw GoogleCalendarRequestError.badResponse
            }
            let decoded = try JSONDecoder().decode(GoogleEventsResponse.self, from: data)
            let mapped = (decoded.items ?? []).compactMap {
                GoogleEventMapper.map($0, calendarId: calendarId, calendarTitle: calendarTitle)
            }
            results.append(contentsOf: mapped)
            pageToken = decoded.nextPageToken
        } while pageToken != nil

        return results
    }

    // MARK: - Helpers

    private static func pathEncode(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
    }

    private static func rfc3339(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let oauthError = error as? GoogleOAuthError {
            switch oauthError {
            case .missingClientID:
                return "Add a Google client id in Settings before connecting."
            case .invalidRedirectURI:
                return "That Google client id looks incomplete."
            case .userCancelled:
                return "Sign-in was cancelled."
            case .authorisationFailed, .tokenExchangeFailed:
                return "Google sign-in failed. Please try again."
            case .noRefreshToken:
                return "Google Calendar needs to be reconnected."
            case .network:
                return "Google Calendar could not be reached."
            }
        }
        return "Google Calendar could not be reached."
    }
}
#endif

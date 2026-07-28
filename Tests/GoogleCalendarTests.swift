import Foundation
import Testing
@testable import Flowmap

#if os(iOS) || os(macOS)

/// One top-level suite so `-only-testing:FlowmapTests/GoogleCalendarTests`
/// runs everything below; the nested suites just keep it organised.
@Suite("Google Calendar")
struct GoogleCalendarTests {
    @Suite("OAuth PKCE")
    struct OAuthPKCETests {
        @Test("Challenge is base64url(SHA256(verifier)) with no padding, per RFC 7636")
        func challengeMatchesRFCVector() {
            // The worked example from RFC 7636 Appendix B.
            let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
            let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
            #expect(GoogleOAuth.codeChallenge(for: verifier) == expectedChallenge)
        }

        @Test("Generated verifiers are URL-safe, unpadded, and not reused")
        func verifierIsURLSafeAndRandom() {
            let first = GoogleOAuth.makeCodeVerifier()
            let second = GoogleOAuth.makeCodeVerifier()

            #expect(first != second)
            for verifier in [first, second] {
                #expect(!verifier.contains("+"))
                #expect(!verifier.contains("/"))
                #expect(!verifier.contains("="))
                #expect(!verifier.isEmpty)
            }
        }

        @Test("Redirect URI reverses the client id without hard-coding a project")
        func redirectURIDerivesFromClientID() {
            let uri = GoogleOAuth.redirectURI(clientID: "123456-abc.apps.googleusercontent.com")
            #expect(uri?.absoluteString == "com.googleusercontent.apps.123456-abc:/oauth2redirect")
            #expect(uri?.scheme == "com.googleusercontent.apps.123456-abc")

            // A client id that doesn't match Google's shape yields no redirect
            // URI rather than a guessed one.
            #expect(GoogleOAuth.redirectURI(clientID: "not-a-google-client-id") == nil)
        }
    }

    @Suite("Event JSON decoding")
    struct EventDecodingTests {
        private let calendarId = "primary"
        private let calendarTitle = "Work"

        private func decode(_ json: String) throws -> GoogleEventDTO {
            try JSONDecoder().decode(GoogleEventDTO.self, from: Data(json.utf8))
        }

        @Test("A timed event maps to a non-all-day ExternalCalendarEvent")
        func timedEvent() throws {
            let dto = try decode("""
            {
                "id": "evt-timed",
                "status": "confirmed",
                "summary": "Team sync",
                "start": {"dateTime": "2026-07-27T10:00:00+01:00"},
                "end": {"dateTime": "2026-07-27T10:30:00+01:00"}
            }
            """)

            let mapped = GoogleEventMapper.map(dto, calendarId: calendarId, calendarTitle: calendarTitle)
            let event = try #require(mapped)

            #expect(event.title == "Team sync")
            #expect(event.isAllDay == false)
            #expect(event.calendarIdentifier == calendarId)
            #expect(event.calendarTitle == calendarTitle)
            #expect(event.end > event.start)
            #expect(
                event.id == GoogleEventIdentifier.make(
                    calendarId: calendarId,
                    eventId: "evt-timed",
                    start: event.start
                )
            )
        }

        @Test("An all-day event (date, not dateTime) is flagged isAllDay")
        func allDayEvent() throws {
            let dto = try decode("""
            {
                "id": "evt-allday",
                "status": "confirmed",
                "summary": "Holiday",
                "start": {"date": "2026-07-27"},
                "end": {"date": "2026-07-28"}
            }
            """)

            let mapped = GoogleEventMapper.map(dto, calendarId: calendarId, calendarTitle: calendarTitle)
            let event = try #require(mapped)
            #expect(event.isAllDay == true)
        }

        @Test("A cancelled event is skipped")
        func cancelledEventIsSkipped() throws {
            let dto = try decode("""
            {
                "id": "evt-cancelled",
                "status": "cancelled",
                "summary": "Old meeting",
                "start": {"dateTime": "2026-07-27T10:00:00Z"},
                "end": {"dateTime": "2026-07-27T10:30:00Z"}
            }
            """)

            #expect(GoogleEventMapper.map(dto, calendarId: calendarId, calendarTitle: calendarTitle) == nil)
        }

        @Test("A transparent (free) event is skipped as not busy")
        func transparentEventIsSkipped() throws {
            let dto = try decode("""
            {
                "id": "evt-transparent",
                "status": "confirmed",
                "summary": "Optional webinar",
                "transparency": "transparent",
                "start": {"dateTime": "2026-07-27T10:00:00Z"},
                "end": {"dateTime": "2026-07-27T10:30:00Z"}
            }
            """)

            #expect(GoogleEventMapper.map(dto, calendarId: calendarId, calendarTitle: calendarTitle) == nil)
        }

        @Test("Two occurrences of the same recurring event id get distinct composite ids")
        func recurringOccurrencesStayUnique() throws {
            let first = try decode("""
            {
                "id": "recurring-1",
                "status": "confirmed",
                "summary": "Standup",
                "start": {"dateTime": "2026-07-27T09:00:00Z"},
                "end": {"dateTime": "2026-07-27T09:15:00Z"}
            }
            """)
            let second = try decode("""
            {
                "id": "recurring-1",
                "status": "confirmed",
                "summary": "Standup",
                "start": {"dateTime": "2026-07-28T09:00:00Z"},
                "end": {"dateTime": "2026-07-28T09:15:00Z"}
            }
            """)

            let firstEvent = try #require(
                GoogleEventMapper.map(first, calendarId: calendarId, calendarTitle: calendarTitle)
            )
            let secondEvent = try #require(
                GoogleEventMapper.map(second, calendarId: calendarId, calendarTitle: calendarTitle)
            )

            #expect(firstEvent.id != secondEvent.id)
        }
    }

    @Suite("Composite event id")
    struct EventIdentifierTests {
        @Test("A composite id round-trips back to its calendar id and event id")
        func roundTrips() {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let identifier = GoogleEventIdentifier.make(calendarId: "primary", eventId: "evt-42", start: start)

            let parsed = GoogleEventIdentifier.parse(identifier)
            #expect(parsed?.calendarId == "primary")
            #expect(parsed?.eventId == "evt-42")
        }

        @Test("Round-trips when the calendar id is itself an email address")
        func roundTripsWithEmailCalendarID() {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            let identifier = GoogleEventIdentifier.make(
                calendarId: "person@gmail.com",
                eventId: "evt-99",
                start: start
            )

            let parsed = GoogleEventIdentifier.parse(identifier)
            #expect(parsed?.calendarId == "person@gmail.com")
            #expect(parsed?.eventId == "evt-99")
        }

        @Test("Anything not shaped like our composite id parses to nil")
        func rejectsForeignIdentifiers() {
            #expect(GoogleEventIdentifier.parse("apple-event-identifier#123") == nil)
            #expect(GoogleEventIdentifier.parse("google:onlyonepart") == nil)
            #expect(GoogleEventIdentifier.parse("") == nil)
        }
    }
}

#endif
